//
//  ImageAttachment+Ollama.swift
//  FoundationOllama
//
//  Created by Radion Rusnak on 07.08.2026.
//

import Foundation
import FoundationModels
import ImageIO
import UniformTypeIdentifiers

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
extension Transcript.ImageAttachment {
    var pngData: Data {
        get throws {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                throw FoundationOllamaError.imageEncodingFailed
            }

            CGImageDestinationAddImage(destination, cgImage, [
                kCGImagePropertyOrientation: orientation.rawValue
            ] as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                throw FoundationOllamaError.imageEncodingFailed
            }

            return data as Data
        }
    }
}
