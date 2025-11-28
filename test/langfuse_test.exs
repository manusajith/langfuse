defmodule LangfuseTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  describe "update/2" do
    test "updates a span" do
      capture_log(fn ->
        trace = Langfuse.trace(name: "test")
        span = Langfuse.span(trace, name: "span")

        updated = Langfuse.update(span, output: %{result: "done"}, level: :warning)

        assert updated.output == %{result: "done"}
        assert updated.level == :warning
      end)
    end

    test "updates a generation" do
      capture_log(fn ->
        trace = Langfuse.trace(name: "test")
        gen = Langfuse.generation(trace, name: "gen", model: "gpt-4")

        updated =
          Langfuse.update(gen,
            output: "Response text",
            usage: %{input: 100, output: 50}
          )

        assert updated.output == "Response text"
        assert updated.usage == %{input: 100, output: 50}
      end)
    end

    test "replaces metadata" do
      capture_log(fn ->
        trace = Langfuse.trace(name: "test")
        span = Langfuse.span(trace, name: "span", metadata: %{initial: true})

        updated = Langfuse.update(span, metadata: %{updated: true})

        assert updated.metadata == %{updated: true}
      end)
    end
  end

  describe "end_observation/1" do
    test "ends a span and sets end_time" do
      capture_log(fn ->
        trace = Langfuse.trace(name: "test")
        span = Langfuse.span(trace, name: "span")

        assert span.end_time == nil

        ended = Langfuse.end_observation(span)

        assert ended.end_time != nil
        assert %DateTime{} = ended.end_time
      end)
    end

    test "ends a generation and sets end_time" do
      capture_log(fn ->
        trace = Langfuse.trace(name: "test")
        gen = Langfuse.generation(trace, name: "gen", model: "gpt-4")

        assert gen.end_time == nil

        ended = Langfuse.end_observation(gen)

        assert ended.end_time != nil
        assert %DateTime{} = ended.end_time
      end)
    end
  end

  describe "flush/1" do
    test "returns :ok" do
      capture_log(fn ->
        assert :ok = Langfuse.flush()
      end)
    end

    test "accepts timeout option" do
      capture_log(fn ->
        result = Langfuse.flush(timeout: 1000)
        assert result == :ok or result == {:error, :timeout}
      end)
    end
  end

  describe "shutdown/0" do
    test "returns :ok" do
      capture_log(fn ->
        assert :ok = Langfuse.shutdown()
      end)
    end
  end

  describe "auth_check/0" do
    test "returns boolean" do
      result = Langfuse.auth_check()
      assert is_boolean(result)
    end
  end

  describe "integration workflow" do
    test "complete trace with span and generation" do
      {_result, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Langfuse.trace(name: "integration-test", user_id: "test-user")

          span = Langfuse.span(trace, name: "retrieval", input: %{query: "test"})
          span = Langfuse.update(span, output: %{docs: ["doc1", "doc2"]})
          _span = Langfuse.end_observation(span)

          gen =
            Langfuse.generation(trace,
              name: "completion",
              model: "gpt-4",
              input: [%{role: "user", content: "Hello"}]
            )

          gen = Langfuse.update(gen, output: "Hi there!", usage: %{input: 10, output: 5})
          gen = Langfuse.end_observation(gen)

          Langfuse.score(trace, name: "quality", value: 0.9)
          Langfuse.score(gen, name: "relevance", value: 0.85)

          Langfuse.event(trace, name: "completed")

          :done
        end)

      assert Enum.any?(events, &(&1.type == "trace-create"))
      assert Enum.any?(events, &(&1.type == "span-create"))
      assert Enum.any?(events, &(&1.type == "span-update"))
      assert Enum.any?(events, &(&1.type == "generation-create"))
      assert Enum.any?(events, &(&1.type == "generation-update"))
      assert Enum.any?(events, &(&1.type == "score-create"))
      assert Enum.any?(events, &(&1.type == "event-create"))
    end

    test "nested spans" do
      {_result, events} =
        Langfuse.Test.Helpers.capture_events(fn ->
          trace = Langfuse.trace(name: "nested-test")

          outer_span = Langfuse.span(trace, name: "outer")

          inner_span = Langfuse.span(outer_span, name: "inner")
          _inner_span = Langfuse.end_observation(inner_span)

          _outer_span = Langfuse.end_observation(outer_span)
        end)

      span_events = Enum.filter(events, &(&1.type == "span-create"))
      assert length(span_events) == 2

      inner_event = Enum.find(span_events, &(&1.body.name == "inner"))
      outer_event = Enum.find(span_events, &(&1.body.name == "outer"))

      assert inner_event.body.parentObservationId == outer_event.body.id
    end
  end
end
