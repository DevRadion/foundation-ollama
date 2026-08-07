//
//  OllamaLanguageModel.swift
//  FoundationOllama
//
//  Created by Radion Rusnak on 07.08.2026.
//

import FoundationModels
import Ollama

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
public struct OllamaLanguageModel: LanguageModel, Sendable {
    public typealias Executor = OllamaLanguageModelExecutor

    public let id: Ollama.Model.ID
    public let modifiedAt: String
    public let size: Int64
    public let digest: String
    public let details: Ollama.Model.Details
    public let ollamaCapabilities: Set<Ollama.Model.Capability>

    public var capabilities: LanguageModelCapabilities {
        var capabilities: [LanguageModelCapabilities.Capability] = [.guidedGeneration]

        if ollamaCapabilities.contains(.tools) {
            capabilities.append(.toolCalling)
        }
        if supportsBooleanThinking {
            capabilities.append(.reasoning)
        }
        if ollamaCapabilities.contains(.vision) {
            capabilities.append(.vision)
        }

        return LanguageModelCapabilities(capabilities)
    }

    public let executorConfiguration: OllamaLanguageModelExecutor.Configuration

    var supportsBooleanThinking: Bool {
        ollamaCapabilities.contains(.thinking)
            && id.model.lowercased() != "gpt-oss"
            && details.family.lowercased() != "gptoss"
    }

    @MainActor
    public static func installed(
        using client: Ollama.Client = .default,
        options: [String: Ollama.Value] = [:],
        keepAlive: Ollama.KeepAlive = .default
    ) async throws -> [Self] {
        let installedModels = try await client.listModels().models
        var models: [Self] = []

        for installedModel in installedModels {
            let id = Ollama.Model.ID(rawValue: installedModel.name)!
            let modelInfo = try await client.showModel(id)

            guard modelInfo.capabilities.contains(.completion) else {
                continue
            }

            models.append(Self(
                installedModel: installedModel,
                ollamaCapabilities: modelInfo.capabilities,
                client: client,
                options: options,
                keepAlive: keepAlive
            ))
        }

        return models
    }

    @MainActor
    public static func load(
        _ id: Ollama.Model.ID,
        using client: Ollama.Client = .default,
        options: [String: Ollama.Value] = [:],
        keepAlive: Ollama.KeepAlive = .default
    ) async throws -> Self {
        guard let installedModel = try await client.listModels().models.first(where: {
            Ollama.Model.ID(rawValue: $0.name) == id
        }) else {
            throw FoundationOllamaError.modelNotInstalled(id.rawValue)
        }
        let modelInfo = try await client.showModel(id)
        guard modelInfo.capabilities.contains(.completion) else {
            throw FoundationOllamaError.modelDoesNotSupportCompletion(id.rawValue)
        }

        return Self(
            installedModel: installedModel,
            ollamaCapabilities: modelInfo.capabilities,
            client: client,
            options: options,
            keepAlive: keepAlive
        )
    }

    init(
        installedModel: Ollama.Client.ListModelsResponse.Model,
        ollamaCapabilities: Set<Ollama.Model.Capability>,
        client: Ollama.Client,
        options: [String: Ollama.Value],
        keepAlive: Ollama.KeepAlive
    ) {
        self.id = Ollama.Model.ID(rawValue: installedModel.name)!
        self.modifiedAt = installedModel.modifiedAt
        self.size = installedModel.size
        self.digest = installedModel.digest
        self.details = installedModel.details
        self.ollamaCapabilities = ollamaCapabilities
        self.executorConfiguration = .init(
            client: client,
            options: options,
            keepAlive: keepAlive
        )
    }
}
