//
//  OllamaLanguageModelExecutor.swift
//  FoundationOllama
//
//  Created by Radion Rusnak on 07.08.2026.
//

import Foundation
import FoundationModels
import Ollama

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
public struct OllamaLanguageModelExecutor: LanguageModelExecutor, Sendable {
    private enum OutputEntry {
        case reasoning
        case response
        case toolCalls
    }

    private struct OutputState {
        var lastEntry: OutputEntry?
        var pendingToolCall: (name: String, arguments: String)?
    }

    public struct Configuration: Hashable, Sendable {
        let client: Ollama.Client
        let clientID: ObjectIdentifier
        let options: [String: Ollama.Value]
        let keepAlive: Ollama.KeepAlive

        init(
            client: Ollama.Client,
            options: [String: Ollama.Value],
            keepAlive: Ollama.KeepAlive
        ) {
            self.client = client
            self.clientID = ObjectIdentifier(client)
            self.options = options
            self.keepAlive = keepAlive
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.clientID == rhs.clientID
                && lhs.options == rhs.options
                && lhs.keepAlive == rhs.keepAlive
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(clientID)
            hasher.combine(options)
            hasher.combine(keepAlive)
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: OllamaLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        do {
            try await performResponse(
                to: request,
                model: model,
                streamingInto: channel
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch Ollama.Client.Error.responseError(let response, let detail)
                    where response.statusCode == 429 {
            throw LanguageModelError.rateLimited(.init(
                resetDate: nil,
                debugDescription: detail
            ))
        } catch let error as URLError where error.code == .timedOut {
            throw LanguageModelError.timeout(.init(debugDescription: error.localizedDescription))
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }

    private func performResponse(
        to request: LanguageModelExecutorGenerationRequest,
        model: OllamaLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let reasoningRequested = request.contextOptions.reasoningLevel != nil
        if reasoningRequested && !model.supportsBooleanThinking {
            throw LanguageModelError.unsupportedCapability(.init(
                capability: .reasoning,
                debugDescription: "The selected Ollama model does not support reasoning."
            ))
        }

        let toolMode = request.generationOptions.toolCallingMode?.kind
        let toolsEnabled = toolMode != .disallowed && !request.enabledToolDefinitions.isEmpty
        if toolsEnabled && !model.ollamaCapabilities.contains(.tools) {
            throw LanguageModelError.unsupportedCapability(.init(
                capability: .toolCalling,
                debugDescription: "The selected Ollama model does not support tools."
            ))
        }

        let format: Ollama.Value?
        do {
            format = try request.schema?.ollamaValue
        } catch {
            throw LanguageModelError.unsupportedGenerationGuide(.init(
                schemaName: request.schema?.name,
                debugDescription: error.localizedDescription
            ))
        }

        let tools: [any Ollama.ToolProtocol]?
        do {
            tools = toolsEnabled
                ? try request.enabledToolDefinitions.map { try $0.ollamaTool }
                : nil
        } catch {
            throw LanguageModelError.unsupportedGenerationGuide(.init(
                schemaName: nil,
                debugDescription: "An Ollama tool schema could not be created: \(error.localizedDescription)"
            ))
        }
        let stream = try await configuration.client.chatStream(
            model: model.id,
            messages: try request.transcript.ollamaMessages(for: model),
            options: ollamaOptions(from: request.generationOptions),
            format: format,
            tools: tools,
            think: reasoningRequested ? true : nil,
            keepAlive: configuration.keepAlive
        )

        let requiredToolCall = toolMode == .required
        if requiredToolCall {
            var chunks: [Ollama.Client.ChatResponse] = []
            for try await chunk in stream {
                chunks.append(chunk)
            }
            try Task.checkCancellation()

            guard chunks.contains(where: { !($0.message.toolCalls ?? []).isEmpty }) else {
                throw FoundationOllamaError.requiredToolCallMissing
            }

            var state = OutputState()
            for chunk in chunks {
                state = try await emit(
                    chunk,
                    request: request,
                    channel: channel,
                    state: state
                )
            }
        } else {
            var state = OutputState()
            for try await chunk in stream {
                state = try await emit(
                    chunk,
                    request: request,
                    channel: channel,
                    state: state
                )
            }
            try Task.checkCancellation()
        }
    }

    private func ollamaOptions(from options: GenerationOptions) -> [String: Ollama.Value] {
        var values = configuration.options

        if let temperature = options.temperature {
            values["temperature"] = .double(temperature)
        }
        if let maximumResponseTokens = options.maximumResponseTokens {
            values["num_predict"] = .int(maximumResponseTokens)
        }

        switch options.samplingMode?.kind {
        case .greedy:
            values["temperature"] = .double(0)
        case .randomTopK(let topK, let seed):
            values["top_k"] = .int(topK)
            if let seed {
                values["seed"] = .int(Int(clamping: seed))
            }
        case .randomProbabilityThreshold(let threshold, let seed):
            values["top_p"] = .double(threshold)
            if let seed {
                values["seed"] = .int(Int(clamping: seed))
            }
        case nil:
            break
        @unknown default:
            break
        }

        return values
    }

    private func emit(
        _ chunk: Ollama.Client.ChatResponse,
        request: LanguageModelExecutorGenerationRequest,
        channel: LanguageModelExecutorGenerationChannel,
        state initialState: OutputState
    ) async throws -> OutputState {
        let requestID = request.id.uuidString
        var state = initialState

        if let thinking = chunk.message.thinking, !thinking.isEmpty {
            await channel.send(.reasoning(
                entryID: "\(requestID)-reasoning",
                action: .appendText(thinking, tokenCount: 0)
            ))
            state.lastEntry = .reasoning
        }

        if !chunk.message.content.isEmpty {
            await channel.send(.response(
                entryID: "\(requestID)-response",
                action: .appendText(chunk.message.content, tokenCount: 0)
            ))
            state.lastEntry = .response
        }

        for toolCall in chunk.message.toolCalls ?? [] {
            guard state.pendingToolCall == nil else {
                throw FoundationOllamaError.parallelToolCallsUnsupported
            }
            let arguments = try Ollama.Value.object(toolCall.function.arguments).jsonString
            state.pendingToolCall = (toolCall.function.name, arguments)
        }

        if chunk.done, let toolCall = state.pendingToolCall {
            await channel.send(.toolCalls(
                entryID: "\(requestID)-tools",
                action: .toolCall(
                    id: "\(requestID)-tool-0",
                    name: toolCall.name,
                    action: .appendArguments(toolCall.arguments, tokenCount: 0)
                )
            ))
            state.lastEntry = .toolCalls
            state.pendingToolCall = nil
        }

        if chunk.done, let lastEntry = state.lastEntry {
            let metadata: [String: any Sendable & Codable & Equatable] = [
                "model": chunk.model.rawValue,
                "requestID": requestID,
            ]
            let inputUsage = LanguageModelExecutorGenerationChannel.Usage.Input(
                totalTokenCount: chunk.promptEvalCount ?? 0,
                cachedTokenCount: 0
            )
            let outputUsage = LanguageModelExecutorGenerationChannel.Usage.Output(
                totalTokenCount: chunk.evalCount ?? 0,
                reasoningTokenCount: 0
            )

            switch lastEntry {
            case .toolCalls:
                await channel.send(.toolCalls(
                    entryID: "\(requestID)-tools",
                    action: .updateMetadata(metadata)
                ))
                await channel.send(.toolCalls(
                    entryID: "\(requestID)-tools",
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                ))
            case .reasoning:
                await channel.send(.reasoning(
                    entryID: "\(requestID)-reasoning",
                    action: .updateMetadata(metadata)
                ))
                await channel.send(.reasoning(
                    entryID: "\(requestID)-reasoning",
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                ))
            case .response:
                await channel.send(.response(
                    entryID: "\(requestID)-response",
                    action: .updateMetadata(metadata)
                ))
                await channel.send(.response(
                    entryID: "\(requestID)-response",
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                ))
            }
        }

        return state
    }
}
