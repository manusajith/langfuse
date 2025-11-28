defmodule Langfuse.HTTP do
  @moduledoc """
  HTTP client for Langfuse API using Req.

  Handles authentication, retries with exponential backoff, and telemetry.
  """

  alias Langfuse.Config

  @ingestion_path "/api/public/ingestion"
  @prompts_path "/api/public/v2/prompts"

  @type response :: {:ok, map()} | {:error, term()}

  @spec ingest(list(map())) :: response()
  def ingest(events) when is_list(events) do
    post(@ingestion_path, %{batch: events})
  end

  @spec get_prompt(String.t(), keyword()) :: response()
  def get_prompt(name, opts \\ []) do
    params =
      [name: name]
      |> maybe_add(:version, opts[:version])
      |> maybe_add(:label, opts[:label])

    get(@prompts_path, params)
  end

  @spec get(String.t(), keyword()) :: response()
  def get(path, params \\ []) do
    config = Config.get()

    unless Config.configured?() do
      {:error, :not_configured}
    else
      request(:get, path, config, params: params)
    end
  end

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
