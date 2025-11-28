defmodule Langfuse.Telemetry do
  @moduledoc """
  Telemetry events emitted by the Langfuse SDK.

  The SDK emits telemetry events for HTTP requests and batch ingestion,
  enabling monitoring, logging, and metrics collection using the
  standard Erlang telemetry library.

  ## Event Format

  All events follow the telemetry convention:

    * Event name is a list of atoms
    * Measurements contain numeric values
    * Metadata contains contextual information

  ## HTTP Events

    * `[:langfuse, :http, :request, :start]` - HTTP request initiated
      * Measurements: `%{system_time: integer}`
      * Metadata: `%{method: atom, path: String.t, host: String.t}`

    * `[:langfuse, :http, :request, :stop]` - HTTP request completed
      * Measurements: `%{duration: integer}` (native time units)
      * Metadata: `%{method: atom, path: String.t, host: String.t, result: :ok | :error}`

  ## Ingestion Events

    * `[:langfuse, :ingestion, :flush, :start]` - Batch flush initiated
      * Measurements: `%{batch_size: integer}`
      * Metadata: `%{}`

    * `[:langfuse, :ingestion, :flush, :stop]` - Batch flush completed
      * Measurements: `%{batch_size: integer, success_count: integer, error_count: integer}`
      * Metadata: `%{}`

    * `[:langfuse, :ingestion, :flush, :error]` - Batch flush failed
      * Measurements: `%{batch_size: integer}`
      * Metadata: `%{reason: term}`

  ## Prompt Events

    * `[:langfuse, :prompt, :fetch, :start]` - Prompt fetch initiated
      * Measurements: `%{system_time: integer}`
      * Metadata: `%{name: String.t, version: integer | nil, label: String.t | nil}`

    * `[:langfuse, :prompt, :fetch, :stop]` - Prompt fetch completed
      * Measurements: `%{duration: integer}`
      * Metadata: `%{name: String.t, result: :ok | :error | :cache_hit}`

  ## Attaching Handlers

  Attach your own handlers using `:telemetry.attach/4`:

      :telemetry.attach(
        "my-langfuse-handler",
        [:langfuse, :http, :request, :stop],
        fn _event, measurements, metadata, _config ->
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
          Logger.info("Langfuse HTTP request took \#{duration_ms}ms")
        end,
        nil
      )

  Or use the built-in debug logger:

      Langfuse.Telemetry.attach_default_logger()

  """

  @doc """
  Returns all telemetry event names emitted by this library.

  Useful for attaching handlers to all events at once.

  ## Examples

      Langfuse.Telemetry.events()
      # => [[:langfuse, :http, :request, :start], ...]

      :telemetry.attach_many("my-handler", Langfuse.Telemetry.events(), &handler/4, nil)

  """
  @spec events() :: list(list(atom()))
  def events do
    [
      [:langfuse, :http, :request, :start],
      [:langfuse, :http, :request, :stop],
      [:langfuse, :ingestion, :flush, :start],
      [:langfuse, :ingestion, :flush, :stop],
      [:langfuse, :ingestion, :flush, :error],
      [:langfuse, :prompt, :fetch, :start],
      [:langfuse, :prompt, :fetch, :stop]
    ]
  end

  @doc """
  Attaches a default logger handler for all Langfuse telemetry events.

  Useful for debugging. Logs all events with the specified log level.

  ## Options

    * `:level` - Log level. Defaults to `:debug`.

  ## Examples

      Langfuse.Telemetry.attach_default_logger()
      # => :ok

      Langfuse.Telemetry.attach_default_logger(level: :info)
      # => :ok

  ## Log Output

  Events are logged in the format:

      [Langfuse] langfuse.http.request.stop %{duration: 123456} %{method: :post, ...}

  """
  @spec attach_default_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)

    :telemetry.attach_many(
      "langfuse-default-logger",
      events(),
      &log_event/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the default logger handler.

  ## Examples

      Langfuse.Telemetry.detach_default_logger()
      # => :ok

  """
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger do
    :telemetry.detach("langfuse-default-logger")
  end

  defp log_event(event, measurements, metadata, %{level: level}) do
    require Logger
    event_name = Enum.join(event, ".")
    Logger.log(level, "[Langfuse] #{event_name} #{inspect(measurements)} #{inspect(metadata)}")
  end
end
