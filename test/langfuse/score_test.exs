defmodule Langfuse.ScoreTest do
  use ExUnit.Case, async: false

  alias Langfuse.{Score, Trace, Span, Generation}
  import Langfuse.Test.Helpers

  describe "create/2" do
    test "creates a numeric score on a trace" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      result = Score.create(trace, name: "quality", value: 0.85)

      assert result == :ok
    end

    test "creates a numeric score on a span" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      span = Span.new(trace, name: "test-span", id: "span-123")
      result = Score.create(span, name: "relevance", value: 0.9)

      assert result == :ok
    end

    test "creates a numeric score on a generation" do
      trace = Trace.new(name: "test-trace", id: "trace-123")
      gen = Generation.new(trace, name: "llm-call", id: "gen-123")
      result = Score.create(gen, name: "accuracy", value: 0.75)

      assert result == :ok
    end

    test "creates a categorical score" do
      trace = Trace.new(name: "test-trace")

      result =
        Score.create(trace,
          name: "sentiment",
          string_value: "positive",
          data_type: :categorical
        )

      assert result == :ok
    end

    test "creates a boolean score" do
      trace = Trace.new(name: "test-trace")

      result =
        Score.create(trace,
          name: "hallucination",
          value: false,
          data_type: :boolean
        )

      assert result == :ok
    end

    test "creates a boolean score with numeric value" do
      trace = Trace.new(name: "test-trace")

      result =
        Score.create(trace,
          name: "factual",
          value: 1,
          data_type: :boolean
        )

      assert result == :ok
    end

    test "creates a score with comment" do
      trace = Trace.new(name: "test-trace")

      result =
        Score.create(trace,
          name: "feedback",
          value: 5,
          comment: "Excellent response"
        )

      assert result == :ok
    end

    test "creates a score using trace_id string" do
      result = Score.create("trace-123", name: "quality", value: 0.8)

      assert result == :ok
    end

    test "infers numeric data type when value is provided" do
      trace = Trace.new(name: "test-trace")
      result = Score.create(trace, name: "score", value: 42.5)

      assert result == :ok
    end

    test "infers categorical data type when string_value is provided" do
      trace = Trace.new(name: "test-trace")
      result = Score.create(trace, name: "category", string_value: "good")

      assert result == :ok
    end

    test "infers boolean data type when value is boolean" do
      trace = Trace.new(name: "test-trace")
      result = Score.create(trace, name: "passed", value: true)

      assert result == :ok
    end

    test "raises when name is missing" do
      trace = Trace.new(name: "test-trace")

      assert_raise KeyError, fn ->
        Score.create(trace, value: 0.5)
      end
    end
  end

  describe "score_session/2" do
    test "creates a score for a session" do
      result = Score.score_session("session-123", name: "satisfaction", value: 4.5)

      assert result == :ok
    end

    test "creates a categorical session score" do
      result =
        Score.score_session("session-123",
          name: "outcome",
          string_value: "converted",
          data_type: :categorical
        )

      assert result == :ok
    end

    test "creates a boolean session score" do
      result =
        Score.score_session("session-123",
          name: "goal_achieved",
          value: true,
          data_type: :boolean
        )

      assert result == :ok
    end
  end

  describe "event body verification" do
    test "creates score with metadata" do
      {_result, events} =
        capture_events(fn ->
          trace = Trace.new(name: "test-trace", id: "trace-meta")

          Score.create(trace,
            name: "quality",
            value: 0.9,
            metadata: %{evaluator: "gpt-4", prompt_version: 3}
          )
        end)

      score_event = Enum.find(events, &(&1.type == "score-create"))
      assert score_event != nil
      assert score_event.body.metadata == %{evaluator: "gpt-4", prompt_version: 3}
    end

    test "session score includes sessionId in body" do
      {_result, events} =
        capture_events(fn ->
          Score.score_session("session-456", name: "satisfaction", value: 5)
        end)

      score_event = Enum.find(events, &(&1.type == "score-create"))
      assert score_event != nil
      assert score_event.body.sessionId == "session-456"
    end

    test "session score includes metadata" do
      {_result, events} =
        capture_events(fn ->
          Score.score_session("session-789",
            name: "completion",
            value: 1,
            data_type: :boolean,
            metadata: %{reason: "user_completed_goal"}
          )
        end)

      score_event = Enum.find(events, &(&1.type == "score-create"))
      assert score_event != nil
      assert score_event.body.sessionId == "session-789"
      assert score_event.body.metadata == %{reason: "user_completed_goal"}
    end

    test "score includes all expected fields" do
      {_result, events} =
        capture_events(fn ->
          trace = Trace.new(name: "test-trace", id: "trace-full")

          Score.create(trace,
            name: "accuracy",
            value: 0.95,
            comment: "Very accurate",
            id: "score-custom-id",
            config_id: "config-123",
            metadata: %{version: 1}
          )
        end)

      score_event = Enum.find(events, &(&1.type == "score-create"))
      assert score_event != nil

      body = score_event.body
      assert body.id == "score-custom-id"
      assert body.name == "accuracy"
      assert body.value == 0.95
      assert body.dataType == "NUMERIC"
      assert body.comment == "Very accurate"
      assert body.configId == "config-123"
      assert body.metadata == %{version: 1}
      assert body.traceId == "trace-full"
    end
  end
end
