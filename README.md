# FoundationOllama

FoundationOllama connects an Ollama model to Apple's Foundation Models framework.
Use `LanguageModelSession` with models that run through a local or remote Ollama server.

## Requirements

- Xcode 27 or later
- iOS 27, macOS 27, Mac Catalyst 27, visionOS 27, or watchOS 27
- Ollama with at least one completion model

The custom `LanguageModel` provider API is beta in the OS 27 SDK.

## Installation

Add this repository as a Swift package.
Then add the `FoundationOllama` product to your target.

## Discover Models

```swift
import FoundationModels
import FoundationOllama

let models = try await OllamaLanguageModel.installed()
guard let model = models.first else {
    return
}

let session = LanguageModelSession(model: model)
let response = try await session.respond(to: "Explain Swift actors.")
print(response.content)
```

The default Ollama server is `http://localhost:11434`.

## Use Another Server

```swift
import Ollama

let client = Ollama.Client(
    host: URL(string: "http://192.168.1.10:11434")!
)
let models = try await OllamaLanguageModel.installed(using: client)
```

An iOS application needs the applicable local-network and transport-security declarations.
The Swift package cannot add these application declarations.

## Structured Output

```swift
@Generable
struct Answer {
    let summary: String
    let confidence: Double
}

let response = try await session.respond(
    to: "Summarize the input.",
    generating: Answer.self
)
```

## Capabilities

The package reads model capabilities from Ollama's `/api/show` endpoint.
It maps tool use, reasoning, and vision to the matching Foundation Models capabilities.
Ollama structured output supplies guided generation for completion models.

Reasoning levels map to Ollama's Boolean `think` option.
GPT-OSS reasoning is unavailable because `ollama-swift` 1.8.0 cannot send string reasoning levels.
Required tool mode buffers the response until Ollama returns a tool call.
Version 1.8.0 of `ollama-swift` cannot preserve parallel tool-call identity.
FoundationOllama rejects more than one tool call in a model turn.

## Network Configuration

Create an `Ollama.Client` with a custom `URLSession` to set timeouts, proxies, or session headers.
FoundationOllama uses `ollama-swift` for all Ollama API requests.
