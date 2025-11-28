defmodule Langfuse.GenerationTest do
  use ExUnit.Case, async: false

  alias Langfuse.{Generation, Trace, Span}

  describe "new/2" do
    test "creates a generation from a trace" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      gen = Generation.new(trace, name: "llm-call")

      assert gen.name == "llm-call"
      assert gen.trace_id == "trace-123"
      assert gen.parent_observation_id == nil
      assert is_binary(gen.id)
      assert %DateTime{} = gen.start_time
    end

    test "creates a generation from a span" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      span = Span.new(trace, name: "parent-span", id: "span-123")
      gen = Generation.new(span, name: "llm-call")

      assert gen.trace_id == "trace-123"
      assert gen.parent_observation_id == "span-123"
    end

    test "creates a generation with model details" do
      trace = Trace.new(name: "test-trace")

      gen =
        Generation.new(trace,
          name: "chat-completion",
          model: "gpt-4",
          model_parameters: %{temperature: 0.7, max_tokens: 1000}
        )

      assert gen.model == "gpt-4"
      assert gen.model_parameters == %{temperature: 0.7, max_tokens: 1000}
    end

    test "creates a generation with input/output" do
      trace = Trace.new(name: "test-trace")

      gen =
        Generation.new(trace,
          name: "chat",
          input: [%{role: "user", content: "Hello"}],
          output: %{role: "assistant", content: "Hi!"}
        )

      assert gen.input == [%{role: "user", content: "Hello"}]
      assert gen.output == %{role: "assistant", content: "Hi!"}
    end

    test "creates a generation with usage" do
      trace = Trace.new(name: "test-trace")

      gen =
        Generation.new(trace,
          name: "chat",
          usage: %{input: 10, output: 20, total: 30}
        )

      assert gen.usage == %{input: 10, output: 20, total: 30}
    end

    test "creates a generation with prompt reference" do
      trace = Trace.new(name: "test-trace")

      gen =
        Generation.new(trace,
          name: "chat",
          prompt_name: "chat-template",
          prompt_version: 2
        )

      assert gen.prompt_name == "chat-template"
      assert gen.prompt_version == 2
    end

    test "raises when name is missing" do
      trace = Trace.new(name: "test-trace")

      assert_raise KeyError, fn ->
        Generation.new(trace, [])
      end
    end
  end

  describe "update/2" do
    test "updates generation fields" do
      trace = Trace.new(name: "test-trace")
      gen = Generation.new(trace, name: "chat", model: "gpt-4")

      updated =
        Generation.update(gen,
          output: %{content: "response"},
          usage: %{input: 10, output: 5, total: 15}
        )

      assert updated.output == %{content: "response"}
      assert updated.usage == %{input: 10, output: 5, total: 15}
      assert updated.id == gen.id
      assert updated.model == "gpt-4"
    end
  end

  describe "end_generation/1" do
    test "sets end_time" do
      trace = Trace.new(name: "test-trace")
      gen = Generation.new(trace, name: "chat")

      assert gen.end_time == nil

      ended = Generation.end_generation(gen)

      assert %DateTime{} = ended.end_time
    end
  end

  describe "get_id/1" do
    test "returns the generation id" do
      trace = Trace.new(name: "test-trace")
      gen = Generation.new(trace, name: "chat", id: "gen-123")

      assert Generation.get_id(gen) == "gen-123"
    end
  end

  describe "get_trace_id/1" do
    test "returns the trace id" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      gen = Generation.new(trace, name: "chat")

      assert Generation.get_trace_id(gen) == "trace-123"
    end
  end

  describe "event capture" do
    test "new/2 sends generation-create event" do
      {_gen, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Trace.new(name: "test-trace")
          Generation.new(trace, name: "llm-call", model: "gpt-4")
        end)

      gen_events = Enum.filter(events, &(&1.type == "generation-create"))
      assert length(gen_events) == 1
      assert hd(gen_events).body.name == "llm-call"
      assert hd(gen_events).body.model == "gpt-4"
    end

    test "update/2 sends generation-update event" do
      {_gen, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Trace.new(name: "test-trace")
          gen = Generation.new(trace, name: "llm-call")
          Generation.update(gen, output: %{content: "response"})
        end)

      update_events = Enum.filter(events, &(&1.type == "generation-update"))
      assert length(update_events) == 1
      assert update_events |> hd() |> Map.get(:body) |> Map.get(:output) == %{content: "response"}
    end

    test "end_generation/1 sends generation-update event with end_time" do
      {_gen, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Trace.new(name: "test-trace")
          gen = Generation.new(trace, name: "llm-call")
          Generation.end_generation(gen)
        end)

      update_events = Enum.filter(events, &(&1.type == "generation-update"))
      assert length(update_events) == 1
      assert update_events |> hd() |> Map.get(:body) |> Map.has_key?(:endTime)
    end

    test "events include required fields" do
      {_gen, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Trace.new(name: "test-trace")
          Generation.new(trace, name: "llm-call")
        end)

      gen_event = Enum.find(events, &(&1.type == "generation-create"))

      assert is_binary(gen_event.id)
      assert is_binary(gen_event.timestamp)
      assert gen_event.type == "generation-create"
      assert is_map(gen_event.body)
    end
  end
end
