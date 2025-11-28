defmodule Langfuse.Client do
  @moduledoc """
  Direct access to the Langfuse REST API.

  This module provides functions for interacting with Langfuse management
  APIs that are not covered by the tracing SDK. Use this for datasets,
  score configurations, listing traces/sessions, and other administrative
  operations.

  ## Datasets

  Create and manage evaluation datasets:

      {:ok, dataset} = Langfuse.Client.create_dataset(name: "qa-eval")

      {:ok, item} = Langfuse.Client.create_dataset_item(
        dataset_name: "qa-eval",
        input: %{question: "What is Elixir?"},
        expected_output: %{answer: "A functional programming language"}
      )

  ## Dataset Runs

  Track evaluation runs against datasets:

      {:ok, run} = Langfuse.Client.create_dataset_run(
        name: "eval-2025-01",
        dataset_name: "qa-eval"
      )

      {:ok, _} = Langfuse.Client.create_dataset_run_item(
        run_name: "eval-2025-01",
        dataset_item_id: item["id"],
        trace_id: trace.id
      )

  ## Querying Data

  List and retrieve traces, sessions, and scores:

      {:ok, traces} = Langfuse.Client.list_traces(limit: 10, user_id: "user-123")
      {:ok, trace} = Langfuse.Client.get_trace("trace-id")
      {:ok, sessions} = Langfuse.Client.list_sessions(limit: 50)

  ## Score Configurations

  Manage score configurations:

      {:ok, config} = Langfuse.Client.create_score_config(
        name: "accuracy",
        data_type: "NUMERIC",
        min_value: 0,
        max_value: 1
      )

  """

  alias Langfuse.{Config, HTTP}

  @typedoc "API response result."
  @type response :: {:ok, map()} | {:ok, list(map())} | {:error, term()}

  @doc """
  Gets a dataset by name.
  """
  @spec get_dataset(String.t()) :: response()
  def get_dataset(name) do
    get("/api/public/v2/datasets/#{URI.encode(name)}")
  end

  @doc """
  Creates a new dataset.

  ## Options

    * `:name` - Dataset name (required)
    * `:description` - Dataset description
    * `:metadata` - Additional metadata

  """
  @spec create_dataset(keyword()) :: response()
  def create_dataset(opts) do
    body = %{
      name: Keyword.fetch!(opts, :name)
    }
    |> maybe_put(:description, opts[:description])
    |> maybe_put(:metadata, opts[:metadata])

    post("/api/public/v2/datasets", body)
  end

  @doc """
  Lists datasets.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination

  """
  @spec list_datasets(keyword()) :: response()
  def list_datasets(opts \\ []) do
    params = build_pagination_params(opts)
    get("/api/public/v2/datasets", params)
  end

  @doc """
  Creates a dataset item.

  ## Options

    * `:dataset_name` - Dataset name (required)
    * `:input` - Input data (required)
    * `:expected_output` - Expected output data
    * `:metadata` - Additional metadata
    * `:source_trace_id` - Source trace ID
    * `:source_observation_id` - Source observation ID
    * `:status` - Item status

  """
  @spec create_dataset_item(keyword()) :: response()
  def create_dataset_item(opts) do
    body = %{
      datasetName: Keyword.fetch!(opts, :dataset_name),
      input: Keyword.fetch!(opts, :input)
    }
    |> maybe_put(:expectedOutput, opts[:expected_output])
    |> maybe_put(:metadata, opts[:metadata])
    |> maybe_put(:sourceTraceId, opts[:source_trace_id])
    |> maybe_put(:sourceObservationId, opts[:source_observation_id])
    |> maybe_put(:status, opts[:status])

    post("/api/public/v2/dataset-items", body)
  end

  @doc """
  Gets a dataset item by ID.
  """
  @spec get_dataset_item(String.t()) :: response()
  def get_dataset_item(id) do
    get("/api/public/v2/dataset-items/#{URI.encode(id)}")
  end

  @doc """
  Creates a dataset run.

  ## Options

    * `:name` - Run name (required)
    * `:dataset_name` - Dataset name (required)
    * `:description` - Run description
    * `:metadata` - Additional metadata

  """
  @spec create_dataset_run(keyword()) :: response()
  def create_dataset_run(opts) do
    body = %{
      name: Keyword.fetch!(opts, :name),
      datasetName: Keyword.fetch!(opts, :dataset_name)
    }
    |> maybe_put(:description, opts[:description])
    |> maybe_put(:metadata, opts[:metadata])

    post("/api/public/v2/dataset-runs", body)
  end

  @doc """
  Creates a dataset run item linking a trace to a dataset item.

  ## Options

    * `:run_name` - Run name (required)
    * `:run_description` - Run description
    * `:dataset_item_id` - Dataset item ID (required)
    * `:trace_id` - Trace ID (required)
    * `:observation_id` - Observation ID
    * `:metadata` - Additional metadata

  """
  @spec create_dataset_run_item(keyword()) :: response()
  def create_dataset_run_item(opts) do
    body = %{
      runName: Keyword.fetch!(opts, :run_name),
      datasetItemId: Keyword.fetch!(opts, :dataset_item_id),
      traceId: Keyword.fetch!(opts, :trace_id)
    }
    |> maybe_put(:runDescription, opts[:run_description])
    |> maybe_put(:observationId, opts[:observation_id])
    |> maybe_put(:metadata, opts[:metadata])

    post("/api/public/v2/dataset-run-items", body)
  end

  @doc """
  Lists score configurations.
  """
  @spec list_score_configs(keyword()) :: response()
  def list_score_configs(opts \\ []) do
    params = build_pagination_params(opts)
    get("/api/public/v2/score-configs", params)
  end

  @doc """
  Gets a score configuration by ID.
  """
  @spec get_score_config(String.t()) :: response()
  def get_score_config(id) do
    get("/api/public/v2/score-configs/#{URI.encode(id)}")
  end

  @doc """
  Creates a score configuration.

  ## Options

    * `:name` - Config name (required)
    * `:data_type` - One of "NUMERIC", "CATEGORICAL", "BOOLEAN" (required)
    * `:min_value` - Minimum value (for numeric)
    * `:max_value` - Maximum value (for numeric)
    * `:categories` - List of category maps (for categorical)
    * `:description` - Config description

  """
  @spec create_score_config(keyword()) :: response()
  def create_score_config(opts) do
    body = %{
      name: Keyword.fetch!(opts, :name),
      dataType: Keyword.fetch!(opts, :data_type)
    }
    |> maybe_put(:minValue, opts[:min_value])
    |> maybe_put(:maxValue, opts[:max_value])
    |> maybe_put(:categories, opts[:categories])
    |> maybe_put(:description, opts[:description])

    post("/api/public/v2/score-configs", body)
  end

  @doc """
  Gets an observation by ID.

  Observations include spans, generations, and events within a trace.
  """
  @spec get_observation(String.t()) :: response()
  def get_observation(id) do
    get("/api/public/observations/#{URI.encode(id)}")
  end

  @doc """
  Lists observations.

  ## Options

    * `:limit` - Maximum number of results
    * `:page` - Page number
    * `:trace_id` - Filter by trace ID
    * `:name` - Filter by observation name
    * `:type` - Filter by type ("SPAN", "GENERATION", "EVENT")
    * `:user_id` - Filter by user ID
    * `:parent_observation_id` - Filter by parent observation

  """
  @spec list_observations(keyword()) :: response()
  def list_observations(opts \\ []) do
    params =
      build_pagination_params(opts)
      |> maybe_add_param(:traceId, opts[:trace_id])
      |> maybe_add_param(:name, opts[:name])
      |> maybe_add_param(:type, opts[:type])
      |> maybe_add_param(:userId, opts[:user_id])
      |> maybe_add_param(:parentObservationId, opts[:parent_observation_id])

    get("/api/public/observations", params)
  end

  @doc """
  Gets a trace by ID.
  """
  @spec get_trace(String.t()) :: response()
  def get_trace(id) do
    get("/api/public/traces/#{URI.encode(id)}")
  end

  @doc """
  Lists traces.

  ## Options

    * `:limit` - Maximum number of results
    * `:page` - Page number
    * `:user_id` - Filter by user ID
    * `:session_id` - Filter by session ID
    * `:name` - Filter by name
    * `:tags` - Filter by tags
    * `:from_timestamp` - Filter from timestamp
    * `:to_timestamp` - Filter to timestamp

  """
  @spec list_traces(keyword()) :: response()
  def list_traces(opts \\ []) do
    params =
      build_pagination_params(opts)
      |> maybe_add_param(:userId, opts[:user_id])
      |> maybe_add_param(:sessionId, opts[:session_id])
      |> maybe_add_param(:name, opts[:name])
      |> maybe_add_param(:tags, opts[:tags])
      |> maybe_add_param(:fromTimestamp, opts[:from_timestamp])
      |> maybe_add_param(:toTimestamp, opts[:to_timestamp])

    get("/api/public/traces", params)
  end

  @doc """
  Gets a session by ID.
  """
  @spec get_session(String.t()) :: response()
  def get_session(id) do
    get("/api/public/sessions/#{URI.encode(id)}")
  end

  @doc """
  Lists sessions.

  ## Options

    * `:limit` - Maximum number of results
    * `:page` - Page number
    * `:from_timestamp` - Filter from timestamp
    * `:to_timestamp` - Filter to timestamp

  """
  @spec list_sessions(keyword()) :: response()
  def list_sessions(opts \\ []) do
    params =
      build_pagination_params(opts)
      |> maybe_add_param(:fromTimestamp, opts[:from_timestamp])
      |> maybe_add_param(:toTimestamp, opts[:to_timestamp])

    get("/api/public/sessions", params)
  end

  @doc """
  Gets a score by ID.
  """
  @spec get_score(String.t()) :: response()
  def get_score(id) do
    get("/api/public/scores/#{URI.encode(id)}")
  end

  @doc """
  Lists scores.

  ## Options

    * `:limit` - Maximum number of results
    * `:page` - Page number
    * `:trace_id` - Filter by trace ID
    * `:user_id` - Filter by user ID
    * `:name` - Filter by score name
    * `:data_type` - Filter by data type

  """
  @spec list_scores(keyword()) :: response()
  def list_scores(opts \\ []) do
    params =
      build_pagination_params(opts)
      |> maybe_add_param(:traceId, opts[:trace_id])
      |> maybe_add_param(:userId, opts[:user_id])
      |> maybe_add_param(:name, opts[:name])
      |> maybe_add_param(:dataType, opts[:data_type])

    get("/api/public/scores", params)
  end

  @doc """
  Deletes a score by ID.
  """
  @spec delete_score(String.t()) :: :ok | {:error, term()}
  def delete_score(id) do
    delete("/api/public/scores/#{URI.encode(id)}")
  end

  @doc """
  Makes a raw GET request to the Langfuse API.
  """
  @spec get(String.t(), keyword()) :: response()
  def get(path, params \\ []) do
    HTTP.get(path, params)
  end

  @doc """
  Makes a raw POST request to the Langfuse API.
  """
  @spec post(String.t(), map()) :: response()
  def post(path, body) do
    HTTP.post(path, body)
  end

  @doc """
  Makes a raw DELETE request to the Langfuse API.
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(path) do
    config = Config.get()

    unless Config.configured?() do
      {:error, :not_configured}
    else
      url = config.host <> path

      case Req.delete(url, auth: {:basic, "#{config.public_key}:#{config.secret_key}"}) do
        {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
        {:ok, %Req.Response{status: status, body: body}} -> {:error, %{status: status, body: body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_pagination_params(opts) do
    []
    |> maybe_add_param(:limit, opts[:limit])
    |> maybe_add_param(:page, opts[:page])
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Keyword.put(params, key, value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
