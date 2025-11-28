defmodule Langfuse.Event do
  @moduledoc """
  An event represents a point-in-time occurrence within a trace.

  Unlike spans and generations, events have no duration. They mark
  discrete moments such as user actions, errors, milestones, or
  any significant occurrence you want to track.

  ## Creating Events

  Events are created as children of traces or spans:

      trace = Langfuse.trace(name: "user-session")

      event = Langfuse.Event.new(trace,
        name: "button-click",
        input: %{button_id: "submit"}
      )

  ## Use Cases

  Common uses for events include:

    * User interactions (clicks, form submissions)
    * Error occurrences with context
    * State transitions
    * External API calls (when duration isn't important)
    * Logging significant application milestones

  """

  alias Langfuse.{Ingestion, Trace, Span}

  @typedoc "Log level for the observation."
  @type level :: :debug | :default | :warning | :error

  @typedoc "Valid parent types for an event."
  @type parent :: Trace.t() | Span.t()

  @typedoc """
  An event struct containing all event attributes.

  Events are immutable after creation. The `:id` is auto-generated
  if not provided. The `:start_time` defaults to the current UTC time.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          trace_id: String.t(),
          parent_observation_id: String.t() | nil,
          name: String.t(),
          start_time: DateTime.t(),
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
    :start_time,
    :input,
    :output,
    :metadata,
    :level,
    :status_message,
    :version
  ]

  @doc """
  Creates a new event and enqueues it for ingestion.

  The event is created as a child of the given parent (trace or span).
  It is immediately queued for asynchronous delivery to Langfuse.

  Events are immutable after creation; there is no update function.

  ## Options

    * `:name` - Name of the event (required)
    * `:id` - Custom event ID. Uses secure random hex if not provided.
    * `:input` - Input data associated with the event.
    * `:output` - Output data associated with the event.
    * `:metadata` - Arbitrary metadata as a map.
    * `:level` - Log level: `:debug`, `:default`, `:warning`, or `:error`.
    * `:status_message` - Status description.
    * `:start_time` - Event timestamp. Defaults to `DateTime.utc_now/0`.
    * `:version` - Application version string.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test", id: "trace-1")
      iex> event = Langfuse.Event.new(trace, name: "user-click")
      iex> event.name
      "user-click"
      iex> event.trace_id
      "trace-1"

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> event = Langfuse.Event.new(trace,
      ...>   name: "error",
      ...>   level: :error,
      ...>   input: %{error: "Connection failed"},
      ...>   status_message: "Database unavailable"
      ...> )
      iex> event.level
      :error

  """
  @spec new(parent(), keyword()) :: t()
  def new(parent, opts) do
    name = Keyword.fetch!(opts, :name)
    {trace_id, parent_observation_id} = extract_parent_ids(parent)

    event = %__MODULE__{
      id: opts[:id] || generate_id(),
      trace_id: trace_id,
      parent_observation_id: parent_observation_id,
      name: name,
      start_time: opts[:start_time] || DateTime.utc_now(),
      input: opts[:input],
      output: opts[:output],
      metadata: opts[:metadata],
      level: opts[:level],
      status_message: opts[:status_message],
      version: opts[:version]
    }

    enqueue_event(event)
    event
  end

  @doc """
  Returns the event ID.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> event = Langfuse.Event.new(trace, name: "click", id: "event-123")
      iex> Langfuse.Event.get_id(event)
      "event-123"

  """
  @spec get_id(t()) :: String.t()
  def get_id(%__MODULE__{id: id}), do: id

  @doc """
  Returns the trace ID that this event belongs to.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test", id: "trace-456")
      iex> event = Langfuse.Event.new(trace, name: "click")
      iex> Langfuse.Event.get_trace_id(event)
      "trace-456"

  """
  @spec get_trace_id(t()) :: String.t()
  def get_trace_id(%__MODULE__{trace_id: trace_id}), do: trace_id

  defp extract_parent_ids(%Trace{id: trace_id}), do: {trace_id, nil}
  defp extract_parent_ids(%Span{trace_id: trace_id, id: id}), do: {trace_id, id}

  defp enqueue_event(event) do
    ingestion_event = %{
      id: generate_id(),
      type: "event-create",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body: to_body(event)
    }

    Ingestion.enqueue(ingestion_event)
  end

  defp to_body(event) do
    %{
      id: event.id,
      traceId: event.trace_id,
      name: event.name,
      startTime: DateTime.to_iso8601(event.start_time)
    }
    |> maybe_put(:parentObservationId, event.parent_observation_id)
    |> maybe_put(:input, event.input)
    |> maybe_put(:output, event.output)
    |> maybe_put(:metadata, event.metadata)
    |> maybe_put(:level, event.level && level_to_string(event.level))
    |> maybe_put(:statusMessage, event.status_message)
    |> maybe_put(:version, event.version)
    |> maybe_put(:environment, Langfuse.Config.get(:environment))
  end

  defp level_to_string(:debug), do: "DEBUG"
  defp level_to_string(:default), do: "DEFAULT"
  defp level_to_string(:warning), do: "WARNING"
  defp level_to_string(:error), do: "ERROR"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
