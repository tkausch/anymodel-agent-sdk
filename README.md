# anymodel-swift-agent

A minimal terminal chat agent in Swift that works with any language model provider. It's built on [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel).

The agent keeps a multi-turn conversation with a language model and lets the model call tools. Tool results go back to the model automatically, and the loop continues until the model replies with plain text. Then it waits for your next message.

The same agent runs against Anthropic (Claude), OpenAI, Google Gemini, Ollama, or Apple's on-device Foundation Models. Only the `LanguageModel` you pass to `Agent` changes.

The package has two products:

- **`AnyModelSwiftAgentSDK`**: a library with the agent loop, the terminal UI and the built-in tools.
- **`anymodel-swift-agent`**: a command-line program that picks a model from environment variables and starts a chat with the built-in tools.

## Requirements

- Swift 6.3+ toolchain
- macOS 14+ (macOS 26+ for Apple's on-device model)
- An API key for a hosted provider, a running [Ollama](https://ollama.com) server, or Apple Intelligence turned on
- A network connection for the built-in tools

## Choose a model

The command-line program reads these environment variables:

| Variable | Purpose |
| --- | --- |
| `LLM_PROVIDER` | `anthropic`, `openai`, `gemini`, `ollama` or `system` (Apple Foundation Models). Optional. |
| `LLM_MODEL` | Overrides the provider's default model. |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` | API key for the hosted providers. |
| `OLLAMA_BASE_URL` | Ollama server URL (default `http://localhost:11434`). |

If `LLM_PROVIDER` is unset, the program uses the first provider whose API key is set, checking Anthropic, then OpenAI, then Gemini. If no key is set, it uses Apple's on-device model.

Default models:

| Provider | Default model |
| --- | --- |
| `anthropic` | `claude-opus-4-8` |
| `openai` | `gpt-5` |
| `gemini` | `gemini-2.5-flash` |
| `ollama` | `qwen3` |
| `system` | Apple's default on-device model |

## Run

```bash
export ANTHROPIC_API_KEY=sk-ant-...
swift run anymodel-swift-agent
```

Other providers:

```bash
LLM_PROVIDER=openai OPENAI_API_KEY=sk-... swift run anymodel-swift-agent
LLM_PROVIDER=ollama LLM_MODEL=llama3.2 swift run anymodel-swift-agent
LLM_PROVIDER=system swift run anymodel-swift-agent    # on-device, no key needed
```

Each tool call is shown as it happens:

```
Chat with the agent (use 'ctrl-c' to quit)
You: How warm was it in Berlin on 1 June 2024?
tool: geocode(address: Berlin)
tool: historic_weather(latitude: 52.5244, longitude: 13.4105, startDate: 2024-06-01, endDate: 2024-06-01)
Agent: ...
```

Press ctrl-c to quit, or ctrl-d to end the chat.

## Built-in tools

| Tool | Type | What it does |
| --- | --- | --- |
| `geocode` | `GeoCodingTool` | Turns a city name or address into coordinates using Apple's CoreLocation geocoder. Returns every match so the model can pick one or ask you. |
| `historic_weather` | `HistoricWeatherTool` | Gets past hourly air temperatures for coordinates and a date range from the [Open-Meteo archive API](https://open-meteo.com/en/docs/historical-weather-api). Returns daily min / mean / max, plus hourly readings for ranges of up to 3 days. |

Together they answer questions like "What was the weather in Zurich last Christmas?": the model calls `geocode` first, then passes the coordinates to `historic_weather`. Neither tool needs an API key.

## Use the library

Add the package as a dependency, replacing the URL with this repository's URL:

```swift
.package(url: "https://github.com/<owner>/anymodel-swift-agent", branch: "main"),
```

Then add the `AnyModelSwiftAgentSDK` product to your target. Create any AnyLanguageModel `LanguageModel` and start the agent:

```swift
import AnyLanguageModel
import AnyModelSwiftAgentSDK

let model = AnthropicLanguageModel(apiKey: apiKey, model: "claude-opus-4-8")
let agent = Agent(
    model: model,
    tools: [GeoCodingTool(), HistoricWeatherTool()],
    instructions: "You are a helpful weather assistant.",
    options: GenerationOptions(maximumResponseTokens: 8096)
)
try await agent.run()
```

`run()` reads messages from standard input and prints replies until standard input ends.

## Add a tool

A tool is an AnyLanguageModel `Tool` with `@Generable` arguments, the same as in Apple's Foundation Models:

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

let agent = Agent(model: model, tools: [GeoCodingTool(), HistoricWeatherTool(), AddTool()])
```

`Agent` wraps every tool so that:

- each call is printed to the terminal
- each call is logged with its arguments, duration and result size
- an error thrown by a tool goes back to the model as the tool's result (`Error: ...`) instead of ending the turn, so the model can recover

To report a failure from your own tool, throw `ToolError.invalidInput` or `ToolError.executionFailed("reason")`.

## Logs

Tool calls are logged with Apple's unified logging, under subsystem `AnyModelSwiftAgentSDK` and category `tools`. To watch them while the agent runs:

```bash
log stream --level info --predicate 'subsystem == "AnyModelSwiftAgentSDK"'
```

## Project structure

- `Sources/AnyModelSwiftAgentSDK`: the library
  - `Agent.swift`: the conversation loop on top of `LanguageModelSession`. Some providers (Anthropic, Ollama) stop after a tool call without replying, so the agent asks the model to continue until it answers in text.
  - `AgentTool.swift`: the tool wrapper (terminal display, logging, errors) and `ToolError`
  - `ChatTerminal.swift`: terminal input and output with colored prompts
  - `Tools/`: `GeoCodingTool` and `HistoricWeatherTool`
- `Sources/anymodel-swift-agent/main.swift`: the command-line program; picks the model from the environment and starts the agent
- `Tests/AnyModelSwiftAgentTests`: unit tests that use a scripted mock `LanguageModel` and terminal, so they don't call any provider

## Test

```bash
swift test
```

## Dependencies

- [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel) (0.13.0+): works like Apple's Foundation Models framework, and supports many providers
