# Langfuse

[![Hex.pm](https://img.shields.io/hexpm/v/langfuse.svg)](https://hex.pm/packages/langfuse)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/langfuse)

Community Elixir SDK for [Langfuse](https://langfuse.com) - Open source LLM observability, tracing, and prompt management.

> **Note**: This is an unofficial community-maintained SDK, not affiliated with or endorsed by Langfuse GmbH.

## Features

- **Tracing** - Create traces, spans, generations, and events for LLM observability
- **Scoring** - Attach numeric, categorical, and boolean scores to traces and observations
- **Sessions** - Group related traces into conversations
- **Prompts** - Fetch, cache, and compile version-controlled prompts
- **Client API** - Full REST API access for datasets, models, and management
- **OpenTelemetry** - Optional integration for distributed tracing
- **Instrumentation** - Macros for automatic function tracing
- **Data Masking** - Redact sensitive data before sending to Langfuse
- **Async Batching** - Non-blocking event ingestion with configurable batching

## Installation

Add `langfuse` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:langfuse, "~> 0.1.0"}
  ]
end
```

For OpenTelemetry integration, add the optional dependencies:

```elixir
def deps do
  [
    {:langfuse, "~> 0.1.0"},
    {:opentelemetry_api, "~> 1.4"},
    {:opentelemetry, "~> 1.5"}
  ]
end
```

## Configuration

Configure Langfuse in your `config/config.exs`:

```elixir
config :langfuse,
  public_key: "pk-...",
  secret_key: "sk-...",
  host: "https://cloud.langfuse.com"
```

Or use environment variables:

```bash
export LANGFUSE_PUBLIC_KEY="pk-..."
export LANGFUSE_SECRET_KEY="sk-..."
export LANGFUSE_HOST="https://cloud.langfuse.com"
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `public_key` | string | - | Langfuse public key (or `LANGFUSE_PUBLIC_KEY`) |
| `secret_key` | string | - | Langfuse secret key (or `LANGFUSE_SECRET_KEY`) |
| `host` | string | `https://cloud.langfuse.com` | Langfuse API host |
| `environment` | string | `nil` | Environment tag (e.g., "production", "staging") |
| `enabled` | boolean | `true` | Enable/disable SDK |
| `flush_interval` | integer | `5000` | Batch flush interval in ms |
| `batch_size` | integer | `100` | Maximum events per batch |
| `max_retries` | integer | `3` | HTTP retry attempts |
| `debug` | boolean | `false` | Enable debug logging |
| `mask_fn` | function | `nil` | Custom function for masking sensitive data |

## Quick Start

### Tracing

```elixir
trace = Langfuse.trace(
  name: "chat-request",
  user_id: "user-123",
  metadata: %{source: "api"},
  version: "1.0.0",
  release: "2025-01-15"
)

span = Langfuse.span(trace,
  name: "document-retrieval",
  type: :retriever,
  input: %{query: "test"}
)
span = Langfuse.update(span, output: retrieved_docs)
span = Langfuse.end_observation(span)

generation = Langfuse.generation(trace,
  name: "chat-completion",
  model: "gpt-4",
  input: [%{role: "user", content: "Hello"}],
  model_parameters: %{temperature: 0.7}
)

generation = Langfuse.update(generation,
  output: %{role: "assistant", content: "Hi there!"},
  usage: %{input: 10, output: 5, total: 15}
)
generation = Langfuse.end_observation(generation)

Langfuse.score(trace, name: "quality", value: 0.9)
```

### Span Types

Spans support semantic types for better organization in the Langfuse UI:

```elixir
Langfuse.span(trace, name: "agent-loop", type: :agent)
Langfuse.span(trace, name: "tool-call", type: :tool)
Langfuse.span(trace, name: "rag-chain", type: :chain)
Langfuse.span(trace, name: "doc-search", type: :retriever)
Langfuse.span(trace, name: "embed-text", type: :embedding)
Langfuse.span(trace, name: "generic-step", type: :default)
```

### Sessions

Group related traces into sessions:

```elixir
session_id = Langfuse.Session.new_id()

trace1 = Langfuse.trace(name: "turn-1", session_id: session_id)
trace2 = Langfuse.trace(name: "turn-2", session_id: session_id)

Langfuse.Session.score(session_id, name: "satisfaction", value: 4.5)
```

### Prompts

Fetch and use prompts from Langfuse:

```elixir
{:ok, prompt} = Langfuse.Prompt.get("my-prompt")
{:ok, prompt} = Langfuse.Prompt.get("my-prompt", version: 2)
{:ok, prompt} = Langfuse.Prompt.get("my-prompt", label: "production")

compiled = Langfuse.Prompt.compile(prompt, %{name: "Alice", topic: "weather"})

generation = Langfuse.generation(trace,
  name: "chat",
  prompt_name: prompt.name,
  prompt_version: prompt.version,
  input: compiled
)
```

Prompts are cached by default. To invalidate:

```elixir
Langfuse.Prompt.invalidate("my-prompt")
Langfuse.Prompt.invalidate("my-prompt", version: 2)
Langfuse.Prompt.invalidate_all()
```

Use fallback prompts when fetch fails:

```elixir
fallback = %Langfuse.Prompt{
  name: "my-prompt",
  prompt: "Default template: {{name}}",
  type: :text
}

{:ok, prompt} = Langfuse.Prompt.get("my-prompt", fallback: fallback)
```

### Scores

Score traces, observations, or sessions:

```elixir
Langfuse.score(trace, name: "quality", value: 0.85)

Langfuse.score(trace,
  name: "sentiment",
  string_value: "positive",
  data_type: :categorical
)

Langfuse.score(trace,
  name: "hallucination",
  value: false,
  data_type: :boolean
)

Langfuse.score(trace,
  name: "feedback",
  value: 5,
  comment: "Excellent response",
  metadata: %{reviewer: "human"}
)
```

## Client API

Direct access to Langfuse REST API:

```elixir
{:ok, _} = Langfuse.Client.auth_check()

{:ok, dataset} = Langfuse.Client.create_dataset(name: "eval-set")
{:ok, datasets} = Langfuse.Client.list_datasets()

{:ok, item} = Langfuse.Client.create_dataset_item(
  dataset_name: "eval-set",
  input: %{query: "test"},
  expected_output: %{answer: "response"}
)
{:ok, _} = Langfuse.Client.update_dataset_item(item["id"], status: "ARCHIVED")

{:ok, run} = Langfuse.Client.create_dataset_run(
  dataset_name: "eval-set",
  name: "experiment-1"
)

{:ok, model} = Langfuse.Client.create_model(
  model_name: "gpt-4-turbo",
  match_pattern: "(?i)^(gpt-4-turbo)$",
  input_price: 0.01,
  output_price: 0.03,
  unit: "TOKENS"
)
{:ok, models} = Langfuse.Client.list_models()

{:ok, observations} = Langfuse.Client.list_observations(trace_id: trace.id)
{:ok, observation} = Langfuse.Client.get_observation(observation_id)

{:ok, prompt} = Langfuse.Client.get_prompt("my-prompt", version: 1)

{:ok, config} = Langfuse.Client.create_score_config(
  name: "quality",
  data_type: "NUMERIC",
  min_value: 0,
  max_value: 1
)
```

## Instrumentation

Use macros for automatic function tracing:

```elixir
defmodule MyApp.Agent do
  use Langfuse.Instrumentation

  @trace name: "agent-run"
  def run(input) do
    process(input)
  end

  @span name: "process-step", type: :chain
  def process(input) do
    call_llm(input)
  end

  @generation name: "llm-call", model: "gpt-4"
  def call_llm(input) do
    # LLM call here
  end
end
```

## OpenTelemetry Integration

For applications using OpenTelemetry, Langfuse can receive spans via a custom span processor:

```elixir
config :opentelemetry,
  span_processor: {Langfuse.OpenTelemetry.SpanProcessor, []}
```

Or configure programmatically:

```elixir
Langfuse.OpenTelemetry.Setup.configure()
```

Map OpenTelemetry attributes to Langfuse fields:

```elixir
:otel_tracer.with_span "llm-call", %{attributes: %{
  "langfuse.type" => "generation",
  "langfuse.model" => "gpt-4",
  "langfuse.input" => Jason.encode!(messages),
  "langfuse.output" => Jason.encode!(response)
}} do
  # Your code here
end
```

See `Langfuse.OpenTelemetry` for full documentation.

## Data Masking

Redact sensitive data before sending to Langfuse:

```elixir
config :langfuse,
  mask_fn: &MyApp.Masking.mask/1
```

```elixir
defmodule MyApp.Masking do
  def mask(data) do
    Langfuse.Masking.mask(data,
      patterns: [
        ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
        ~r/\b\d{3}-\d{2}-\d{4}\b/
      ],
      replacement: "[REDACTED]"
    )
  end
end
```

Or use the built-in masking:

```elixir
config :langfuse,
  mask_fn: {Langfuse.Masking, :mask, [[
    patterns: [~r/secret_\w+/i],
    keys: ["password", "api_key", "token"]
  ]]}
```

## Telemetry

The SDK emits telemetry events for observability:

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:langfuse, :ingestion, :flush, :start\|:stop\|:exception]` | `duration` | `batch_size` |
| `[:langfuse, :http, :request, :start\|:stop\|:exception]` | `duration` | `method`, `path`, `status` |
| `[:langfuse, :prompt, :fetch, :start\|:stop\|:exception]` | `duration` | `name`, `version` |
| `[:langfuse, :prompt, :cache, :hit\|:miss]` | - | `name`, `version` |

```elixir
:telemetry.attach(
  "langfuse-logger",
  [:langfuse, :http, :request, :stop],
  fn _event, measurements, metadata, _config ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("Langfuse HTTP #{metadata.method} #{metadata.path}: #{duration_ms}ms")
  end,
  nil
)

Langfuse.Telemetry.attach_default_logger()
```

## Testing

The SDK provides helpers for testing applications that use Langfuse:

```elixir
config :langfuse, enabled: false
```

```elixir
defmodule MyApp.TracingTest do
  use ExUnit.Case
  import Langfuse.Testing

  setup do
    start_supervised!({Langfuse.Testing.EventCapture, []})
    :ok
  end

  test "traces are created" do
    MyApp.Agent.run("test input")

    assert_traced("agent-run")
    assert_generation_created("llm-call", model: "gpt-4")
  end
end
```

For mocking HTTP calls:

```elixir
Mox.defmock(Langfuse.HTTPMock, for: Langfuse.HTTPBehaviour)

config :langfuse, http_client: Langfuse.HTTPMock
```

## Graceful Shutdown

The SDK automatically flushes pending events on application shutdown. For explicit control:

```elixir
Langfuse.flush()

Langfuse.flush(timeout: 10_000)

Langfuse.shutdown()
```

## Runtime Configuration

Reload configuration at runtime (useful for feature flags):

```elixir
Application.put_env(:langfuse, :enabled, false)
Langfuse.Config.reload()
```

## License

MIT License - see [LICENSE](LICENSE) for details.
