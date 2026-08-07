//
//  FoundationOllamaError.swift
//  FoundationOllama
//
//  Created by Radion Rusnak on 07.08.2026.
//

import Foundation

public enum FoundationOllamaError: LocalizedError, Sendable {
    case modelNotInstalled(String)
    case modelDoesNotSupportCompletion(String)
    case imageEncodingFailed
    case invalidToolArguments(String)
    case parallelToolCallsUnsupported
    case requiredToolCallMissing

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let model):
            "Ollama model '\(model)' is not installed."
        case .modelDoesNotSupportCompletion(let model):
            "Ollama model '\(model)' does not support text completion."
        case .imageEncodingFailed:
            "The image could not be encoded for Ollama."
        case .invalidToolArguments(let tool):
            "Ollama returned invalid arguments for tool '\(tool)'."
        case .parallelToolCallsUnsupported:
            "ollama-swift 1.8.0 cannot preserve parallel tool-call identity."
        case .requiredToolCallMissing:
            "The model did not call a required tool."
        }
    }
}
