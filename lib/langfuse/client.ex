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
  Lists prompts with pagination and filtering.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)
    * `:name` - Filter by prompt name
    * `:label` - Filter by label
    * `:tag` - Filter by tag

  ## Examples

      Langfuse.Client.list_prompts()
      #=> {:ok, %{"data" => [...], "meta" => %{"page" => 1, "totalPages" => 5}}}

      Langfuse.Client.list_prompts(limit: 10, name: "chat-template")

      Langfuse.Client.list_prompts(label: "production")

  """
  @spec list_prompts(keyword()) :: response()
  def list_prompts(opts \\ []) do
    params =
      build_pagination_params(opts)
      |> maybe_add_param(:name, opts[:name])
      |> maybe_add_param(:label, opts[:label])
      |> maybe_add_param(:tag, opts[:tag])

    get("/api/public/v2/prompts", params)
  end

  @doc """
  Creates a new prompt version.

  ## Options

    * `:name` - Prompt name (required)
    * `:prompt` - Prompt content (required). String for text, list of messages for chat.
    * `:type` - Prompt type: "text" or "chat" (default: "text")
    * `:labels` - List of labels (e.g., ["production", "latest"])
    * `:tags` - List of tags
    * `:config` - Configuration map (model parameters, etc.)

  ## Examples

      Langfuse.Client.create_prompt(
        name: "greeting",
        prompt: "Hello {{name}}!",
        labels: ["production"]
      )

      Langfuse.Client.create_prompt(
        name: "chat-assistant",
        type: "chat",
        prompt: [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "{{question}}"}
        ]
      )

  """
  @spec create_prompt(keyword()) :: response()
  def create_prompt(opts) do
    body =
      %{
        name: Keyword.fetch!(opts, :name),
        prompt: Keyword.fetch!(opts, :prompt)
      }
      |> maybe_put(:type, opts[:type] || "text")
      |> maybe_put(:labels, opts[:labels])
      |> maybe_put(:tags, opts[:tags])
      |> maybe_put(:config, opts[:config])

    post("/api/public/v2/prompts", body)
  end

  @doc """
  Updates labels for a specific prompt version.

  ## Options

    * `:labels` - New list of labels for this version

  ## Examples

      Langfuse.Client.update_prompt_labels("my-prompt", 3, labels: ["production", "v3"])

  """
  @spec update_prompt_labels(String.t(), pos_integer(), keyword()) :: response()
  def update_prompt_labels(name, version, opts) do
    body = %{labels: Keyword.fetch!(opts, :labels)}
    patch("/api/public/v2/prompts/#{URI.encode(name)}/versions/#{version}", body)
  end

  @doc """
  Gets a prompt by name.

  Returns the prompt with optional version or label filtering. If neither
  version nor label is specified, returns the latest production version.

  For cached prompt fetching with variable compilation, use `Langfuse.Prompt.get/2`.

  ## Options

    * `:version` - Specific version number to fetch
    * `:label` - Label to fetch (e.g., "production", "latest")

  ## Examples

      Langfuse.Client.get_prompt("my-prompt")
      #=> {:ok, %{"name" => "my-prompt", "version" => 1, "prompt" => "...", ...}}

      Langfuse.Client.get_prompt("my-prompt", version: 2)

      Langfuse.Client.get_prompt("my-prompt", label: "production")

  """
  @spec get_prompt(String.t(), keyword()) :: response()
  def get_prompt(name, opts \\ []) do
    params =
      []
      |> maybe_add_param(:version, opts[:version])
      |> maybe_add_param(:label, opts[:label])

    get("/api/public/v2/prompts/#{URI.encode(name)}", params)
  end

  @doc """
  Gets a dataset by name.

  ## Examples

      Langfuse.Client.get_dataset("qa-evaluation")
      #=> {:ok, %{"id" => "...", "name" => "qa-evaluation", "items" => [...]}}

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

  ## Examples

      Langfuse.Client.create_dataset(name: "qa-evaluation")
      #=> {:ok, %{"id" => "...", "name" => "qa-evaluation"}}

      Langfuse.Client.create_dataset(
        name: "rag-benchmark",
        description: "Evaluation dataset for RAG pipeline",
        metadata: %{version: "1.0"}
      )

  """
  @spec create_dataset(keyword()) :: response()
  def create_dataset(opts) do
    body =
      %{
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
    * `:page` - Page number for pagination (1-indexed)

  ## Examples

      Langfuse.Client.list_datasets()
      #=> {:ok, %{"data" => [...], "meta" => %{"page" => 1, "totalPages" => 1}}}

      Langfuse.Client.list_datasets(limit: 10, page: 2)

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
    * `:status` - Item status ("ACTIVE" or "ARCHIVED")

  ## Examples

      Langfuse.Client.create_dataset_item(
        dataset_name: "qa-evaluation",
        input: %{question: "What is Elixir?"},
        expected_output: %{answer: "A functional programming language"}
      )
      #=> {:ok, %{"id" => "...", "input" => %{...}}}

  """
  @spec create_dataset_item(keyword()) :: response()
  def create_dataset_item(opts) do
    body =
      %{
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

  ## Examples

      Langfuse.Client.get_dataset_item("item-abc-123")
      #=> {:ok, %{"id" => "item-abc-123", "input" => %{...}, "expectedOutput" => %{...}}}

  """
  @spec get_dataset_item(String.t()) :: response()
  def get_dataset_item(id) do
    get("/api/public/v2/dataset-items/#{URI.encode(id)}")
  end

  @doc """
  Updates a dataset item.

  ## Options

    * `:input` - Updated input data
    * `:expected_output` - Updated expected output
    * `:metadata` - Updated metadata
    * `:status` - Updated status ("ACTIVE" or "ARCHIVED")

  ## Examples

      Langfuse.Client.update_dataset_item("item-abc-123",
        expected_output: %{answer: "Updated answer"},
        status: "ARCHIVED"
      )
      #=> {:ok, %{"id" => "item-abc-123", ...}}

  """
  @spec update_dataset_item(String.t(), keyword()) :: response()
  def update_dataset_item(id, opts) do
    body =
      %{}
      |> maybe_put(:input, opts[:input])
      |> maybe_put(:expectedOutput, opts[:expected_output])
      |> maybe_put(:metadata, opts[:metadata])
      |> maybe_put(:status, opts[:status])

    patch("/api/public/v2/dataset-items/#{URI.encode(id)}", body)
  end

  @doc """
  Creates a dataset run.

  A dataset run represents a single evaluation pass over a dataset,
  linking trace executions to dataset items for comparison.

  ## Options

    * `:name` - Run name (required)
    * `:dataset_name` - Dataset name (required)
    * `:description` - Run description
    * `:metadata` - Additional metadata

  ## Examples

      Langfuse.Client.create_dataset_run(
        name: "eval-2025-01-15",
        dataset_name: "qa-evaluation"
      )
      #=> {:ok, %{"name" => "eval-2025-01-15", ...}}

      Langfuse.Client.create_dataset_run(
        name: "gpt4-vs-claude",
        dataset_name: "qa-evaluation",
        description: "Comparing GPT-4 and Claude responses",
        metadata: %{model: "gpt-4"}
      )

  """
  @spec create_dataset_run(keyword()) :: response()
  def create_dataset_run(opts) do
    body =
      %{
        name: Keyword.fetch!(opts, :name),
        datasetName: Keyword.fetch!(opts, :dataset_name)
      }
      |> maybe_put(:description, opts[:description])
      |> maybe_put(:metadata, opts[:metadata])

    post("/api/public/v2/dataset-runs", body)
  end

  @doc """
  Creates a dataset run item linking a trace to a dataset item.

  This connects an execution trace to a specific dataset item, enabling
  comparison between the actual output and expected output.

  ## Options

    * `:run_name` - Run name (required)
    * `:run_description` - Run description
    * `:dataset_item_id` - Dataset item ID (required)
    * `:trace_id` - Trace ID (required)
    * `:observation_id` - Observation ID (to link specific span/generation)
    * `:metadata` - Additional metadata

  ## Examples

      Langfuse.Client.create_dataset_run_item(
        run_name: "eval-2025-01-15",
        dataset_item_id: "item-abc-123",
        trace_id: "trace-xyz-789"
      )
      #=> {:ok, %{"id" => "...", "runName" => "eval-2025-01-15", ...}}

  """
  @spec create_dataset_run_item(keyword()) :: response()
  def create_dataset_run_item(opts) do
    body =
      %{
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
  Gets a dataset run by name.

  ## Examples

      Langfuse.Client.get_dataset_run("qa-evaluation", "eval-2025-01-15")
      #=> {:ok, %{"name" => "eval-2025-01-15", "datasetName" => "qa-evaluation", ...}}

  """
  @spec get_dataset_run(String.t(), String.t()) :: response()
  def get_dataset_run(dataset_name, run_name) do
    get("/api/public/datasets/#{URI.encode(dataset_name)}/runs/#{URI.encode(run_name)}")
  end

  @doc """
  Lists runs for a dataset.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)

  ## Examples

      Langfuse.Client.list_dataset_runs("qa-evaluation")
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

      Langfuse.Client.list_dataset_runs("qa-evaluation", limit: 5)

  """
  @spec list_dataset_runs(String.t(), keyword()) :: response()
  def list_dataset_runs(dataset_name, opts \\ []) do
    params = build_pagination_params(opts)
    get("/api/public/datasets/#{URI.encode(dataset_name)}/runs", params)
  end

  @doc """
  Deletes a dataset run.

  This operation is irreversible. All run items will also be deleted.

  ## Examples

      Langfuse.Client.delete_dataset_run("qa-evaluation", "eval-2025-01-15")
      #=> :ok

  """
  @spec delete_dataset_run(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_dataset_run(dataset_name, run_name) do
    delete("/api/public/datasets/#{URI.encode(dataset_name)}/runs/#{URI.encode(run_name)}")
  end

  @doc """
  Lists dataset items.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)
    * `:dataset_name` - Filter by dataset name

  ## Examples

      Langfuse.Client.list_dataset_items()
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

      Langfuse.Client.list_dataset_items(dataset_name: "qa-evaluation", limit: 10)

  """
  @spec list_dataset_items(keyword()) :: response()
  def list_dataset_items(opts \\ []) do
    params =
      build_pagination_params(opts)
      |> maybe_add_param(:datasetName, opts[:dataset_name])

    get("/api/public/dataset-items", params)
  end

  @doc """
  Lists dataset run items.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)
    * `:run_name` - Filter by run name
    * `:dataset_item_id` - Filter by dataset item ID

  ## Examples

      Langfuse.Client.list_dataset_run_items()
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

      Langfuse.Client.list_dataset_run_items(run_name: "eval-2025-01-15")

  """
  @spec list_dataset_run_items(keyword()) :: response()
  def list_dataset_run_items(opts \\ []) do
    params =
      build_pagination_params(opts)
      |> maybe_add_param(:runName, opts[:run_name])
      |> maybe_add_param(:datasetItemId, opts[:dataset_item_id])

    get("/api/public/dataset-run-items", params)
  end

  @doc """
  Lists score configurations.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)

  ## Examples

      Langfuse.Client.list_score_configs()
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

  """
  @spec list_score_configs(keyword()) :: response()
  def list_score_configs(opts \\ []) do
    params = build_pagination_params(opts)
    get("/api/public/v2/score-configs", params)
  end

  @doc """
  Gets a score configuration by ID.

  ## Examples

      Langfuse.Client.get_score_config("config-abc-123")
      #=> {:ok, %{"id" => "config-abc-123", "name" => "accuracy", "dataType" => "NUMERIC"}}

  """
  @spec get_score_config(String.t()) :: response()
  def get_score_config(id) do
    get("/api/public/v2/score-configs/#{URI.encode(id)}")
  end

  @doc """
  Creates a score configuration.

  Score configurations define the schema for scores, including allowed
  values, ranges, and categories.

  ## Options

    * `:name` - Config name (required)
    * `:data_type` - One of "NUMERIC", "CATEGORICAL", "BOOLEAN" (required)
    * `:min_value` - Minimum value (for numeric)
    * `:max_value` - Maximum value (for numeric)
    * `:categories` - List of category maps (for categorical)
    * `:description` - Config description

  ## Examples

      Langfuse.Client.create_score_config(
        name: "accuracy",
        data_type: "NUMERIC",
        min_value: 0,
        max_value: 1
      )
      #=> {:ok, %{"id" => "...", "name" => "accuracy", ...}}

      Langfuse.Client.create_score_config(
        name: "sentiment",
        data_type: "CATEGORICAL",
        categories: [
          %{label: "positive", value: 1},
          %{label: "neutral", value: 0},
          %{label: "negative", value: -1}
        ]
      )

  """
  @spec create_score_config(keyword()) :: response()
  def create_score_config(opts) do
    body =
      %{
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

  ## Examples

      Langfuse.Client.get_observation("obs-abc-123")
      #=> {:ok, %{"id" => "obs-abc-123", "type" => "GENERATION", "name" => "llm-call", ...}}

  """
  @spec get_observation(String.t()) :: response()
  def get_observation(id) do
    get("/api/public/observations/#{URI.encode(id)}")
  end

  @doc """
  Lists observations.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)
    * `:trace_id` - Filter by trace ID
    * `:name` - Filter by observation name
    * `:type` - Filter by type ("SPAN", "GENERATION", "EVENT")
    * `:user_id` - Filter by user ID
    * `:parent_observation_id` - Filter by parent observation

  ## Examples

      Langfuse.Client.list_observations(trace_id: "trace-abc-123")
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

      Langfuse.Client.list_observations(type: "GENERATION", limit: 10)

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

  ## Examples

      Langfuse.Client.get_trace("trace-abc-123")
      #=> {:ok, %{"id" => "trace-abc-123", "name" => "chat-request", "observations" => [...]}}

  """
  @spec get_trace(String.t()) :: response()
  def get_trace(id) do
    get("/api/public/traces/#{URI.encode(id)}")
  end

  @doc """
  Lists traces.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)
    * `:user_id` - Filter by user ID
    * `:session_id` - Filter by session ID
    * `:name` - Filter by name
    * `:tags` - Filter by tags (list of strings)
    * `:from_timestamp` - Filter from timestamp (ISO 8601)
    * `:to_timestamp` - Filter to timestamp (ISO 8601)

  ## Examples

      Langfuse.Client.list_traces()
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

      Langfuse.Client.list_traces(user_id: "user-123", limit: 10)

      Langfuse.Client.list_traces(
        session_id: "session-456",
        from_timestamp: "2025-01-01T00:00:00Z"
      )

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

  ## Examples

      Langfuse.Client.get_session("session-abc-123")
      #=> {:ok, %{"id" => "session-abc-123", "traces" => [...]}}

  """
  @spec get_session(String.t()) :: response()
  def get_session(id) do
    get("/api/public/sessions/#{URI.encode(id)}")
  end

  @doc """
  Lists sessions.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)
    * `:from_timestamp` - Filter from timestamp (ISO 8601)
    * `:to_timestamp` - Filter to timestamp (ISO 8601)

  ## Examples

      Langfuse.Client.list_sessions()
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

      Langfuse.Client.list_sessions(limit: 20)

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

  ## Examples

      Langfuse.Client.get_score("score-abc-123")
      #=> {:ok, %{"id" => "score-abc-123", "name" => "accuracy", "value" => 0.95}}

  """
  @spec get_score(String.t()) :: response()
  def get_score(id) do
    get("/api/public/scores/#{URI.encode(id)}")
  end

  @doc """
  Lists scores.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)
    * `:trace_id` - Filter by trace ID
    * `:user_id` - Filter by user ID
    * `:name` - Filter by score name
    * `:data_type` - Filter by data type ("NUMERIC", "CATEGORICAL", "BOOLEAN")

  ## Examples

      Langfuse.Client.list_scores()
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

      Langfuse.Client.list_scores(trace_id: "trace-abc-123")

      Langfuse.Client.list_scores(name: "accuracy", data_type: "NUMERIC")

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

  ## Examples

      Langfuse.Client.delete_score("score-abc-123")
      #=> :ok

  """
  @spec delete_score(String.t()) :: :ok | {:error, term()}
  def delete_score(id) do
    delete("/api/public/scores/#{URI.encode(id)}")
  end

  @doc """
  Deletes a dataset by name.

  This operation is irreversible. All items and runs in the dataset
  will also be deleted.

  ## Examples

      Langfuse.Client.delete_dataset("qa-evaluation")
      #=> :ok

  """
  @spec delete_dataset(String.t()) :: :ok | {:error, term()}
  def delete_dataset(name) do
    delete("/api/public/v2/datasets/#{URI.encode(name)}")
  end

  @doc """
  Deletes a dataset item by ID.

  ## Examples

      Langfuse.Client.delete_dataset_item("item-abc-123")
      #=> :ok

  """
  @spec delete_dataset_item(String.t()) :: :ok | {:error, term()}
  def delete_dataset_item(id) do
    delete("/api/public/v2/dataset-items/#{URI.encode(id)}")
  end

  @doc """
  Lists available models with pricing information.

  Returns both built-in models and custom models you've created.

  ## Options

    * `:limit` - Maximum number of results (default: 50)
    * `:page` - Page number for pagination (1-indexed)

  ## Examples

      Langfuse.Client.list_models()
      #=> {:ok, %{"data" => [...], "meta" => %{...}}}

  """
  @spec list_models(keyword()) :: response()
  def list_models(opts \\ []) do
    params = build_pagination_params(opts)
    get("/api/public/models", params)
  end

  @doc """
  Gets a model by ID.

  ## Examples

      Langfuse.Client.get_model("model-abc-123")
      #=> {:ok, %{"id" => "model-abc-123", "modelName" => "gpt-4", ...}}

  """
  @spec get_model(String.t()) :: response()
  def get_model(id) do
    get("/api/public/models/#{URI.encode(id)}")
  end

  @doc """
  Creates a custom model definition.

  Custom models allow you to define pricing for models not in Langfuse's
  default model list, enabling accurate cost tracking.

  ## Options

    * `:model_name` - Model identifier (required). Must match what's sent in generations.
    * `:match_pattern` - Regex pattern for matching model names (required).
    * `:input_price` - Price per input token in USD (required).
    * `:output_price` - Price per output token in USD (required).
    * `:total_price` - Fixed price per request (optional, alternative to token pricing).
    * `:unit` - Pricing unit: "TOKENS", "CHARACTERS", "IMAGES", etc. (default: "TOKENS")
    * `:tokenizer_id` - Tokenizer to use for token counting.
    * `:tokenizer_config` - Tokenizer configuration map.

  ## Examples

      Langfuse.Client.create_model(
        model_name: "my-custom-model",
        match_pattern: "my-custom-.*",
        input_price: 0.0001,
        output_price: 0.0002,
        unit: "TOKENS"
      )

  """
  @spec create_model(keyword()) :: response()
  def create_model(opts) do
    body =
      %{
        modelName: Keyword.fetch!(opts, :model_name),
        matchPattern: Keyword.fetch!(opts, :match_pattern),
        inputPrice: Keyword.fetch!(opts, :input_price),
        outputPrice: Keyword.fetch!(opts, :output_price)
      }
      |> maybe_put(:totalPrice, opts[:total_price])
      |> maybe_put(:unit, opts[:unit])
      |> maybe_put(:tokenizerId, opts[:tokenizer_id])
      |> maybe_put(:tokenizerConfig, opts[:tokenizer_config])

    post("/api/public/models", body)
  end

  @doc """
  Deletes a custom model definition.

  Only custom models created via the API can be deleted.
  Built-in models cannot be deleted.

  ## Examples

      Langfuse.Client.delete_model("model-abc-123")
      #=> :ok

  """
  @spec delete_model(String.t()) :: :ok | {:error, term()}
  def delete_model(id) do
    delete("/api/public/models/#{URI.encode(id)}")
  end

  @doc """
  Makes a raw GET request to the Langfuse API.

  Use this for API endpoints not covered by the higher-level functions.

  ## Examples

      Langfuse.Client.get("/api/public/health")
      #=> {:ok, %{"status" => "OK"}}

      Langfuse.Client.get("/api/public/traces", limit: 5)

  """
  @spec get(String.t(), keyword()) :: response()
  def get(path, params \\ []) do
    HTTP.get(path, params)
  end

  @doc """
  Makes a raw POST request to the Langfuse API.

  Use this for API endpoints not covered by the higher-level functions.

  ## Examples

      Langfuse.Client.post("/api/public/v2/datasets", %{name: "my-dataset"})
      #=> {:ok, %{"id" => "...", "name" => "my-dataset"}}

  """
  @spec post(String.t(), map()) :: response()
  def post(path, body) do
    HTTP.post(path, body)
  end

  @doc """
  Makes a raw DELETE request to the Langfuse API.

  ## Examples

      Langfuse.Client.delete("/api/public/scores/score-abc-123")
      #=> :ok

  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(path) do
    config = Config.get()

    unless Config.configured?() do
      {:error, :not_configured}
    else
      url = config.host <> path

      case Req.delete(url, auth: {:basic, "#{config.public_key}:#{config.secret_key}"}) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          :ok

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, %{status: status, body: body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Makes a raw PATCH request to the Langfuse API.

  ## Examples

      Langfuse.Client.patch("/api/public/v2/dataset-items/item-123", %{status: "ARCHIVED"})
      #=> {:ok, %{"id" => "item-123", "status" => "ARCHIVED"}}

  """
  @spec patch(String.t(), map()) :: response()
  def patch(path, body) do
    config = Config.get()

    unless Config.configured?() do
      {:error, :not_configured}
    else
      url = config.host <> path

      case Req.patch(url,
             json: body,
             auth: {:basic, "#{config.public_key}:#{config.secret_key}"}
           ) do
        {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
          {:ok, resp_body}

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          {:error, %{status: status, body: resp_body}}

        {:error, reason} ->
          {:error, reason}
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
