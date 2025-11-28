defmodule Langfuse do
  @moduledoc """
  Elixir SDK for Langfuse - LLM observability, tracing, and prompt management.

  ## Configuration

      config :langfuse,
        public_key: "pk-...",
        secret_key: "sk-...",
        host: "https://cloud.langfuse.com"  # optional, defaults to cloud

  ## Quick Start

      # Start a trace
      trace = Langfuse.trace(name: "my-llm-call", user_id: "user-123")

      # Add a generation (LLM call)
      generation = Langfuse.generation(trace,
        name: "chat-completion",
        model: "gpt-4",
        input: [%{role: "user", content: "Hello"}],
        output: %{role: "assistant", content: "Hi there!"}
      )

      # Score the trace
      Langfuse.score(trace, name: "quality", value: 0.9)

  """

  alias Langfuse.Ingestion

  @doc """
  Creates a new trace.

  ## Options

    * `:name` - Name of the trace (required)
    * `:user_id` - User identifier
    * `:session_id` - Session identifier for grouping traces
    * `:metadata` - Additional metadata map
    * `:tags` - List of tags
    * `:public` - Whether trace is publicly accessible
    * `:input` - Input data
    * `:output` - Output data

  ## Examples

      Langfuse.trace(name: "chat-request", user_id: "user-123")
      Langfuse.trace(name: "rag-pipeline", session_id: "session-456", tags: ["production"])

  """
  @spec trace(keyword()) :: Langfuse.Trace.t()
  defdelegate trace(opts), to: Langfuse.Trace, as: :new

  @doc """
  Creates a span within a trace or parent span.

  ## Options

    * `:name` - Name of the span (required)
    * `:input` - Input data
    * `:output` - Output data
    * `:metadata` - Additional metadata map
    * `:level` - Log level (debug, default, warning, error)
    * `:status_message` - Status message

  """
  @spec span(Langfuse.Trace.t() | Langfuse.Span.t(), keyword()) :: Langfuse.Span.t()
  defdelegate span(parent, opts), to: Langfuse.Span, as: :new

  @doc """
  Creates a generation (LLM call) within a trace or parent span.

  ## Options

    * `:name` - Name of the generation (required)
    * `:model` - Model name (e.g., "gpt-4", "claude-3-opus")
    * `:input` - Input messages/prompt
    * `:output` - Output completion
    * `:usage` - Token usage map with `:input`, `:output`, `:total`
    * `:metadata` - Additional metadata map
    * `:model_parameters` - Model parameters (temperature, etc.)

  """
  @spec generation(Langfuse.Trace.t() | Langfuse.Span.t(), keyword()) :: Langfuse.Generation.t()
  defdelegate generation(parent, opts), to: Langfuse.Generation, as: :new

  @doc """
  Creates an event within a trace or parent span.

  ## Options

    * `:name` - Name of the event (required)
    * `:input` - Input data
    * `:output` - Output data
    * `:metadata` - Additional metadata map
    * `:level` - Log level

  """
  @spec event(Langfuse.Trace.t() | Langfuse.Span.t(), keyword()) :: Langfuse.Event.t()
  defdelegate event(parent, opts), to: Langfuse.Event, as: :new

  @doc """
  Scores a trace, observation, or session.

  ## Options

    * `:name` - Score name (required)
    * `:value` - Numeric value for numeric scores
    * `:string_value` - String value for categorical scores
    * `:data_type` - One of :numeric, :categorical, :boolean
    * `:comment` - Optional comment

  """
  @spec score(Langfuse.Trace.t() | Langfuse.Span.t() | Langfuse.Generation.t(), keyword()) ::
          :ok | {:error, term()}
  defdelegate score(target, opts), to: Langfuse.Score, as: :create

  @doc """
  Updates a span or generation with output and end time.

  ## Options

    * `:output` - Output data
    * `:status_message` - Status message
    * `:level` - Log level
    * `:usage` - Token usage (for generations)

  """
  @spec update(Langfuse.Span.t() | Langfuse.Generation.t(), keyword()) ::
          Langfuse.Span.t() | Langfuse.Generation.t()
  def update(%Langfuse.Span{} = span, opts), do: Langfuse.Span.update(span, opts)
  def update(%Langfuse.Generation{} = gen, opts), do: Langfuse.Generation.update(gen, opts)

  @doc """
  Ends a span or generation, setting the end time.
  """
  @spec end_observation(Langfuse.Span.t() | Langfuse.Generation.t()) ::
          Langfuse.Span.t() | Langfuse.Generation.t()
  def end_observation(%Langfuse.Span{} = span), do: Langfuse.Span.end_span(span)
  def end_observation(%Langfuse.Generation{} = gen), do: Langfuse.Generation.end_generation(gen)

  @doc """
  Flushes all pending events to Langfuse.
  Blocks until all events are sent or timeout is reached.

  ## Options

    * `:timeout` - Maximum time to wait in milliseconds (default: 5000)

  """
  @spec flush(keyword()) :: :ok | {:error, :timeout}
  def flush(opts \\ []) do
    Ingestion.flush(opts)
  end

  @doc """
  Shuts down the Langfuse client gracefully, flushing all pending events.
  """
  @spec shutdown() :: :ok
  def shutdown do
    Ingestion.shutdown()
  end
end
