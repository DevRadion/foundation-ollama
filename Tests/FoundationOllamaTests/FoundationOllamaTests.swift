//
//  FoundationOllamaTests.swift
//  FoundationOllamaTests
//
//  Created by Radion Rusnak on 07.08.2026.
//

import Foundation
import FoundationModels
import CoreGraphics
import Ollama
import Testing
@testable import FoundationOllama

@Suite(.serialized)
struct FoundationOllamaTests {
    @MainActor
    @Test
    func discoversModelsAndGeneratesText() async throws {
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/tags":
                return response(to: request, body: Self.modelsJSON)
            case "/api/show":
                return response(to: request, body: Self.modelInfoJSON)
            case "/api/chat":
                return response(to: request, body: Self.chatJSON(content: "Hello from Ollama"))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let models = try await OllamaLanguageModel.installed(using: client)
        let model = try #require(models.first)

        #expect(model.id == "llama3.2")
        #expect(model.capabilities.contains(.guidedGeneration))
        #expect(model.capabilities.contains(.toolCalling))
        #expect(model.capabilities.contains(.reasoning))
        #expect(model.capabilities.contains(.vision))

        let session = LanguageModelSession(model: model)
        let result = try await session.respond(to: "Hello")

        #expect(result.content == "Hello from Ollama")
    }

    @MainActor
    @Test
    func executesFoundationModelsTool() async throws {
        var chatRequestCount = 0
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/tags":
                return response(to: request, body: Self.modelsJSON)
            case "/api/show":
                return response(to: request, body: Self.modelInfoJSON)
            case "/api/chat":
                defer { chatRequestCount += 1 }
                if chatRequestCount == 0 {
                    return response(to: request, body: Self.toolCallJSON)
                }
                return response(to: request, body: Self.chatJSON(content: "Tool returned value"))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let model = try #require(try await OllamaLanguageModel.installed(using: client).first)
        let session = LanguageModelSession(model: model, tools: [EchoTool()])
        let result = try await session.respond(to: "Use the echo tool")

        #expect(result.content == "Tool returned value")
        #expect(chatRequestCount == 2)
    }

    @MainActor
    @Test
    func rejectsParallelToolCallsBeforeExecutingTools() async throws {
        var chatRequestCount = 0
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/tags":
                return response(to: request, body: Self.modelsJSON)
            case "/api/show":
                return response(to: request, body: Self.modelInfoJSON)
            case "/api/chat":
                chatRequestCount += 1
                return response(to: request, body: Self.parallelToolCallsJSON)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let model = try #require(try await OllamaLanguageModel.installed(using: client).first)
        let session = LanguageModelSession(model: model, tools: [EchoTool()])

        await #expect(throws: FoundationOllamaError.self) {
            try await session.respond(to: "Call the tool twice")
        }
        #expect(chatRequestCount == 1)
    }

    @MainActor
    @Test
    func doesNotAdvertiseUnsupportedGPTOSSReasoning() async throws {
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/tags":
                return response(to: request, body: Self.gptOSSModelsJSON)
            case "/api/show":
                return response(to: request, body: Self.gptOSSModelInfoJSON)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let model = try #require(try await OllamaLanguageModel.installed(using: client).first)

        #expect(!model.capabilities.contains(.reasoning))
    }

    @Test
    func convertsGenerationSchemaToJSONSchema() throws {
        let value = try StructuredAnswer.generationSchema.ollamaValue
        let schema = try #require(value.objectValue)

        #expect(schema["type"]?.stringValue == "object")
        #expect(schema["properties"]?.objectValue?["answer"] != nil)
    }

    @MainActor
    @Test
    func generatesStructuredContentAndReasoning() async throws {
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/tags":
                return response(to: request, body: Self.modelsJSON)
            case "/api/show":
                return response(to: request, body: Self.modelInfoJSON)
            case "/api/chat":
                return response(to: request, body: Self.reasoningJSON)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let model = try #require(try await OllamaLanguageModel.installed(using: client).first)
        let session = LanguageModelSession(model: model)
        let result = try await session.respond(
            to: "Give an answer",
            generating: StructuredAnswer.self,
            contextOptions: .init(reasoningLevel: .light)
        )

        #expect(result.content.answer == "42")
        #expect(session.transcript.contains { entry in
            if case .reasoning = entry { true } else { false }
        })
    }

    @Test
    func encodesVisionAttachmentAsPNG() throws {
        let context = try #require(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let data = try Transcript.ImageAttachment(image).pngData

        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @MainActor
    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> Ollama.Client {
        MockURLProtocol.setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return Ollama.Client(
            session: URLSession(configuration: configuration),
            host: URL(string: "http://localhost:11434")!
        )
    }

    private func response(
        to request: URLRequest,
        body: String,
        statusCode: Int = 200
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static let modelsJSON = """
    {"models":[{"name":"llama3.2","modified_at":"2026-08-07T12:00:00Z","size":2000000000,"digest":"digest","details":{"format":"gguf","family":"llama","families":["llama"],"parameter_size":"3B","quantization_level":"Q4_K_M","parent_model":null}}]}
    """

    private static let modelInfoJSON = """
    {"modelfile":"","parameters":null,"template":"","details":{"format":"gguf","family":"llama","families":["llama"],"parameter_size":"3B","quantization_level":"Q4_K_M","parent_model":null},"model_info":{},"capabilities":["completion","tools","thinking","vision"]}
    """

    private static let toolCallJSON = """
    {"model":"llama3.2","created_at":"2026-08-07T12:00:00.000Z","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"echo","arguments":{"value":"value"}}}]},"done":false}
    {"model":"llama3.2","created_at":"2026-08-07T12:00:00.000Z","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":10,"eval_count":4}
    """ + "\n"

    private static let reasoningJSON = #"""
    {"model":"llama3.2","created_at":"2026-08-07T12:00:00.000Z","message":{"role":"assistant","content":"{\"answer\":\"42\"}","thinking":"Considering the answer."},"done":true,"prompt_eval_count":10,"eval_count":8}
    """# + "\n"

    private static let parallelToolCallsJSON = """
    {"model":"llama3.2","created_at":"2026-08-07T12:00:00.000Z","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"echo","arguments":{"value":"one"}}},{"function":{"name":"echo","arguments":{"value":"two"}}}]},"done":true,"prompt_eval_count":10,"eval_count":8}
    """ + "\n"

    private static let gptOSSModelsJSON = modelsJSON
        .replacingOccurrences(of: "llama3.2", with: "gpt-oss")
        .replacingOccurrences(of: "\"llama\"", with: "\"gptoss\"")

    private static let gptOSSModelInfoJSON = modelInfoJSON
        .replacingOccurrences(of: "\"llama\"", with: "\"gptoss\"")

    private static func chatJSON(content: String) -> String {
        """
        {"model":"llama3.2","created_at":"2026-08-07T12:00:00.000Z","message":{"role":"assistant","content":"\(content)"},"done":false}
        {"model":"llama3.2","created_at":"2026-08-07T12:00:00.000Z","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":10,"eval_count":4}
        """ + "\n"
    }
}

@Generable
private struct StructuredAnswer {
    let answer: String
}

private struct EchoTool: FoundationModels.Tool {
    let name = "echo"
    let description = "Returns the supplied value."

    @Generable
    struct Arguments {
        let value: String
    }

    func call(arguments: Arguments) async throws -> String {
        arguments.value
    }
}
