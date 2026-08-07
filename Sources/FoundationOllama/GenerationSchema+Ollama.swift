//
//  GenerationSchema+Ollama.swift
//  FoundationOllama
//
//  Created by Radion Rusnak on 07.08.2026.
//

import Foundation
import FoundationModels
import Ollama

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
extension GenerationSchema {
    var ollamaValue: Ollama.Value {
        get throws {
            try Ollama.Value(self)
        }
    }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
extension GeneratedContent {
    var ollamaValue: Ollama.Value {
        get throws {
            try JSONDecoder().decode(Ollama.Value.self, from: Data(jsonString.utf8))
        }
    }
}

extension Ollama.Value {
    var jsonString: String {
        get throws {
            String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
        }
    }
}
