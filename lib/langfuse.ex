defmodule Langfuse do
  @moduledoc """
  Elixir SDK for Langfuse - open source LLM observability platform.

  This module provides the primary interface for tracing LLM applications,
  recording generations, scoring outputs, and managing prompts. All tracing
  operations are non-blocking and batched for efficient API communication.

  ## Configuration

  Configure Langfuse in your application config:

      config :langfuse,
        public_key: "pk-lf-...",
        secret_key: "sk-lf-...",
        host: "https://cloud.langfuse.com",
        flush_interval: 5_000,
        batch_size: 100,
        enabled: true

  Or via environment variables `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`,
  and `LANGFUSE_HOST`.

  ## Tracing

  Traces are the top-level containers for observability data. Each trace
  can contain multiple observations: spans, generations, and events.

      trace = Langfuse.trace(name: "chat-request", user_id: "user-123")

      span = Langfuse.span(trace, name: "document-retrieval")
      span = Langfuse.end_observation(span)

      generation = Langfuse.generation(trace,
        name: "llm-call",
        model: "gpt-4",
        input: messages
      )
      generation = Langfuse.update(generation, output: response)
      generation = Langfuse.end_observation(generation)

  ## Scoring

  Attach evaluation scores to traces or observations:

      Langfuse.score(trace, name: "quality", value: 0.95)
      Langfuse.score(generation, name: "relevance", value: 0.8)

  ## Sessions

  Group related traces using session IDs:

      session_id = Langfuse.Session.new_id()
      trace1 = Langfuse.trace(name: "turn-1", session_id: session_id)
      trace2 = Langfuse.trace(name: "turn-2", session_id: session_id)

  ## Prompts

  Fetch and compile prompts from Langfuse:

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt")
      compiled = Langfuse.Prompt.compile(prompt, %{name: "Alice"})

  ## Graceful Shutdown

  The SDK automatically flushes pending events on shutdown. For explicit
  control:

      Langfuse.flush()
      Langfuse.shutdown()

  """

  alias Langfuse.Ingestion

  @doc """
  Creates a new trace.

  A trace represents a single request or operation in your LLM application.
  All observations (spans, generations, events) are nested within a trace.

  ## Options

    * `:name` - Name of the trace (required)
    * `:id` - Custom trace ID. Auto-generated if not provided.
    * `:user_id` - User identifier for filtering and analytics.
    * `:session_id` - Session identifier for grouping related traces.
    * `:metadata` - Arbitrary metadata as a map.
    * `:tags` - List of string tags for categorization.
    * `:public` - Whether the trace is publicly accessible via link.
    * `:input` - Input data for the trace.
    * `:output` - Output data for the trace.
    * `:version` - Application version string.
    * `:release` - Release identifier.

  ## Examples

      iex> trace = Langfuse.trace(name: "chat-request")
      iex> trace.name
      "chat-request"

      iex> trace = Langfuse.trace(
      ...>   name: "rag-pipeline",
      ...>   user_id: "user-123",
      ...>   session_id: "session-456",
      ...>   tags: ["production", "v2"],
      ...>   metadata: %{model: "gpt-4"}
      ...> )
      iex> trace.user_id
      "user-123"

  """
  @spec trace(keyword()) :: Langfuse.Trace.t()
  defdelegate trace(opts), to: Langfuse.Trace, as: :new

  @doc """
  Creates a span within a trace or parent span.

  Spans represent units of work with a start and end time. Use spans
  for operations like data retrieval, preprocessing, or any logical
  step in your pipeline.

  ## Options

    * `:name` - Name of the span (required)
    * `:id` - Custom span ID. Auto-generated if not provided.
    * `:input` - Input data for the span.
    * `:output` - Output data for the span.
    * `:metadata` - Arbitrary metadata as a map.
    * `:level` - Log level: `:debug`, `:default`, `:warning`, or `:error`.
    * `:status_message` - Status description, useful for errors.
    * `:start_time` - Custom start time. Defaults to now.
    * `:version` - Application version string.

  ## Examples

      iex> trace = Langfuse.trace(name: "pipeline")
      iex> span = Langfuse.span(trace, name: "retrieval")
      iex> span.name
      "retrieval"

      iex> trace = Langfuse.trace(name: "pipeline")
      iex> span = Langfuse.span(trace,
      ...>   name: "vector-search",
      ...>   input: %{query: "test"},
      ...>   metadata: %{index: "documents"}
      ...> )
      iex> span.input
      %{query: "test"}

  """
  @spec span(Langfuse.Trace.t() | Langfuse.Span.t(), keyword()) :: Langfuse.Span.t()
  defdelegate span(parent, opts), to: Langfuse.Span, as: :new

  @doc """
  Creates a generation within a trace or parent span.

  Generations are specialized observations for LLM API calls. They track
  model information, token usage, costs, and can be linked to prompts.

  ## Options

    * `:name` - Name of the generation (required)
    * `:id` - Custom generation ID. Auto-generated if not provided.
    * `:model` - Model identifier (e.g., "gpt-4", "claude-3-opus").
    * `:model_parameters` - Model parameters as a map (temperature, etc.).
    * `:input` - Input messages or prompt sent to the model.
    * `:output` - Model response/completion.
    * `:usage` - Token usage map with keys `:input`, `:output`, `:total`.
    * `:metadata` - Arbitrary metadata as a map.
    * `:level` - Log level: `:debug`, `:default`, `:warning`, or `:error`.
    * `:status_message` - Status description.
    * `:prompt_name` - Name of linked Langfuse prompt.
    * `:prompt_version` - Version of linked Langfuse prompt.
    * `:completion_start_time` - When streaming response started.
    * `:version` - Application version string.

  ## Examples

      iex> trace = Langfuse.trace(name: "chat")
      iex> gen = Langfuse.generation(trace,
      ...>   name: "completion",
      ...>   model: "gpt-4"
      ...> )
      iex> gen.model
      "gpt-4"

      iex> trace = Langfuse.trace(name: "chat")
      iex> gen = Langfuse.generation(trace,
      ...>   name: "completion",
      ...>   model: "gpt-4",
      ...>   input: [%{role: "user", content: "Hello"}],
      ...>   model_parameters: %{temperature: 0.7}
      ...> )
      iex> gen.model_parameters
      %{temperature: 0.7}

  """
  @spec generation(Langfuse.Trace.t() | Langfuse.Span.t(), keyword()) :: Langfuse.Generation.t()
  defdelegate generation(parent, opts), to: Langfuse.Generation, as: :new

  @doc """
  Creates an event within a trace or parent span.

  Events are point-in-time occurrences without duration. Use events
  to mark discrete happenings like user actions, errors, or milestones.

  ## Options

    * `:name` - Name of the event (required)
    * `:id` - Custom event ID. Auto-generated if not provided.
    * `:input` - Input data for the event.
    * `:output` - Output data for the event.
    * `:metadata` - Arbitrary metadata as a map.
    * `:level` - Log level: `:debug`, `:default`, `:warning`, or `:error`.
    * `:status_message` - Status description.
    * `:start_time` - Event timestamp. Defaults to now.
    * `:version` - Application version string.

  ## Examples

      iex> trace = Langfuse.trace(name: "session")
      iex> event = Langfuse.event(trace, name: "user-click")
      iex> event.name
      "user-click"

  """
  @spec event(Langfuse.Trace.t() | Langfuse.Span.t(), keyword()) :: Langfuse.Event.t()
  defdelegate event(parent, opts), to: Langfuse.Event, as: :new

  @doc """
  Attaches a score to a trace, span, or generation.

  Scores are evaluation metrics that can be numeric, categorical, or boolean.
  They enable quality tracking and filtering in the Langfuse dashboard.

  ## Options

    * `:name` - Score name (required). Examples: "accuracy", "relevance".
    * `:value` - Numeric value for numeric/boolean scores.
    * `:string_value` - String value for categorical scores.
    * `:data_type` - Score type: `:numeric`, `:categorical`, or `:boolean`.
      Auto-inferred if not provided.
    * `:comment` - Free-text comment or reasoning.
    * `:id` - Custom score ID for idempotent updates.
    * `:config_id` - Reference to a score configuration.

  ## Examples

      iex> trace = Langfuse.trace(name: "chat")
      iex> Langfuse.score(trace, name: "quality", value: 0.95)
      :ok

      iex> trace = Langfuse.trace(name: "chat")
      iex> Langfuse.score(trace,
      ...>   name: "sentiment",
      ...>   string_value: "positive",
      ...>   data_type: :categorical
      ...> )
      :ok

      iex> trace = Langfuse.trace(name: "chat")
      iex> Langfuse.score(trace,
      ...>   name: "factual",
      ...>   value: true,
      ...>   data_type: :boolean,
      ...>   comment: "Verified against source"
      ...> )
      :ok

  """
  @spec score(Langfuse.Trace.t() | Langfuse.Span.t() | Langfuse.Generation.t(), keyword()) ::
          :ok | {:error, term()}
  defdelegate score(target, opts), to: Langfuse.Score, as: :create

  @doc """
  Updates a span or generation with additional data.

  Use this to add output, change status, or update metadata after
  the observation was created.

  ## Options

    * `:output` - Output data to record.
    * `:metadata` - Additional metadata to merge.
    * `:level` - Log level: `:debug`, `:default`, `:warning`, or `:error`.
    * `:status_message` - Status description.
    * `:usage` - Token usage map (generations only).

  ## Examples

      iex> trace = Langfuse.trace(name: "chat")
      iex> span = Langfuse.span(trace, name: "process")
      iex> span = Langfuse.update(span, output: %{result: "done"})
      iex> span.output
      %{result: "done"}

  """
  @spec update(Langfuse.Span.t() | Langfuse.Generation.t(), keyword()) ::
          Langfuse.Span.t() | Langfuse.Generation.t()
  def update(%Langfuse.Span{} = span, opts), do: Langfuse.Span.update(span, opts)
  def update(%Langfuse.Generation{} = gen, opts), do: Langfuse.Generation.update(gen, opts)

  @doc """
  Ends a span or generation by setting its end time to now.

  Always call this when an observation is complete to record accurate
  duration metrics.

  ## Examples

      iex> trace = Langfuse.trace(name: "chat")
      iex> span = Langfuse.span(trace, name: "process")
      iex> span = Langfuse.end_observation(span)
      iex> span.end_time != nil
      true

  """
  @spec end_observation(Langfuse.Span.t() | Langfuse.Generation.t()) ::
          Langfuse.Span.t() | Langfuse.Generation.t()
  def end_observation(%Langfuse.Span{} = span), do: Langfuse.Span.end_span(span)
  def end_observation(%Langfuse.Generation{} = gen), do: Langfuse.Generation.end_generation(gen)

  @doc """
  Flushes all pending events to Langfuse synchronously.

  Blocks until all queued events are sent or the timeout is reached.
  Useful before application shutdown or when you need to ensure events
  are persisted.

  ## Options

    * `:timeout` - Maximum wait time in milliseconds. Defaults to 5000.

  ## Examples

      Langfuse.flush()
      :ok

      Langfuse.flush(timeout: 10_000)
      :ok

  """
  @spec flush(keyword()) :: :ok | {:error, :timeout}
  def flush(opts \\ []) do
    Ingestion.flush(opts)
  end

  @doc """
  Shuts down the Langfuse SDK gracefully.

  Flushes all pending events and stops the ingestion process. Call this
  during application shutdown for clean termination.

  ## Examples

      Langfuse.shutdown()
      :ok

  """
  @spec shutdown() :: :ok
  def shutdown do
    Ingestion.shutdown()
  end
end
