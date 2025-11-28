defmodule Langfuse.ScoreTest do
  use ExUnit.Case, async: true

  alias Langfuse.{Score, Trace, Span, Generation}

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
end
