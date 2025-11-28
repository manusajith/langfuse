defmodule Langfuse.SpanTest do
  use ExUnit.Case, async: false

  alias Langfuse.{Span, Trace}

  describe "new/2" do
    test "creates a span from a trace" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      span = Span.new(trace, name: "test-span")

      assert span.name == "test-span"
      assert span.trace_id == "trace-123"
      assert span.parent_observation_id == nil
      assert is_binary(span.id)
      assert %DateTime{} = span.start_time
    end

    test "creates a span from a parent span" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      parent_span = Span.new(trace, name: "parent", id: "parent-span-id")
      child_span = Span.new(parent_span, name: "child")

      assert child_span.name == "child"
      assert child_span.trace_id == "trace-123"
      assert child_span.parent_observation_id == "parent-span-id"
    end

    test "creates a span with optional fields" do
      trace = Trace.new(name: "test-trace")

      span =
        Span.new(trace,
          name: "test-span",
          input: %{query: "test"},
          output: %{results: []},
          metadata: %{key: "value"},
          level: :warning,
          status_message: "in progress"
        )

      assert span.input == %{query: "test"}
      assert span.output == %{results: []}
      assert span.metadata == %{key: "value"}
      assert span.level == :warning
      assert span.status_message == "in progress"
    end

    test "allows custom id" do
      trace = Trace.new(name: "test-trace")
      span = Span.new(trace, name: "test-span", id: "custom-span-id")

      assert span.id == "custom-span-id"
    end

    test "raises when name is missing" do
      trace = Trace.new(name: "test-trace")

      assert_raise KeyError, fn ->
        Span.new(trace, [])
      end
    end
  end

  describe "update/2" do
    test "updates span fields" do
      trace = Trace.new(name: "test-trace")
      span = Span.new(trace, name: "test-span")

      updated =
        Span.update(span,
          output: %{result: "done"},
          status_message: "completed"
        )

      assert updated.output == %{result: "done"}
      assert updated.status_message == "completed"
      assert updated.id == span.id
    end

    test "preserves unchanged fields" do
      trace = Trace.new(name: "test-trace")
      span = Span.new(trace, name: "test-span", input: %{query: "test"})
      updated = Span.update(span, output: %{result: "done"})

      assert updated.input == %{query: "test"}
      assert updated.output == %{result: "done"}
    end
  end

  describe "end_span/1" do
    test "sets end_time" do
      trace = Trace.new(name: "test-trace")
      span = Span.new(trace, name: "test-span")

      assert span.end_time == nil

      ended = Span.end_span(span)

      assert %DateTime{} = ended.end_time
    end
  end

  describe "get_id/1" do
    test "returns the span id" do
      trace = Trace.new(name: "test-trace")
      span = Span.new(trace, name: "test-span", id: "span-123")

      assert Span.get_id(span) == "span-123"
    end
  end

  describe "get_trace_id/1" do
    test "returns the trace id" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      span = Span.new(trace, name: "test-span")

      assert Span.get_trace_id(span) == "trace-123"
    end
  end

  describe "event capture" do
    test "new/2 sends span-create event" do
      {_span, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Trace.new(name: "test-trace")
          Span.new(trace, name: "test-span")
        end)

      span_events = Enum.filter(events, &(&1.type == "span-create"))
      assert length(span_events) == 1
      assert hd(span_events).body.name == "test-span"
    end

    test "update/2 sends span-update event" do
      {_span, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Trace.new(name: "test-trace")
          span = Span.new(trace, name: "test-span")
          Span.update(span, output: %{result: "done"})
        end)

      update_events = Enum.filter(events, &(&1.type == "span-update"))
      assert length(update_events) == 1
      assert update_events |> hd() |> Map.get(:body) |> Map.get(:output) == %{result: "done"}
    end

    test "end_span/1 sends span-update event with end_time" do
      {_span, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Trace.new(name: "test-trace")
          span = Span.new(trace, name: "test-span")
          Span.end_span(span)
        end)

      update_events = Enum.filter(events, &(&1.type == "span-update"))
      assert length(update_events) == 1
      assert update_events |> hd() |> Map.get(:body) |> Map.has_key?(:endTime)
    end

    test "events include required fields" do
      {_span, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Trace.new(name: "test-trace")
          Span.new(trace, name: "test-span")
        end)

      span_event = Enum.find(events, &(&1.type == "span-create"))

      assert is_binary(span_event.id)
      assert is_binary(span_event.timestamp)
      assert span_event.type == "span-create"
      assert is_map(span_event.body)
    end
  end
end
