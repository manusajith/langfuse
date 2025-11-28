defmodule Langfuse.HTTP do
  @moduledoc """
  HTTP client for Langfuse API.

  This module handles all HTTP communication with the Langfuse API,
  including authentication, automatic retries with exponential backoff,
  and telemetry instrumentation.

  ## Authentication

  Requests are authenticated using HTTP Basic Auth with the configured
  public key and secret key.

  ## Retries

  Failed requests are automatically retried with exponential backoff.
  The base delay starts at 1 second and doubles with each attempt,
  capped at 30 seconds. Random jitter is added to prevent thundering herd.

  ## Telemetry

  HTTP requests emit telemetry events. See `Langfuse.Telemetry` for details.

  This module is used internally by the SDK. For direct API access,
  use `Langfuse.Client` instead.
  """

  @behaviour Langfuse.HTTPBehaviour

  alias Langfuse.Config

  @ingestion_path "/api/public/ingestion"
  @prompts_path "/api/public/v2/prompts"

  @typedoc "HTTP response result."
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Sends a batch of events to the ingestion API.

  Used internally by `Langfuse.Ingestion` to flush event batches.
  """
  @impl true
  @spec ingest(list(map())) :: response()
  def ingest(events) when is_list(events) do
    post(@ingestion_path, %{batch: events})
  end

  @doc """
  Fetches a prompt from the prompts API.

  Used internally by `Langfuse.Prompt`.

  ## Options

    * `:version` - Specific version number
    * `:label` - Label to fetch (e.g., "production")

  """
  @impl true
  @spec get_prompt(String.t(), keyword()) :: response()
  def get_prompt(name, opts \\ []) do
    params =
      [name: name]
      |> maybe_add(:version, opts[:version])
      |> maybe_add(:label, opts[:label])

    get(@prompts_path, params)
  end

  @doc """
  Makes a GET request to the Langfuse API.

  Returns `{:error, :not_configured}` if credentials are not set.
  """
  @impl true
  @spec get(String.t(), keyword()) :: response()
  def get(path, params \\ []) do
    config = Config.get()

    unless Config.configured?() do
      {:error, :not_configured}
    else
      request(:get, path, config, params: params)
    end
  end

  @doc """
  Makes a POST request to the Langfuse API.

  Returns `{:error, :not_configured}` if credentials are not set.
  """
  @impl true
  @spec post(String.t(), map()) :: response()
  def post(path, body) do
    config = Config.get()

    unless Config.configured?() do
      {:error, :not_configured}
    else
      request(:post, path, config, json: body)
    end
  end

  defp request(method, path, config, opts) do
    url = config.host <> path

    start_time = System.monotonic_time()
    metadata = %{method: method, path: path, host: config.host}

    :telemetry.execute(
      [:langfuse, :http, :request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result =
      [
        method: method,
        url: url,
        auth: {:basic, "#{config.public_key}:#{config.secret_key}"},
        retry: retry_options(config),
        receive_timeout: 30_000
      ]
      |> Keyword.merge(opts)
      |> Req.request()
      |> handle_response()

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:langfuse, :http, :request, :stop],
      %{duration: duration},
      Map.merge(metadata, %{result: result_type(result)})
    )

    result
  end

  defp retry_options(config) do
    [
      max_retries: config.max_retries,
      delay: &exponential_backoff/1,
      retry_log_level: :warning
    ]
  end

  defp exponential_backoff(attempt) do
    base_delay = 1000
    max_delay = 30_000
    delay = base_delay * Integer.pow(2, attempt - 1)
    jitter = :rand.uniform(500)
    min(delay + jitter, max_delay)
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp result_type({:ok, _}), do: :ok
  defp result_type({:error, _}), do: :error

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)
end
