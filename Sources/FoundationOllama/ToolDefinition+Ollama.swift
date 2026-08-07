//
//  ToolDefinition+Ollama.swift
//  FoundationOllama
//
//  Created by Radion Rusnak on 07.08.2026.
//

import FoundationModels
import Ollama

struct OllamaToolDefinition: Ollama.ToolProtocol {
    let value: Ollama.Value

    var schema: any (Codable & Sendable) {
        value
    }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
extension Transcript.ToolDefinition {
    var ollamaTool: OllamaToolDefinition {
        get throws {
            OllamaToolDefinition(value: [
                "type": "function",
                "function": [
                    "name": .string(name),
                    "description": .string(description),
                    "parameters": try parameters.ollamaValue,
                ],
            ])
        }
    }
}
