# anymodel-swift-agent

A minimal, provider-independent terminal chat agent written in Swift, built on [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel).

It keeps a multi-turn conversation with a language model and lets the model call tools (read a file, list a directory). Tool results go back to the model automatically, and the loop continues until the model replies with plain text. Then it waits for your next message.

The same agent runs against Anthropic (Claude), OpenAI, Google Gemini, Ollama, or Apple's on-device Foundation Models. Only the `LanguageModel` you pass to `Agent` changes.

## Requirements

- Swift 6.3+ toolchain (see `Package.swift`)
- macOS 14+ (macOS 26+ for Apple's on-device model)
- An API key for a hosted provider, a running [Ollama](https://ollama.com) server, or Apple Intelligence enabled

## Setup

Pick a provider with environment variables:

| Variable | Purpose |
| --- | --- |
| `LLM_PROVIDER` | `anthropic`, `openai`, `gemini`, `ollama` or `system` (Apple Foundation Models). Optional. |
| `LLM_MODEL` | Overrides the provider's default model. |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` | API key for the hosted providers. |
| `OLLAMA_BASE_URL` | Ollama server URL (default `http://localhost:11434`). |

If `LLM_PROVIDER` is unset, the agent uses the first provider whose API key is set. If no key is set, it falls back to Apple's on-device model.

```bash
export ANTHROPIC_API_KEY=sk-ant-...                        # Claude
LLM_PROVIDER=openai OPENAI_API_KEY=sk-... swift run         # OpenAI
LLM_PROVIDER=ollama LLM_MODEL=qwen3 swift run               # local Ollama
LLM_PROVIDER=system swift run                               # on-device, no key needed
```

## Run

```bash
swift run anymodel-swift-agent
```

You'll get an interactive prompt:

```
Chat with the agent (use 'ctrl-c' to quit)
You: what files are in Sources/anymodel-swift-agent?
tool: list_files(path: Sources/anymodel-swift-agent)
Agent: ...
```

## Project structure

- `Sources/AnyModelSwiftAgentSDK`: the reusable agent library
  - `Agent.swift`: the conversation loop on top of `LanguageModelSession`
  - `AgentTool.swift`: wraps each tool to echo its calls and report its errors back to the model
  - `ChatTerminal.swift`: terminal I/O (colored prompts, tool call display)
  - `Tools/`: built-in tools (`read_file`, `list_files`, `geocode` via CoreLocation, `historic_weather` via the [Open-Meteo archive API](https://open-meteo.com/en/docs/historical-weather-api))
- `Sources/anymodel-swift-agent`: the executable entry point; selects the language model and starts the agent
- `Tests/AnyModelSwiftAgentTests`: unit tests with a scripted `LanguageModel` and terminal

## Adding a tool

Tools are plain AnyLanguageModel (Foundation Models–compatible) `Tool` types with `@Generable` arguments:

```swift
struct AddTool: Tool {
    let name = "add"
    let description = "Returns the sum of two integers."

    @Generable
    struct Arguments {
        @Guide(description: "First operand")
        var a: Int
        @Guide(description: "Second operand")
        var b: Int
    }

    func call(arguments: Arguments) async throws -> String {
        "\(arguments.a + arguments.b)"
    }
}

let agent = Agent(model: model, tools: [ReadFileTool(), ListFilesTool(), AddTool()])
```

If a tool throws, the error goes back to the model as the tool result, so the model can recover.

## Test

```bash
swift test
```

## Dependencies

- [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel): a drop-in replacement for Apple's Foundation Models framework with support for many providers
