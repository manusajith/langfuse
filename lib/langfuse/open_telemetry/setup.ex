defmodule Langfuse.OpenTelemetry.Setup do
  @moduledoc """
  Setup helpers for OpenTelemetry integration with Langfuse.

  This module provides convenience functions for configuring OpenTelemetry
  to work with Langfuse. It supports both the native OTEL export mode and
  the span processor mode.

  ## Setup Mode: Native OTEL Export

  Send spans directly to Langfuse's OTEL endpoint using the standard exporter:

      Langfuse.OpenTelemetry.Setup.configure_exporter()

  This configures `opentelemetry_exporter` to send traces to Langfuse.

  ## Setup Mode: Span Processor

  Use Langfuse's span processor to intercept and convert OTEL spans:

      Langfuse.OpenTelemetry.Setup.register_processor()

  The span processor provides more control over which spans are sent to
  Langfuse and how they are converted to observations.

  ## Combining Both Modes

  You can use both modes simultaneously - the exporter for complete OTEL
  compatibility and the processor for custom handling:

      Langfuse.OpenTelemetry.Setup.configure_exporter()
      Langfuse.OpenTelemetry.Setup.register_processor(filter_fn: &my_filter/1)

  """

  alias Langfuse.Config

  @doc """
  Returns OpenTelemetry exporter configuration for Langfuse.

  Generates the configuration needed for `opentelemetry_exporter` to send
  spans to Langfuse's OTEL ingestion endpoint.

  ## Options

    * `:host` - Langfuse host (default: from config)
    * `:public_key` - Public API key (default: from config)
    * `:secret_key` - Secret API key (default: from config)
    * `:cacertfile` - Path to a PEM-encoded CA certificate file for self-hosted
      Langfuse instances with self-signed certificates (default: from config)

  ## Examples

      # Get config for runtime.exs
      config = Langfuse.OpenTelemetry.Setup.exporter_config()

      # Use in config/runtime.exs:
      config :opentelemetry_exporter,
        otlp_protocol: config[:otlp_protocol],
        otlp_endpoint: config[:otlp_endpoint],
        otlp_headers: config[:otlp_headers],
        ssl_options: config[:ssl_options]

  """
  @spec exporter_config(keyword()) :: keyword()
  def exporter_config(opts \\ []) do
    config = Config.get()

    host = Keyword.get(opts, :host, config.host || "https://cloud.langfuse.com")
    public_key = Keyword.get(opts, :public_key, config.public_key)
    secret_key = Keyword.get(opts, :secret_key, config.secret_key)
    cacertfile = Keyword.get(opts, :cacertfile, config.cacertfile)

    auth = Base.encode64("#{public_key}:#{secret_key}")

    [
      otlp_protocol: :http_protobuf,
      otlp_endpoint: "#{host}/api/public/otel/v1/traces",
      otlp_headers: [{"Authorization", "Basic #{auth}"}]
    ]
    |> maybe_put(:ssl_options, exporter_ssl_options(cacertfile))
  end

  @doc """
  Configures the OpenTelemetry exporter to send to Langfuse.

  This function sets up the `opentelemetry_exporter` application to export
  spans to Langfuse. Call this during application startup.

  ## Options

    * `:host` - Langfuse host (default: from config)
    * `:public_key` - Public API key (default: from config)
    * `:secret_key` - Secret API key (default: from config)
    * `:cacertfile` - Path to a PEM-encoded CA certificate file for self-hosted
      Langfuse instances with self-signed certificates (default: from config)

  ## Examples

      # In your application's start/2:
      def start(_type, _args) do
        Langfuse.OpenTelemetry.Setup.configure_exporter()

        children = [...]
        Supervisor.start_link(children, strategy: :one_for_one)
      end

  """
  @spec configure_exporter(keyword()) :: :ok
  def configure_exporter(opts \\ []) do
    config = exporter_config(opts)

    Application.put_env(:opentelemetry_exporter, :otlp_protocol, config[:otlp_protocol])
    Application.put_env(:opentelemetry_exporter, :otlp_endpoint, config[:otlp_endpoint])
    Application.put_env(:opentelemetry_exporter, :otlp_headers, config[:otlp_headers])
    put_optional_env(:opentelemetry_exporter, :ssl_options, config[:ssl_options])

    :ok
  end

  @doc """
  Returns the span processor configuration for adding to OpenTelemetry config.

  The Langfuse span processor intercepts completed spans and converts them to
  Langfuse observations. Add this to your OpenTelemetry configuration.

  ## Options

    * `:enabled` - Whether the processor is active (default: true)
    * `:filter_fn` - Function to filter which spans to process

  ## Examples

      # In config/runtime.exs:
      config :opentelemetry,
        processors: [
          {:otel_batch_processor, %{}},
          Langfuse.OpenTelemetry.Setup.processor_config()
        ]

      # With filtering:
      config :opentelemetry,
        processors: [
          Langfuse.OpenTelemetry.Setup.processor_config(
            filter_fn: fn span ->
              attrs = elem(span, 7)
              Map.has_key?(attrs, "gen_ai.request.model")
            end
          )
        ]

  """
  @spec processor_config(keyword()) :: {module(), map()}
  def processor_config(opts \\ []) do
    config = %{
      enabled: Keyword.get(opts, :enabled, true),
      filter_fn: Keyword.get(opts, :filter_fn)
    }

    {Langfuse.OpenTelemetry.SpanProcessor, config}
  end

  @doc """
  Returns OpenTelemetry SDK configuration for use with Langfuse.

  Provides configuration suitable for `config/runtime.exs` that sets up
  both the standard OTEL batch processor and the Langfuse span processor.

  ## Examples

      # In config/runtime.exs:
      otel_config = Langfuse.OpenTelemetry.Setup.sdk_config()

      config :opentelemetry,
        resource: otel_config[:resource],
        span_processor: otel_config[:span_processor],
        traces_exporter: otel_config[:traces_exporter]

  """
  @spec sdk_config(keyword()) :: keyword()
  def sdk_config(opts \\ []) do
    service_name = Keyword.get(opts, :service_name, "langfuse-elixir")

    [
      resource: [
        service: [name: service_name]
      ],
      span_processor: :batch,
      traces_exporter: :otlp
    ]
  end

  @doc """
  Checks if OpenTelemetry is available and properly configured.

  Returns information about the OTEL setup status.

  ## Examples

      case Langfuse.OpenTelemetry.Setup.status() do
        {:ok, info} -> IO.inspect(info)
        {:error, :not_available} -> IO.puts("OpenTelemetry not installed")
      end

  """
  @spec status() :: {:ok, map()} | {:error, atom()}
  def status do
    {:ok,
     %{
       opentelemetry_loaded: true,
       tracer_provider: safe_get_tracer_provider(),
       langfuse_configured: Config.configured?()
     }}
  end

  defp safe_get_tracer_provider do
    :otel_tracer_provider.resource()
    true
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp exporter_ssl_options(nil), do: nil
  defp exporter_ssl_options(path) when is_binary(path), do: [cacertfile: path]

  defp maybe_put(config, _key, nil), do: config
  defp maybe_put(config, key, value), do: Keyword.put(config, key, value)

  defp put_optional_env(app, key, nil), do: Application.delete_env(app, key)
  defp put_optional_env(app, key, value), do: Application.put_env(app, key, value)
end
