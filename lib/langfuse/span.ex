defmodule Langfuse.Span do
  @moduledoc """
  A span represents a unit of work with duration within a trace.

  Spans track operations like data retrieval, preprocessing, postprocessing,
  or any logical step in your LLM pipeline. They have a start time and an
  end time, enabling duration analysis in the Langfuse dashboard.

  ## Creating Spans

  Spans are created as children of traces or other spans:

      trace = Langfuse.trace(name: "rag-pipeline")

      span = Langfuse.Span.new(trace, name: "document-retrieval")

  ## Nesting Spans

  Spans can be nested to represent hierarchical operations:

      trace = Langfuse.trace(name: "pipeline")
      outer_span = Langfuse.Span.new(trace, name: "retrieval")
      inner_span = Langfuse.Span.new(outer_span, name: "vector-search")

  ## Completing Spans

  Always end spans to record accurate duration:

      span = Langfuse.Span.new(trace, name: "process")
      # ... do work ...
      span = Langfuse.Span.end_span(span)

  Or use `update/2` to add output before ending:

      span = Langfuse.Span.update(span, output: result)
      span = Langfuse.Span.end_span(span)

  """

  alias Langfuse.{Ingestion, Trace}

  @typedoc "Log level for the observation."
  @type level :: :debug | :default | :warning | :error

  @typedoc """
  Observation type for categorizing spans.

  Different types enable specialized views in the Langfuse dashboard:

    * `:span` - Generic unit of work (default)
    * `:agent` - AI agent decision spans
    * `:tool` - Tool/function call observations
    * `:chain` - Links between application steps
    * `:retriever` - RAG/data retrieval steps
    * `:embedding` - Embedding generation
    * `:evaluator` - Evaluation function spans
    * `:guardrail` - Safety/moderation checks

  """
  @type observation_type ::
          :span | :agent | :tool | :chain | :retriever | :embedding | :evaluator | :guardrail

  @typedoc "Valid parent types for a span: a trace or another span."
  @type parent :: Trace.t() | t()

  @typedoc """
  A span struct containing all span attributes.

  The `:id` is auto-generated if not provided. The `:start_time` defaults
  to the current UTC time. The `:end_time` is set when `end_span/1` is called.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          trace_id: String.t(),
          parent_observation_id: String.t() | nil,
          name: String.t(),
          type: observation_type(),
          start_time: DateTime.t(),
          end_time: DateTime.t() | nil,
          input: term(),
          output: term(),
          metadata: map() | nil,
          level: level() | nil,
          status_message: String.t() | nil,
          version: String.t() | nil
        }

  @enforce_keys [:id, :trace_id, :name, :start_time]
  defstruct [
    :id,
    :trace_id,
    :parent_observation_id,
    :name,
    type: :span,
    :start_time,
    :end_time,
    :input,
    :output,
    :metadata,
    :level,
    :status_message,
    :version
  ]

  @doc """
  Creates a new span and enqueues it for ingestion.

  The span is created as a child of the given parent (trace or span).
  It is immediately queued for asynchronous delivery to Langfuse.

  ## Options

    * `:name` - Name of the span (required)
    * `:id` - Custom span ID. Uses secure random hex if not provided.
    * `:type` - Observation type. Defaults to `:span`. See `t:observation_type/0`.
    * `:input` - Input data for the span.
    * `:output` - Output data for the span.
    * `:metadata` - Arbitrary metadata as a map.
    * `:level` - Log level: `:debug`, `:default`, `:warning`, or `:error`.
    * `:status_message` - Status description, useful for errors.
    * `:start_time` - Custom start time. Defaults to `DateTime.utc_now/0`.
    * `:end_time` - End time if already known.
    * `:version` - Application version string.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test", id: "trace-1")
      iex> span = Langfuse.Span.new(trace, name: "retrieval")
      iex> span.name
      "retrieval"
      iex> span.trace_id
      "trace-1"

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> span = Langfuse.Span.new(trace,
      ...>   name: "process",
      ...>   input: %{query: "test"},
      ...>   level: :debug
      ...> )
      iex> span.input
      %{query: "test"}
      iex> span.level
      :debug

  """
  @spec new(parent(), keyword()) :: t()
  def new(parent, opts) do
    name = Keyword.fetch!(opts, :name)
    {trace_id, parent_observation_id} = extract_parent_ids(parent)

    span = %__MODULE__{
      id: opts[:id] || generate_id(),
      trace_id: trace_id,
      parent_observation_id: parent_observation_id,
      name: name,
      type: opts[:type] || :span,
      start_time: opts[:start_time] || DateTime.utc_now(),
      end_time: opts[:end_time],
      input: opts[:input],
      output: opts[:output],
      metadata: opts[:metadata],
      level: opts[:level],
      status_message: opts[:status_message],
      version: opts[:version]
    }

    enqueue_event(span, :create)
    span
  end

  @doc """
  Updates an existing span and enqueues the update for ingestion.

  Only the fields provided in `opts` are updated. Other fields retain
  their current values.

  ## Options

    * `:name` - Updated span name.
    * `:input` - Updated input data.
    * `:output` - Updated output data.
    * `:metadata` - Updated metadata map (replaces existing).
    * `:level` - Updated log level.
    * `:status_message` - Updated status description.
    * `:end_time` - End time. Use `end_span/1` to set automatically.
    * `:version` - Updated version string.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> span = Langfuse.Span.new(trace, name: "process")
      iex> span = Langfuse.Span.update(span, output: %{result: "done"})
      iex> span.output
      %{result: "done"}

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> span = Langfuse.Span.new(trace, name: "process")
      iex> span = Langfuse.Span.update(span,
      ...>   level: :error,
      ...>   status_message: "Failed to process"
      ...> )
      iex> span.level
      :error

  """
  @spec update(t(), keyword()) :: t()
  def update(%__MODULE__{} = span, opts) do
    updated =
      span
      |> maybe_update(:name, opts)
      |> maybe_update(:end_time, opts)
      |> maybe_update(:input, opts)
      |> maybe_update(:output, opts)
      |> maybe_update(:metadata, opts)
      |> maybe_update(:level, opts)
      |> maybe_update(:status_message, opts)
      |> maybe_update(:version, opts)

    enqueue_event(updated, :update)
    updated
  end

  @doc """
  Ends the span by setting its end time to now.

  This is equivalent to `update(span, end_time: DateTime.utc_now())`.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> span = Langfuse.Span.new(trace, name: "process")
      iex> span.end_time
      nil
      iex> span = Langfuse.Span.end_span(span)
      iex> span.end_time != nil
      true

  """
  @spec end_span(t()) :: t()
  def end_span(%__MODULE__{} = span) do
    update(span, end_time: DateTime.utc_now())
  end

  @doc """
  Returns the span ID.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> span = Langfuse.Span.new(trace, name: "process", id: "span-123")
      iex> Langfuse.Span.get_id(span)
      "span-123"

  """
  @spec get_id(t()) :: String.t()
  def get_id(%__MODULE__{id: id}), do: id

  @doc """
  Returns the trace ID that this span belongs to.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test", id: "trace-456")
      iex> span = Langfuse.Span.new(trace, name: "process")
      iex> Langfuse.Span.get_trace_id(span)
      "trace-456"

  """
  @spec get_trace_id(t()) :: String.t()
  def get_trace_id(%__MODULE__{trace_id: trace_id}), do: trace_id

  defp extract_parent_ids(%Trace{id: trace_id}), do: {trace_id, nil}
  defp extract_parent_ids(%__MODULE__{trace_id: trace_id, id: id}), do: {trace_id, id}

  defp enqueue_event(span, type) do
    event = %{
      id: generate_id(),
      type: event_type(type),
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body: to_body(span)
    }

    Ingestion.enqueue(event)
  end

  defp event_type(:create), do: "span-create"
  defp event_type(:update), do: "span-update"

  defp to_body(span) do
    %{
      id: span.id,
      traceId: span.trace_id,
      name: span.name,
      startTime: DateTime.to_iso8601(span.start_time)
    }
    |> maybe_put(:parentObservationId, span.parent_observation_id)
    |> maybe_put(:type, type_to_string(span.type))
    |> maybe_put(:endTime, span.end_time && DateTime.to_iso8601(span.end_time))
    |> maybe_put(:input, span.input)
    |> maybe_put(:output, span.output)
    |> maybe_put(:metadata, span.metadata)
    |> maybe_put(:level, span.level && level_to_string(span.level))
    |> maybe_put(:statusMessage, span.status_message)
    |> maybe_put(:version, span.version)
    |> maybe_put(:environment, Langfuse.Config.get(:environment))
  end

  defp type_to_string(:span), do: "SPAN"
  defp type_to_string(:agent), do: "AGENT"
  defp type_to_string(:tool), do: "TOOL"
  defp type_to_string(:chain), do: "CHAIN"
  defp type_to_string(:retriever), do: "RETRIEVER"
  defp type_to_string(:embedding), do: "EMBEDDING"
  defp type_to_string(:evaluator), do: "EVALUATOR"
  defp type_to_string(:guardrail), do: "GUARDRAIL"

  defp level_to_string(:debug), do: "DEBUG"
  defp level_to_string(:default), do: "DEFAULT"
  defp level_to_string(:warning), do: "WARNING"
  defp level_to_string(:error), do: "ERROR"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_update(span, key, opts) do
    case Keyword.get(opts, key) do
      nil -> span
      value -> Map.put(span, key, value)
    end
  end

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
