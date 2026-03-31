defmodule Langfuse.Config do
  @moduledoc """
  Configuration management for the Langfuse SDK.

  The SDK reads configuration from application config and environment
  variables. Environment variables take precedence over application config.

  ## Application Configuration

  Configure Langfuse in your `config/config.exs` or runtime config:

      config :langfuse,
        public_key: "pk-lf-...",
        secret_key: "sk-lf-...",
        host: "https://cloud.langfuse.com",
        environment: "production",
        flush_interval: 5_000,
        batch_size: 100,
        max_retries: 3,
        enabled: true

  ## Environment Variables

  These environment variables override application config:

    * `LANGFUSE_PUBLIC_KEY` - API public key
    * `LANGFUSE_SECRET_KEY` - API secret key
    * `LANGFUSE_HOST` - Langfuse server URL
    * `LANGFUSE_ENVIRONMENT` - Environment name (e.g., "production", "staging")
    * `LANGFUSE_CACERTFILE` - Path to a custom CA certificate PEM file

  ## Configuration Options

    * `:public_key` - Langfuse API public key (required for API calls)
    * `:secret_key` - Langfuse API secret key (required for API calls)
    * `:host` - Langfuse server URL. Defaults to `"https://cloud.langfuse.com"`.
    * `:environment` - Environment name for filtering in Langfuse dashboard.
      Common values: `"production"`, `"staging"`, `"development"`.
    * `:flush_interval` - Interval in milliseconds between automatic flushes.
      Defaults to 5,000 (5 seconds).
    * `:batch_size` - Maximum events per batch before automatic flush.
      Defaults to 100.
    * `:max_retries` - Maximum retry attempts for failed requests.
      Defaults to 3.
    * `:enabled` - Whether tracing is enabled. Defaults to `true`.
      Set to `false` to disable all tracing (useful for tests).
    * `:debug` - Whether debug logging is enabled. Defaults to `false`.
      When enabled, logs detailed information about HTTP requests, batching,
      and event processing. Useful for troubleshooting integration issues.
    * `:cacertfile` - Path to a custom CA certificate PEM file for
      self-hosted Langfuse instances with self-signed certificates.

  ## Self-Hosted Langfuse

  For self-hosted Langfuse instances, set the host:

      config :langfuse,
        host: "https://langfuse.mycompany.com",
        public_key: "pk-...",
        secret_key: "sk-...",
        cacertfile: "/etc/ssl/langfuse-root-ca.pem"

  """

  use GenServer

  @default_host "https://cloud.langfuse.com"
  @default_flush_interval 5_000
  @default_batch_size 100
  @default_max_retries 3

  defstruct [
    :public_key,
    :secret_key,
    :host,
    :environment,
    :flush_interval,
    :batch_size,
    :max_retries,
    :enabled,
    :debug,
    :cacertfile
  ]

  @typedoc """
  Configuration struct containing all SDK settings.

  The struct is populated on application start from application config
  and environment variables.
  """
  @type t :: %__MODULE__{
          public_key: String.t() | nil,
          secret_key: String.t() | nil,
          host: String.t(),
          environment: String.t() | nil,
          flush_interval: pos_integer(),
          batch_size: pos_integer(),
          max_retries: non_neg_integer(),
          enabled: boolean(),
          debug: boolean(),
          cacertfile: String.t() | nil
        }

  @doc false
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the current configuration struct.

  ## Examples

      config = Langfuse.Config.get()
      config.host
      # => "https://cloud.langfuse.com"

  """
  @spec get() :: t()
  def get do
    GenServer.call(__MODULE__, :get)
  end

  @doc """
  Returns a specific configuration value by key.

  ## Examples

      Langfuse.Config.get(:host)
      # => "https://cloud.langfuse.com"

      Langfuse.Config.get(:batch_size)
      # => 100

  """
  @spec get(atom()) :: term()
  def get(key) when is_atom(key) do
    config = get()
    Map.get(config, key)
  end

  @doc """
  Returns whether tracing is enabled.

  When disabled, all tracing operations become no-ops.

  ## Examples

      Langfuse.Config.enabled?()
      # => true

  """
  @spec enabled?() :: boolean()
  def enabled? do
    get(:enabled)
  end

  @doc """
  Returns whether API credentials are configured.

  Returns `true` if both `:public_key` and `:secret_key` are set.

  ## Examples

      Langfuse.Config.configured?()
      # => true

  """
  @spec configured?() :: boolean()
  def configured? do
    config = get()
    not is_nil(config.public_key) and not is_nil(config.secret_key)
  end

  @doc """
  Returns whether debug logging is enabled.

  When enabled, the SDK logs detailed information about HTTP requests,
  batching, and event processing to help troubleshoot integration issues.

  ## Examples

      Langfuse.Config.debug?()
      # => false

  """
  @spec debug?() :: boolean()
  def debug? do
    get(:debug)
  end

  @doc """
  Reloads configuration from application environment.

  This is primarily useful for testing when you need to change
  configuration values at runtime.

  ## Examples

      Application.put_env(:langfuse, :host, "https://custom.langfuse.com")
      Langfuse.Config.reload()

  """
  @spec reload() :: :ok
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @impl true
  def init(_opts) do
    config = load_config()
    {:ok, config}
  end

  @impl true
  def handle_call(:get, _from, config) do
    {:reply, config, config}
  end

  def handle_call(:reload, _from, _config) do
    new_config = load_config()
    {:reply, :ok, new_config}
  end

  defp load_config do
    %__MODULE__{
      public_key: get_value(:public_key, "LANGFUSE_PUBLIC_KEY"),
      secret_key: get_value(:secret_key, "LANGFUSE_SECRET_KEY"),
      host: get_value(:host, "LANGFUSE_HOST") || @default_host,
      environment: get_value(:environment, "LANGFUSE_ENVIRONMENT"),
      flush_interval: get_integer(:flush_interval) || @default_flush_interval,
      batch_size: get_integer(:batch_size) || @default_batch_size,
      max_retries: get_integer(:max_retries) || @default_max_retries,
      enabled: get_boolean(:enabled, true),
      debug: get_boolean(:debug, false),
      cacertfile: get_value(:cacertfile, "LANGFUSE_CACERTFILE")
    }
  end

  defp get_value(key, env_var) do
    System.get_env(env_var) || Application.get_env(:langfuse, key)
  end

  defp get_integer(key) do
    case Application.get_env(:langfuse, key) do
      nil -> nil
      val when is_integer(val) -> val
      val when is_binary(val) -> String.to_integer(val)
    end
  end

  defp get_boolean(key, default) do
    case Application.get_env(:langfuse, key) do
      nil -> default
      val when is_boolean(val) -> val
      "true" -> true
      "false" -> false
      _ -> default
    end
  end
end
