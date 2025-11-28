defmodule Langfuse.TelemetryTest do
  use ExUnit.Case, async: true

  alias Langfuse.Telemetry

  describe "events/0" do
    test "returns all telemetry events" do
      events = Telemetry.events()

      assert is_list(events)
      assert length(events) == 7

      assert [:langfuse, :http, :request, :start] in events
      assert [:langfuse, :http, :request, :stop] in events
      assert [:langfuse, :ingestion, :flush, :start] in events
      assert [:langfuse, :ingestion, :flush, :stop] in events
      assert [:langfuse, :ingestion, :flush, :error] in events
      assert [:langfuse, :prompt, :fetch, :start] in events
      assert [:langfuse, :prompt, :fetch, :stop] in events
    end
  end

  describe "attach_default_logger/1" do
    test "attaches logger handler" do
      assert :ok = Telemetry.attach_default_logger()
      assert :ok = Telemetry.detach_default_logger()
    end

    test "returns error when already attached" do
      assert :ok = Telemetry.attach_default_logger()
      assert {:error, :already_exists} = Telemetry.attach_default_logger()
      assert :ok = Telemetry.detach_default_logger()
    end
  end

  describe "detach_default_logger/0" do
    test "returns error when not attached" do
      assert {:error, :not_found} = Telemetry.detach_default_logger()
    end
  end

  describe "attach_default_logger with custom level" do
    test "accepts level option" do
      assert :ok = Telemetry.attach_default_logger(level: :info)
      assert :ok = Telemetry.detach_default_logger()
    end
  end

  describe "handle_event/4" do
    import ExUnit.CaptureLog

    test "logs event with configured level" do
      log =
        capture_log(fn ->
          Telemetry.handle_event(
            [:langfuse, :http, :request, :stop],
            %{duration: 123_456},
            %{method: :post, path: "/test"},
            %{level: :info}
          )
        end)

      assert log =~ "[Langfuse]"
      assert log =~ "langfuse.http.request.stop"
      assert log =~ "duration"
    end

    test "logs at debug level" do
      log =
        capture_log([level: :debug], fn ->
          Telemetry.handle_event(
            [:langfuse, :ingestion, :flush, :start],
            %{batch_size: 10},
            %{},
            %{level: :debug}
          )
        end)

      assert log =~ "langfuse.ingestion.flush.start"
      assert log =~ "batch_size"
    end
  end
end
