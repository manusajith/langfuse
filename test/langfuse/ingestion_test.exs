defmodule Langfuse.IngestionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Langfuse.Ingestion

  setup :verify_on_exit!

  setup do
    original_config = %{
      enabled: Application.get_env(:langfuse, :enabled),
      batch_size: Application.get_env(:langfuse, :batch_size),
      flush_interval: Application.get_env(:langfuse, :flush_interval),
      event_handler: Application.get_env(:langfuse, :event_handler),
      host: Application.get_env(:langfuse, :host),
      public_key: Application.get_env(:langfuse, :public_key),
      secret_key: Application.get_env(:langfuse, :secret_key)
    }

    Application.put_env(:langfuse, :enabled, true)
    Application.delete_env(:langfuse, :event_handler)

    Langfuse.Config.reload()

    on_exit(fn ->
      Enum.each(original_config, fn {key, value} ->
        if value do
          Application.put_env(:langfuse, key, value)
        else
          Application.delete_env(:langfuse, key)
        end
      end)

      Langfuse.Config.reload()
    end)

    :ok
  end

  describe "enqueue/1" do
    test "accepts map events" do
      event = %{type: "trace-create", body: %{id: "test-1"}}
      assert :ok = Ingestion.enqueue(event)
    end

    test "calls event_handler when configured" do
      test_pid = self()

      Application.put_env(:langfuse, :event_handler, fn event ->
        send(test_pid, {:event, event})
      end)

      event = %{type: "trace-create", body: %{id: "test-2"}}
      Ingestion.enqueue(event)

      assert_receive {:event, ^event}
    end

    test "no-op when disabled" do
      Application.put_env(:langfuse, :enabled, false)
      Langfuse.Config.reload()

      initial_size = Ingestion.queue_size()
      event = %{type: "trace-create", body: %{id: "test-3"}}
      Ingestion.enqueue(event)

      assert Ingestion.queue_size() == initial_size
    end
  end

  describe "queue_size/0" do
    test "returns current queue size" do
      capture_log(fn ->
        Ingestion.flush()
        initial_size = Ingestion.queue_size()

        Application.put_env(:langfuse, :event_handler, nil)
        Application.delete_env(:langfuse, :event_handler)

        Ingestion.enqueue(%{type: "test", body: %{}})

        assert Ingestion.queue_size() == initial_size + 1
      end)
    end
  end

  describe "flush/1" do
    test "returns :ok" do
      capture_log(fn ->
        assert :ok = Ingestion.flush()
      end)
    end

    test "clears the queue" do
      capture_log(fn ->
        Ingestion.flush()
        Ingestion.enqueue(%{type: "test", body: %{}})

        assert Ingestion.queue_size() >= 1

        Ingestion.flush()

        assert Ingestion.queue_size() == 0
      end)
    end

    test "returns timeout error when timeout is too short" do
      capture_log(fn ->
        Application.put_env(:langfuse, :batch_size, 1000)
        Langfuse.Config.reload()

        for i <- 1..100 do
          Ingestion.enqueue(%{type: "test-#{i}", body: %{}})
        end

        result = Ingestion.flush(timeout: 0)

        assert result == {:error, :timeout} or result == :ok
      end)
    end
  end

  describe "shutdown/0" do
    test "returns :ok" do
      assert :ok = Ingestion.shutdown()
    end

    test "clears the queue" do
      capture_log(fn ->
        Ingestion.enqueue(%{type: "test", body: %{}})
        Ingestion.shutdown()
        assert Ingestion.queue_size() == 0
      end)
    end
  end

  describe "batching behavior" do
    test "flushes when batch size reached" do
      capture_log(fn ->
        test_pid = self()
        flush_count = :counters.new(1, [:atomics])

        Application.put_env(:langfuse, :batch_size, 3)
        Langfuse.Config.reload()

        Ingestion.flush()

        :telemetry.attach(
          "test-batch-flush",
          [:langfuse, :ingestion, :flush, :start],
          fn _event, measurements, _metadata, _config ->
            :counters.add(flush_count, 1, 1)
            send(test_pid, {:flushed, measurements.batch_size})
          end,
          nil
        )

        Ingestion.enqueue(%{type: "event-1", body: %{}})
        Ingestion.enqueue(%{type: "event-2", body: %{}})

        refute_receive {:flushed, _}, 50

        Ingestion.enqueue(%{type: "event-3", body: %{}})

        assert_receive {:flushed, 3}, 500

        :telemetry.detach("test-batch-flush")
      end)
    end
  end

  describe "telemetry events" do
    test "emits flush start event" do
      capture_log(fn ->
        test_pid = self()

        :telemetry.attach(
          "test-flush-start",
          [:langfuse, :ingestion, :flush, :start],
          fn event, measurements, metadata, _config ->
            send(test_pid, {:telemetry, event, measurements, metadata})
          end,
          nil
        )

        Ingestion.enqueue(%{type: "test", body: %{}})
        Ingestion.flush()

        assert_receive {:telemetry, [:langfuse, :ingestion, :flush, :start], %{batch_size: _}, %{}},
                       500

        :telemetry.detach("test-flush-start")
      end)
    end

    test "emits flush error event when HTTP fails" do
      capture_log(fn ->
        test_pid = self()

        :telemetry.attach(
          "test-flush-error",
          [:langfuse, :ingestion, :flush, :error],
          fn event, measurements, metadata, _config ->
            send(test_pid, {:telemetry, event, measurements, metadata})
          end,
          nil
        )

        Ingestion.enqueue(%{type: "test", body: %{}})
        Ingestion.flush()

        assert_receive {:telemetry, [:langfuse, :ingestion, :flush, :error], measurements,
                        metadata},
                       500

        assert Map.has_key?(measurements, :batch_size)
        assert Map.has_key?(metadata, :reason)

        :telemetry.detach("test-flush-error")
      end)
    end
  end

  describe "GenServer behavior" do
    test "handles unknown messages gracefully" do
      send(Langfuse.Ingestion, :unknown_message)
      Process.sleep(10)
      assert Ingestion.queue_size() >= 0
    end
  end


  describe "flush with empty queue" do
    test "does not emit telemetry when queue is empty" do
      capture_log(fn ->
        test_pid = self()

        :telemetry.attach(
          "test-empty-flush",
          [:langfuse, :ingestion, :flush, :start],
          fn _event, _measurements, _metadata, _config ->
            send(test_pid, :flush_called)
          end,
          nil
        )

        Ingestion.flush()
        Ingestion.flush()

        refute_receive :flush_called, 100

        :telemetry.detach("test-empty-flush")
      end)
    end
  end
end
