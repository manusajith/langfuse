defmodule Langfuse.Generation do
  @moduledoc """
  A generation represents an LLM API call within a trace.

  Generations are specialized observations for tracking model invocations.
  They capture model information, input prompts, output completions,
  token usage, costs, and can be linked to Langfuse prompts for
  version tracking.

  ## Creating Generations

  Generations are created as children of traces or spans:

      trace = Langfuse.trace(name: "chat")

      generation = Langfuse.Generation.new(trace,
        name: "completion",
        model: "gpt-4",
        input: [%{role: "user", content: "Hello"}]
      )

  ## Recording Output and Usage

  After receiving the model response, update the generation:

      generation = Langfuse.Generation.update(generation,
        output: %{role: "assistant", content: "Hi there!"},
        usage: %{input: 10, output: 5, total: 15}
      )

      generation = Langfuse.Generation.end_generation(generation)

  ## Linking Prompts

  Track which prompt version was used:

      {:ok, prompt} = Langfuse.Prompt.get("chat-template")

      generation = Langfuse.Generation.new(trace,
        name: "completion",
        model: "gpt-4",
        prompt_name: prompt.name,
        prompt_version: prompt.version
      )

  ## Token Usage and Costs

  The `:usage` option accepts a map with token counts and optional costs:

      usage: %{
        input: 150,
        output: 50,
        total: 200,
        input_cost: 0.003,
        output_cost: 0.006,
        total_cost: 0.009
      }

  """

  alias Langfuse.{Ingestion, Trace, Span}

  @typedoc "Log level for the observation."
  @type level :: :debug | :default | :warning | :error

  @typedoc "Valid parent types for a generation."
  @type parent :: Trace.t() | Span.t() | t()

  @typedoc """
  Token usage and cost information.

  All fields are optional. Costs should be in USD.
  """
  @type usage :: %{
          optional(:input) => non_neg_integer(),
          optional(:output) => non_neg_integer(),
          optional(:total) => non_neg_integer(),
          optional(:unit) => String.t(),
          optional(:input_cost) => float(),
          optional(:output_cost) => float(),
          optional(:total_cost) => float()
        }

  @typedoc """
  A generation struct containing all generation attributes.

  The `:id` is auto-generated if not provided. The `:start_time` defaults
  to the current UTC time.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          trace_id: String.t(),
          parent_observation_id: String.t() | nil,
          name: String.t(),
          model: String.t() | nil,
          model_parameters: map() | nil,
          start_time: DateTime.t(),
          end_time: DateTime.t() | nil,
          completion_start_time: DateTime.t() | nil,
          input: term(),
          output: term(),
          usage: usage() | nil,
          metadata: map() | nil,
          level: level() | nil,
          status_message: String.t() | nil,
          prompt_name: String.t() | nil,
          prompt_version: pos_integer() | nil,
          version: String.t() | nil
        }

  @enforce_keys [:id, :trace_id, :name, :start_time]
  defstruct [
    :id,
    :trace_id,
    :parent_observation_id,
    :name,
    :model,
    :model_parameters,
    :start_time,
    :end_time,
    :completion_start_time,
    :input,
    :output,
    :usage,
    :metadata,
    :level,
    :status_message,
    :prompt_name,
    :prompt_version,
    :version
  ]

  @doc """
  Creates a new generation and enqueues it for ingestion.

  The generation is created as a child of the given parent (trace, span,
  or another generation). It is immediately queued for asynchronous
  delivery to Langfuse.

  ## Options

    * `:name` - Name of the generation (required)
    * `:id` - Custom generation ID. Uses secure random hex if not provided.
    * `:model` - Model identifier (e.g., "gpt-4", "claude-3-opus").
    * `:model_parameters` - Model parameters as a map (temperature, etc.).
    * `:input` - Input messages or prompt.
    * `:output` - Model response/completion.
    * `:usage` - Token usage map. See `t:usage/0`.
    * `:metadata` - Arbitrary metadata as a map.
    * `:level` - Log level: `:debug`, `:default`, `:warning`, or `:error`.
    * `:status_message` - Status description.
    * `:prompt_name` - Name of linked Langfuse prompt.
    * `:prompt_version` - Version of linked Langfuse prompt.
    * `:start_time` - Custom start time. Defaults to `DateTime.utc_now/0`.
    * `:end_time` - End time if already known.
    * `:completion_start_time` - When streaming response started.
    * `:version` - Application version string.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test", id: "trace-1")
      iex> gen = Langfuse.Generation.new(trace, name: "llm", model: "gpt-4")
      iex> gen.model
      "gpt-4"
      iex> gen.trace_id
      "trace-1"

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> gen = Langfuse.Generation.new(trace,
      ...>   name: "completion",
      ...>   model: "gpt-4",
      ...>   model_parameters: %{temperature: 0.7},
      ...>   input: [%{role: "user", content: "Hello"}]
      ...> )
      iex> gen.model_parameters
      %{temperature: 0.7}

  """
  @spec new(parent(), keyword()) :: t()
  def new(parent, opts) do
    name = Keyword.fetch!(opts, :name)
    {trace_id, parent_observation_id} = extract_parent_ids(parent)

    generation = %__MODULE__{
      id: opts[:id] || generate_id(),
      trace_id: trace_id,
      parent_observation_id: parent_observation_id,
      name: name,
      model: opts[:model],
      model_parameters: opts[:model_parameters],
      start_time: opts[:start_time] || DateTime.utc_now(),
      end_time: opts[:end_time],
      completion_start_time: opts[:completion_start_time],
      input: opts[:input],
      output: opts[:output],
      usage: opts[:usage],
      metadata: opts[:metadata],
      level: opts[:level],
      status_message: opts[:status_message],
      prompt_name: opts[:prompt_name],
      prompt_version: opts[:prompt_version],
      version: opts[:version]
    }

    enqueue_event(generation, :create)
    generation
  end

  @doc """
  Updates an existing generation and enqueues the update for ingestion.

  Commonly used to add output and usage after receiving the model response.

  ## Options

    * `:model` - Updated model identifier.
    * `:model_parameters` - Updated model parameters.
    * `:input` - Updated input data.
    * `:output` - Model response/completion.
    * `:usage` - Token usage map.
    * `:metadata` - Updated metadata map.
    * `:level` - Updated log level.
    * `:status_message` - Updated status description.
    * `:end_time` - End time. Use `end_generation/1` to set automatically.
    * `:completion_start_time` - When streaming started.
    * `:version` - Updated version string.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> gen = Langfuse.Generation.new(trace, name: "llm", model: "gpt-4")
      iex> gen = Langfuse.Generation.update(gen,
      ...>   output: %{content: "Hello!"},
      ...>   usage: %{input: 10, output: 5, total: 15}
      ...> )
      iex> gen.output
      %{content: "Hello!"}

  """
  @spec update(t(), keyword()) :: t()
  def update(%__MODULE__{} = generation, opts) do
    updated =
      generation
      |> maybe_update(:name, opts)
      |> maybe_update(:model, opts)
      |> maybe_update(:model_parameters, opts)
      |> maybe_update(:end_time, opts)
      |> maybe_update(:completion_start_time, opts)
      |> maybe_update(:input, opts)
      |> maybe_update(:output, opts)
      |> maybe_update(:usage, opts)
      |> maybe_update(:metadata, opts)
      |> maybe_update(:level, opts)
      |> maybe_update(:status_message, opts)
      |> maybe_update(:version, opts)

    enqueue_event(updated, :update)
    updated
  end

  @doc """
  Ends the generation by setting its end time to now.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> gen = Langfuse.Generation.new(trace, name: "llm", model: "gpt-4")
      iex> gen.end_time
      nil
      iex> gen = Langfuse.Generation.end_generation(gen)
      iex> gen.end_time != nil
      true

  """
  @spec end_generation(t()) :: t()
  def end_generation(%__MODULE__{} = generation) do
    update(generation, end_time: DateTime.utc_now())
  end

  @doc """
  Returns the generation ID.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> gen = Langfuse.Generation.new(trace, name: "llm", id: "gen-123")
      iex> Langfuse.Generation.get_id(gen)
      "gen-123"

  """
  @spec get_id(t()) :: String.t()
  def get_id(%__MODULE__{id: id}), do: id

  @doc """
  Returns the trace ID that this generation belongs to.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test", id: "trace-456")
      iex> gen = Langfuse.Generation.new(trace, name: "llm")
      iex> Langfuse.Generation.get_trace_id(gen)
      "trace-456"

  """
  @spec get_trace_id(t()) :: String.t()
  def get_trace_id(%__MODULE__{trace_id: trace_id}), do: trace_id

  defp extract_parent_ids(%Trace{id: trace_id}), do: {trace_id, nil}
  defp extract_parent_ids(%Span{trace_id: trace_id, id: id}), do: {trace_id, id}
  defp extract_parent_ids(%__MODULE__{trace_id: trace_id, id: id}), do: {trace_id, id}

  defp enqueue_event(generation, type) do
    event = %{
      id: generate_id(),
      type: event_type(type),
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body: to_body(generation)
    }

    Ingestion.enqueue(event)
  end

  defp event_type(:create), do: "generation-create"
  defp event_type(:update), do: "generation-update"

  defp to_body(gen) do
    %{
      id: gen.id,
      traceId: gen.trace_id,
      name: gen.name,
      startTime: DateTime.to_iso8601(gen.start_time)
    }
    |> maybe_put(:parentObservationId, gen.parent_observation_id)
    |> maybe_put(:model, gen.model)
    |> maybe_put(:modelParameters, gen.model_parameters)
    |> maybe_put(:endTime, gen.end_time && DateTime.to_iso8601(gen.end_time))
    |> maybe_put(:completionStartTime, gen.completion_start_time && DateTime.to_iso8601(gen.completion_start_time))
    |> maybe_put(:input, gen.input)
    |> maybe_put(:output, gen.output)
    |> maybe_put(:usage, format_usage(gen.usage))
    |> maybe_put(:metadata, gen.metadata)
    |> maybe_put(:level, gen.level && level_to_string(gen.level))
    |> maybe_put(:statusMessage, gen.status_message)
    |> maybe_put(:promptName, gen.prompt_name)
    |> maybe_put(:promptVersion, gen.prompt_version)
    |> maybe_put(:version, gen.version)
    |> maybe_put(:environment, Langfuse.Config.get(:environment))
  end

  defp format_usage(nil), do: nil

  defp format_usage(usage) do
    %{}
    |> maybe_put(:input, usage[:input])
    |> maybe_put(:output, usage[:output])
    |> maybe_put(:total, usage[:total])
    |> maybe_put(:unit, usage[:unit])
    |> maybe_put(:inputCost, usage[:input_cost])
    |> maybe_put(:outputCost, usage[:output_cost])
    |> maybe_put(:totalCost, usage[:total_cost])
  end

  defp level_to_string(:debug), do: "DEBUG"
  defp level_to_string(:default), do: "DEFAULT"
  defp level_to_string(:warning), do: "WARNING"
  defp level_to_string(:error), do: "ERROR"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, map_val) when map_val == %{}, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_update(gen, key, opts) do
    case Keyword.get(opts, key) do
      nil -> gen
      value -> Map.put(gen, key, value)
    end
  end

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
