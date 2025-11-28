defmodule Langfuse.Score do
  @moduledoc """
  Attach evaluation scores to traces and observations.

  Scores are evaluation metrics that enable quality tracking, filtering,
  and analysis in the Langfuse dashboard. They can be attached to traces,
  spans, or generations.

  ## Score Types

  Langfuse supports three score types:

    * **Numeric** - Floating point values for quantitative metrics
      (e.g., 0.0 to 1.0 for quality scores, 1-5 for ratings)

    * **Categorical** - String values from a predefined set
      (e.g., "positive", "negative", "neutral" for sentiment)

    * **Boolean** - True/false values for binary classifications
      (e.g., hallucination detection, relevance checks)

  ## Creating Scores

  Scores are created via `Langfuse.score/2`:

      trace = Langfuse.trace(name: "chat")

      Langfuse.score(trace, name: "quality", value: 0.85)

      Langfuse.score(trace,
        name: "sentiment",
        string_value: "positive",
        data_type: :categorical
      )

  ## Type Inference

  If `:data_type` is not specified, it is inferred:

    * If `:string_value` is present, type is `:categorical`
    * If `:value` is a boolean, type is `:boolean`
    * Otherwise, type is `:numeric`

  ## Score Configurations

  Scores can reference a predefined configuration via `:config_id`,
  which defines allowed values, ranges, and metadata in Langfuse.

  """

  alias Langfuse.{Ingestion, Trace, Span, Generation}

  @typedoc "Score data type classification."
  @type data_type :: :numeric | :categorical | :boolean

  @typedoc "Valid targets for scoring: traces, spans, generations, or trace IDs."
  @type target :: Trace.t() | Span.t() | Generation.t() | String.t()

  @doc """
  Creates a score and enqueues it for ingestion.

  The score is attached to the given target (trace, span, or generation)
  and immediately queued for asynchronous delivery to Langfuse.

  ## Options

    * `:name` - Score name (required). Examples: "accuracy", "relevance".
    * `:value` - Numeric value for numeric or boolean scores.
    * `:string_value` - String value for categorical scores.
    * `:data_type` - Score type: `:numeric`, `:categorical`, or `:boolean`.
      Auto-inferred from values if not provided.
    * `:comment` - Free-text comment or reasoning for the score.
    * `:id` - Custom score ID for idempotent updates.
    * `:config_id` - Reference to a score configuration in Langfuse.
    * `:metadata` - Arbitrary metadata map for additional context.

  ## Examples

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> Langfuse.Score.create(trace, name: "quality", value: 0.95)
      :ok

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> Langfuse.Score.create(trace,
      ...>   name: "sentiment",
      ...>   string_value: "positive",
      ...>   data_type: :categorical
      ...> )
      :ok

      iex> trace = Langfuse.Trace.new(name: "test")
      iex> Langfuse.Score.create(trace,
      ...>   name: "factual",
      ...>   value: true,
      ...>   data_type: :boolean,
      ...>   comment: "Verified against source"
      ...> )
      :ok

  """
  @spec create(target(), keyword()) :: :ok | {:error, term()}
  def create(target, opts) do
    name = Keyword.fetch!(opts, :name)

    {trace_id, observation_id} = extract_ids(target)

    data_type = opts[:data_type] || infer_data_type(opts)
    {value, string_value} = normalize_values(opts, data_type)

    score = %{
      id: opts[:id] || generate_id(),
      traceId: trace_id,
      name: name,
      value: value,
      dataType: data_type_to_string(data_type)
    }
    |> maybe_put(:observationId, observation_id)
    |> maybe_put(:stringValue, string_value)
    |> maybe_put(:comment, opts[:comment])
    |> maybe_put(:configId, opts[:config_id])
    |> maybe_put(:metadata, opts[:metadata])
    |> maybe_put(:environment, Langfuse.Config.get(:environment))

    event = %{
      id: generate_id(),
      type: "score-create",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body: score
    }

    Ingestion.enqueue(event)
    :ok
  end

  @doc """
  Creates a score for a session.

  Session scores evaluate the entire session rather than individual
  traces or observations.

  ## Options

    * `:name` - Score name (required).
    * `:value` - Numeric value for numeric or boolean scores.
    * `:string_value` - String value for categorical scores.
    * `:data_type` - Score type: `:numeric`, `:categorical`, or `:boolean`.
    * `:comment` - Free-text comment or reasoning.
    * `:id` - Custom score ID.
    * `:config_id` - Reference to a score configuration.
    * `:metadata` - Arbitrary metadata map for additional context.

  ## Examples

      iex> Langfuse.Score.score_session("session-123", name: "satisfaction", value: 4.5)
      :ok

  """
  @spec score_session(String.t(), keyword()) :: :ok | {:error, term()}
  def score_session(session_id, opts) when is_binary(session_id) do
    name = Keyword.fetch!(opts, :name)

    data_type = opts[:data_type] || infer_data_type(opts)
    {value, string_value} = normalize_values(opts, data_type)

    score = %{
      id: opts[:id] || generate_id(),
      name: name,
      value: value,
      dataType: data_type_to_string(data_type),
      source: "API",
      sessionId: session_id
    }
    |> maybe_put(:stringValue, string_value)
    |> maybe_put(:comment, opts[:comment])
    |> maybe_put(:configId, opts[:config_id])
    |> maybe_put(:metadata, opts[:metadata])
    |> maybe_put(:environment, Langfuse.Config.get(:environment))

    event = %{
      id: generate_id(),
      type: "score-create",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body: score
    }

    Ingestion.enqueue(event)
    :ok
  end

  defp extract_ids(%Trace{id: trace_id}), do: {trace_id, nil}
  defp extract_ids(%Span{trace_id: trace_id, id: id}), do: {trace_id, id}
  defp extract_ids(%Generation{trace_id: trace_id, id: id}), do: {trace_id, id}
  defp extract_ids(trace_id) when is_binary(trace_id), do: {trace_id, nil}

  defp infer_data_type(opts) do
    cond do
      Keyword.has_key?(opts, :string_value) -> :categorical
      is_boolean(opts[:value]) -> :boolean
      true -> :numeric
    end
  end

  defp normalize_values(opts, :boolean) do
    value = opts[:value]

    numeric_value =
      cond do
        value == true or value == 1 -> 1
        value == false or value == 0 -> 0
        true -> 0
      end

    {numeric_value, nil}
  end

  defp normalize_values(opts, :categorical) do
    {nil, opts[:string_value]}
  end

  defp normalize_values(opts, :numeric) do
    {opts[:value], nil}
  end

  defp data_type_to_string(:numeric), do: "NUMERIC"
  defp data_type_to_string(:categorical), do: "CATEGORICAL"
  defp data_type_to_string(:boolean), do: "BOOLEAN"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
