defmodule Langfuse.InstrumentationTest do
  use ExUnit.Case, async: false

  import Langfuse.Test.Helpers

  defmodule TestModule do
    use Langfuse.Instrumentation

    @observe name: "add-numbers"
    def add(a, b), do: a + b

    @observe as_type: :generation, model: "test-model"
    def generate(prompt), do: "Response to: #{prompt}"

    @observe capture_input: false
    def secret_op(password), do: String.length(password)

    @observe capture_output: false
    def side_effect(data) do
      send(self(), {:processed, data})
      :ok
    end

    @observe name: "risky-op"
    def risky(should_fail) do
      if should_fail, do: raise("Intentional error")
      :success
    end
  end

  describe "@observe attribute" do
    test "traces function calls as spans" do
      {result, events} =
        capture_events(fn ->
          TestModule.add(2, 3)
        end)

      assert result == 5
      assert length(events) >= 2

      span_create = Enum.find(events, &(&1.type == "span-create"))
      assert span_create
      assert span_create.body.name == "add-numbers"
    end

    test "traces generations with model info" do
      {result, events} =
        capture_events(fn ->
          TestModule.generate("Hello")
        end)

      assert result == "Response to: Hello"

      gen_create = Enum.find(events, &(&1.type == "generation-create"))
      assert gen_create
      assert gen_create.body.model == "test-model"
    end

    test "respects capture_input: false" do
      {result, events} =
        capture_events(fn ->
          TestModule.secret_op("my-secret-password")
        end)

      assert result == 18

      span_create = Enum.find(events, &(&1.type == "span-create"))
      assert span_create
      assert span_create.body[:input] == nil
    end

    test "respects capture_output: false" do
      {result, events} =
        capture_events(fn ->
          TestModule.side_effect("test-data")
        end)

      assert result == :ok
      assert_received {:processed, "test-data"}

      span_update = Enum.find(events, &(&1.type == "span-update"))
      assert span_update
      assert span_update.body[:output] == nil
    end

    test "captures errors with status message" do
      {_events_before, events} =
        capture_events(fn ->
          try do
            TestModule.risky(true)
          rescue
            _ -> :caught
          end
        end)

      span_update = Enum.find(events, &(&1.type == "span-update"))
      assert span_update
      assert span_update.body.level == "ERROR"
      assert span_update.body.statusMessage =~ "Intentional error"
    end

    test "successful operations don't set error level" do
      {result, events} =
        capture_events(fn ->
          TestModule.risky(false)
        end)

      assert result == :success

      span_update = Enum.find(events, &(&1.type == "span-update"))
      assert span_update
      refute Map.has_key?(span_update.body, :level)
    end
  end

  describe "with_trace/2 macro" do
    test "creates trace and span for block" do
      import Langfuse.Instrumentation

      {result, events} =
        capture_events(fn ->
          with_trace "test-block" do
            1 + 1
          end
        end)

      assert result == 2

      trace_create = Enum.find(events, &(&1.type == "trace-create"))
      assert trace_create
      assert trace_create.body.name == "test-block"

      span_create = Enum.find(events, &(&1.type == "span-create"))
      assert span_create
      assert span_create.body.name == "test-block"
    end

    test "with_trace/3 accepts options" do
      import Langfuse.Instrumentation

      {result, events} =
        capture_events(fn ->
          with_trace "user-action", user_id: "user-123", tags: ["test"] do
            :done
          end
        end)

      assert result == :done

      trace_create = Enum.find(events, &(&1.type == "trace-create"))
      assert trace_create
      assert trace_create.body.userId == "user-123"
      assert trace_create.body.tags == ["test"]
    end

    test "captures errors in with_trace block" do
      import Langfuse.Instrumentation

      {_result, events} =
        capture_events(fn ->
          try do
            with_trace "failing-block" do
              raise "Block failed"
            end
          rescue
            _ -> :caught
          end
        end)

      span_update = Enum.find(events, &(&1.type == "span-update"))
      assert span_update
      assert span_update.body.level == "ERROR"
      assert span_update.body.statusMessage =~ "Block failed"
    end
  end
end
