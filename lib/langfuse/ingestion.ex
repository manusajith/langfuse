defmodule Langfuse.Ingestion do
  @moduledoc """
  GenServer for async event batching and ingestion to Langfuse.

  Events are queued and sent in batches either when:
  - The batch size is reached
  - The flush interval timer fires
  - `flush/1` is called explicitly

  This module handles graceful shutdown, ensuring all pending events
  are flushed before the application terminates.
  """

  use GenServer
  require Logger

  alias Langfuse.{Config, HTTP}

  defstruct [
    :flush_timer,
    queue: :queue.new(),
    queue_size: 0
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec enqueue(map()) :: :ok
  def enqueue(event) when is_map(event) do
    if Config.enabled?() do
      GenServer.cast(__MODULE__, {:enqueue, event})
    else
      :ok
    end
  end

  @spec flush(keyword()) :: :ok | {:error, :timeout}
  def flush(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    try do
      GenServer.call(__MODULE__, :flush, timeout)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  @spec shutdown() :: :ok
  def shutdown do
    GenServer.call(__MODULE__, :shutdown, 30_000)
  end

  @spec queue_size() :: non_neg_integer()
  def queue_size do
    GenServer.call(__MODULE__, :queue_size)
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    state = schedule_flush(%__MODULE__{})
    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue, event}, state) do
    new_queue = :queue.in(event, state.queue)
    new_size = state.queue_size + 1
    new_state = %{state | queue: new_queue, queue_size: new_size}

    config = Config.get()

    if new_size >= config.batch_size do
      {:noreply, do_flush(new_state)}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = do_flush(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:shutdown, _from, state) do
    new_state = do_flush(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:queue_size, _from, state) do
    {:reply, state.queue_size, state}
  end

  @impl true
  def handle_info(:flush_timer, state) do
    new_state =
      state
      |> do_flush()
      |> schedule_flush()

    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    do_flush(state)
    :ok
  end

  defp do_flush(%{queue_size: 0} = state), do: state

  defp do_flush(state) do
    events = :queue.to_list(state.queue)

    :telemetry.execute(
      [:langfuse, :ingestion, :flush, :start],
      %{batch_size: length(events)},
      %{}
    )

    case HTTP.ingest(events) do
      {:ok, response} ->
        handle_ingestion_response(response, events)

      {:error, reason} ->
        Logger.warning("[Langfuse] Failed to ingest events: #{inspect(reason)}")

        :telemetry.execute(
          [:langfuse, :ingestion, :flush, :error],
          %{batch_size: length(events)},
          %{reason: reason}
        )
    end

    %{state | queue: :queue.new(), queue_size: 0}
  end

  defp handle_ingestion_response(%{"successes" => successes, "errors" => errors}, events) do
    success_count = length(successes)
    error_count = length(errors)

    if error_count > 0 do
      Logger.warning("[Langfuse] Ingestion completed with #{error_count} errors: #{inspect(errors)}")
    end

    :telemetry.execute(
      [:langfuse, :ingestion, :flush, :stop],
      %{batch_size: length(events), success_count: success_count, error_count: error_count},
      %{}
    )
  end

  defp handle_ingestion_response(_response, events) do
    :telemetry.execute(
      [:langfuse, :ingestion, :flush, :stop],
      %{batch_size: length(events), success_count: length(events), error_count: 0},
      %{}
    )
  end

  defp schedule_flush(state) do
    if state.flush_timer do
      Process.cancel_timer(state.flush_timer)
    end

    config = Config.get()
    timer = Process.send_after(self(), :flush_timer, config.flush_interval)
    %{state | flush_timer: timer}
  end
end
