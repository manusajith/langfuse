defmodule Langfuse.EventTest do
  use ExUnit.Case, async: true

  alias Langfuse.{Event, Span, Trace}

  describe "new/2" do
    test "creates an event from a trace" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      event = Event.new(trace, name: "user-action")

      assert event.name == "user-action"
      assert event.trace_id == "trace-123"
      assert event.parent_observation_id == nil
      assert is_binary(event.id)
      assert %DateTime{} = event.start_time
    end

    test "creates an event from a span" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      span = Span.new(trace, name: "parent-span", id: "span-123")
      event = Event.new(span, name: "milestone")

      assert event.trace_id == "trace-123"
      assert event.parent_observation_id == "span-123"
    end

    test "creates an event with optional fields" do
      trace = Trace.new(name: "test-trace")

      event =
        Event.new(trace,
          name: "error-occurred",
          input: %{request: "data"},
          output: %{error: "something went wrong"},
          metadata: %{severity: "high"},
          level: :error,
          status_message: "failed"
        )

      assert event.input == %{request: "data"}
      assert event.output == %{error: "something went wrong"}
      assert event.metadata == %{severity: "high"}
      assert event.level == :error
      assert event.status_message == "failed"
    end

    test "allows custom id" do
      trace = Trace.new(name: "test-trace")
      event = Event.new(trace, name: "custom-event", id: "event-123")

      assert event.id == "event-123"
    end

    test "allows custom start_time" do
      trace = Trace.new(name: "test-trace")
      timestamp = ~U[2025-01-15 10:30:00Z]
      event = Event.new(trace, name: "timed-event", start_time: timestamp)

      assert event.start_time == timestamp
    end

    test "raises when name is missing" do
      trace = Trace.new(name: "test-trace")

      assert_raise KeyError, fn ->
        Event.new(trace, [])
      end
    end
  end

  describe "get_id/1" do
    test "returns the event id" do
      trace = Trace.new(name: "test-trace")
      event = Event.new(trace, name: "test-event", id: "event-123")

      assert Event.get_id(event) == "event-123"
    end
  end

  describe "get_trace_id/1" do
    test "returns the trace id" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      event = Event.new(trace, name: "test-event")

      assert Event.get_trace_id(event) == "trace-123"
    end
  end
end
