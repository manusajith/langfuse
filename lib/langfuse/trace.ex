defmodule Langfuse.Trace do
  @moduledoc """
  A trace represents a single request or operation in an LLM application.

  Traces are the top-level containers for observability data. They group
  related observations (spans, generations, events) into a logical unit
  that can be analyzed, scored, and debugged in the Langfuse dashboard.

  ## Creating Traces

  Use `new/1` to create a trace at the start of an operation:

      trace = Langfuse.Trace.new(name: "chat-completion")

  Or with additional context:

      trace = Langfuse.Trace.new(
        name: "rag-pipeline",
        user_id: "user-123",
        session_id: "session-abc",
        tags: ["production"],
        metadata: %{environment: "prod"}
      )

  ## Updating Traces

  Use `update/2` to add output or modify trace data after creation:

      trace = Langfuse.Trace.update(trace,
        output: %{response: "Hello!"},
        metadata: %{tokens_used: 150}
      )

  ## Linking to Sessions

  Traces with the same `session_id` are grouped together in the UI,
  enabling analysis of multi-turn conversations:

      session_id = Langfuse.Session.new_id()

      trace1 = Langfuse.Trace.new(name: "turn-1", session_id: session_id)
      trace2 = Langfuse.Trace.new(name: "turn-2", session_id: session_id)

  """

  alias Langfuse.Ingestion

  @typedoc """
  A trace struct containing all trace attributes.

  The `:id` is auto-generated using cryptographically secure random bytes
  if not provided. The `:timestamp` defaults to the current UTC time.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          user_id: String.t() | nil,
          session_id: String.t() | nil,
          metadata: map() | nil,
          tags: [String.t()] | nil,
          public: boolean() | nil,
          input: term(),
          output: term(),
          version: String.t() | nil,
          release: String.t() | nil,
          timestamp: DateTime.t()
        }

  @enforce_keys [:id, :name, :timestamp]
  defstruct [
    :id,
    :name,
    :user_id,
    :session_id,
    :metadata,
    :tags,
    :public,
    :input,
    :output,
    :version,
    :release,
    :timestamp
  ]

  @doc """
  Creates a new trace and enqueues it for ingestion.

  The trace is immediately queued for asynchronous delivery to Langfuse.
  Returns the trace struct for use in creating nested observations.

  ## Options

    * `:name` - Name of the trace (required)
    * `:id` - Custom trace ID. Uses secure random hex if not provided.
    * `:user_id` - User identifier for filtering and analytics.
    * `:session_id` - Session ID for grouping related traces.
    * `:metadata` - Arbitrary metadata as a map.
    * `:tags` - List of string tags for categorization.
    * `:public` - Whether the trace is publicly accessible.
    * `:input` - Input data for the trace.
    * `:output` - Output data for the trace.
    * `:version` - Application version string.
    * `:release` - Release identifier.
    * `:timestamp` - Custom timestamp. Defaults to `DateTime.utc_now/0`.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> trace.name
      "test"

      iex> trace = Langfuse.Trace.new(name: "test", id: "custom-id")
      iex> trace.id
      "custom-id"

      iex> trace = Langfuse.Trace.new(
      ...>   name: "chat",
      ...>   user_id: "user-123",
      ...>   tags: ["prod"]
      ...> )
      iex> trace.user_id
      "user-123"
      iex> trace.tags
      ["prod"]

  """
  @spec new(keyword()) :: t()
  def new(opts) do
    name = Keyword.fetch!(opts, :name)

    trace = %__MODULE__{
      id: opts[:id] || generate_id(),
      name: name,
      user_id: opts[:user_id],
      session_id: opts[:session_id],
      metadata: opts[:metadata],
      tags: opts[:tags],
      public: opts[:public],
      input: opts[:input],
      output: opts[:output],
      version: opts[:version],
      release: opts[:release],
      timestamp: opts[:timestamp] || DateTime.utc_now()
    }

    enqueue_event(trace, :create)
    trace
  end

  @doc """
  Updates an existing trace and enqueues the update for ingestion.

  Only the fields provided in `opts` are updated. Other fields retain
  their current values.

  ## Options

    * `:name` - Updated trace name.
    * `:user_id` - Updated user identifier.
    * `:session_id` - Updated session ID.
    * `:metadata` - Updated metadata map (replaces existing).
    * `:tags` - Updated tags list (replaces existing).
    * `:public` - Updated public visibility.
    * `:input` - Updated input data.
    * `:output` - Updated output data.
    * `:version` - Updated version string.
    * `:release` - Updated release identifier.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> trace = Langfuse.Trace.update(trace, output: %{result: "done"})
      iex> trace.output
      %{result: "done"}

      iex> trace = Langfuse.Trace.new(name: "test", tags: ["v1"])
      iex> trace = Langfuse.Trace.update(trace, tags: ["v2"])
      iex> trace.tags
      ["v2"]

  """
  @spec update(t(), keyword()) :: t()
  def update(%__MODULE__{} = trace, opts) do
    updated =
      trace
      |> maybe_update(:name, opts)
      |> maybe_update(:user_id, opts)
      |> maybe_update(:session_id, opts)
      |> maybe_update(:metadata, opts)
      |> maybe_update(:tags, opts)
      |> maybe_update(:public, opts)
      |> maybe_update(:input, opts)
      |> maybe_update(:output, opts)
      |> maybe_update(:version, opts)
      |> maybe_update(:release, opts)

    enqueue_event(updated, :update)
    updated
  end

  @doc """
  Returns the trace ID.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test", id: "trace-123")
      iex> Langfuse.Trace.get_id(trace)
      "trace-123"

  """
  @spec get_id(t()) :: String.t()
  def get_id(%__MODULE__{id: id}), do: id

  @doc """
  Returns the session ID, or `nil` if not set.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test", session_id: "session-456")
      iex> Langfuse.Trace.get_session_id(trace)
      "session-456"

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> Langfuse.Trace.get_session_id(trace)
      nil

  """
  @spec get_session_id(t()) :: String.t() | nil
  def get_session_id(%__MODULE__{session_id: session_id}), do: session_id

  defp enqueue_event(trace, type) do
    event = %{
      id: generate_id(),
      type: event_type(type),
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body: to_body(trace)
    }

    Ingestion.enqueue(event)
  end

  defp event_type(:create), do: "trace-create"
  defp event_type(:update), do: "trace-create"

  defp to_body(trace) do
    %{
      id: trace.id,
      name: trace.name,
      timestamp: DateTime.to_iso8601(trace.timestamp)
    }
    |> maybe_put(:userId, trace.user_id)
    |> maybe_put(:sessionId, trace.session_id)
    |> maybe_put(:metadata, trace.metadata)
    |> maybe_put(:tags, trace.tags)
    |> maybe_put(:public, trace.public)
    |> maybe_put(:input, trace.input)
    |> maybe_put(:output, trace.output)
    |> maybe_put(:version, trace.version)
    |> maybe_put(:release, trace.release)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_update(trace, key, opts) do
    case Keyword.get(opts, key) do
      nil -> trace
      value -> Map.put(trace, key, value)
    end
  end

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
