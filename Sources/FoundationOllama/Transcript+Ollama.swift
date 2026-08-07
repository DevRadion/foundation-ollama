//
//  Transcript+Ollama.swift
//  FoundationOllama
//
//  Created by Radion Rusnak on 07.08.2026.
//

import Foundation
import FoundationModels
import Ollama

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
extension Transcript {
    func ollamaMessages(for model: OllamaLanguageModel) throws -> [Ollama.Chat.Message] {
        var messages: [Ollama.Chat.Message] = []
        var assistantContent = ""
        var assistantThinking = ""
        var assistantToolCalls: [Ollama.Chat.Message.ToolCall] = []

        func flushAssistant() {
            guard !assistantContent.isEmpty
                    || !assistantThinking.isEmpty
                    || !assistantToolCalls.isEmpty else {
                return
            }

            messages.append(.assistant(
                assistantContent,
                toolCalls: assistantToolCalls.isEmpty ? nil : assistantToolCalls,
                thinking: assistantThinking.isEmpty ? nil : assistantThinking
            ))
            assistantContent = ""
            assistantThinking = ""
            assistantToolCalls = []
        }

        for entry in self {
            switch entry {
            case .instructions(let instructions):
                flushAssistant()
                let content = try content(from: instructions.segments, for: model, entry: entry)
                messages.append(.system(content.text, images: content.images.isEmpty ? nil : content.images))

            case .prompt(let prompt):
                flushAssistant()
                let content = try content(from: prompt.segments, for: model, entry: entry)
                messages.append(.user(content.text, images: content.images.isEmpty ? nil : content.images))

            case .reasoning(let reasoning):
                if !assistantContent.isEmpty || !assistantToolCalls.isEmpty {
                    flushAssistant()
                }
                let content = try content(from: reasoning.segments, for: model, entry: entry)
                guard content.images.isEmpty else {
                    throw unsupported(entry)
                }
                assistantThinking += content.text

            case .response(let response):
                if !assistantContent.isEmpty {
                    flushAssistant()
                }
                let content = try content(from: response.segments, for: model, entry: entry)
                guard content.images.isEmpty else {
                    throw unsupported(entry)
                }
                assistantContent += content.text

            case .toolCalls(let calls):
                guard calls.count == 1 else {
                    throw FoundationOllamaError.parallelToolCallsUnsupported
                }
                for call in calls {
                    guard case .object(let arguments) = try call.arguments.ollamaValue else {
                        throw FoundationOllamaError.invalidToolArguments(call.toolName)
                    }

                    assistantToolCalls.append(.init(function: .init(
                        name: call.toolName,
                        arguments: arguments
                    )))
                }

            case .toolOutput(let output):
                flushAssistant()
                let content = try content(from: output.segments, for: model, entry: entry)
                guard content.images.isEmpty else {
                    throw unsupported(entry)
                }
                messages.append(.tool(content.text))
            @unknown default:
                throw unsupported(entry)
            }
        }

        flushAssistant()
        return messages
    }

    private func content(
        from segments: [Segment],
        for model: OllamaLanguageModel,
        entry: Entry
    ) throws -> (text: String, images: [Data]) {
        var text = ""
        var images: [Data] = []

        for segment in segments {
            switch segment {
            case .text(let segment):
                text += segment.content
            case .structure(let segment):
                text += segment.content.jsonString
            case .attachment(let segment):
                guard model.ollamaCapabilities.contains(.vision) else {
                    throw LanguageModelError.unsupportedCapability(.init(
                        capability: .vision,
                        debugDescription: "The selected Ollama model does not support images."
                    ))
                }
                switch segment.content {
                case .image(let image):
                    images.append(try image.pngData)
                @unknown default:
                    throw unsupported(entry)
                }
            case .custom:
                throw unsupported(entry)
            @unknown default:
                throw unsupported(entry)
            }
        }

        return (text, images)
    }

    private func unsupported(_ entry: Entry) -> LanguageModelError {
        .unsupportedTranscriptContent(.init(
            unsupportedContent: [entry],
            debugDescription: "The transcript contains content Ollama cannot represent."
        ))
    }
}
