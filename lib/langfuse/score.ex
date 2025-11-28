defmodule Langfuse.Score do
  @moduledoc """
  Scoring functionality for Langfuse traces and observations.

  Supports three score types:
  - **Numeric**: Floating point values (e.g., 0.0 to 1.0 for quality scores)
  - **Categorical**: String values from a predefined set (e.g., "good", "bad")
  - **Boolean**: True/false values

  ## Examples

      trace = Langfuse.trace(name: "chat")

      # Numeric score
      Langfuse.score(trace, name: "quality", value: 0.85)

      # Categorical score
      Langfuse.score(trace, name: "sentiment", string_value: "positive", data_type: :categorical)

      # Boolean score
      Langfuse.score(trace, name: "hallucination", value: 0, data_type: :boolean)

      # Score with comment
      Langfuse.score(trace, name: "feedback", value: 4, comment: "Very helpful response")

  """

  alias Langfuse.{Ingestion, Trace, Span, Generation}

  @type data_type :: :numeric | :categorical | :boolean
  @type target :: Trace.t() | Span.t() | Generation.t() | String.t()

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

    event = %{
      id: generate_id(),
      type: "score-create",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body: score
    }

    Ingestion.enqueue(event)
    :ok
  end

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
      source: "API"
    }
    |> maybe_put(:stringValue, string_value)
    |> maybe_put(:comment, opts[:comment])
    |> maybe_put(:configId, opts[:config_id])

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
