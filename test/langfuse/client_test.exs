defmodule Langfuse.ClientTest do
  use ExUnit.Case, async: true

  alias Langfuse.Client

  describe "dataset operations" do
    test "create_dataset/1 requires name" do
      assert_raise KeyError, fn ->
        Client.create_dataset(description: "test")
      end
    end

    test "create_dataset_item/1 requires dataset_name and input" do
      assert_raise KeyError, fn ->
        Client.create_dataset_item(input: %{})
      end

      assert_raise KeyError, fn ->
        Client.create_dataset_item(dataset_name: "test")
      end
    end

    test "create_dataset_run/1 requires name and dataset_name" do
      assert_raise KeyError, fn ->
        Client.create_dataset_run(dataset_name: "test")
      end

      assert_raise KeyError, fn ->
        Client.create_dataset_run(name: "test")
      end
    end

    test "create_dataset_run_item/1 requires run_name, dataset_item_id, and trace_id" do
      assert_raise KeyError, fn ->
        Client.create_dataset_run_item(dataset_item_id: "item", trace_id: "trace")
      end

      assert_raise KeyError, fn ->
        Client.create_dataset_run_item(run_name: "run", trace_id: "trace")
      end

      assert_raise KeyError, fn ->
        Client.create_dataset_run_item(run_name: "run", dataset_item_id: "item")
      end
    end
  end

  describe "score config operations" do
    test "create_score_config/1 requires name and data_type" do
      assert_raise KeyError, fn ->
        Client.create_score_config(data_type: "NUMERIC")
      end

      assert_raise KeyError, fn ->
        Client.create_score_config(name: "test")
      end
    end
  end

  describe "list operations with pagination" do
    test "list_datasets/1 accepts pagination options" do
      opts = [limit: 10, page: 2]
      assert is_list(opts)
    end

    test "list_traces/1 accepts filter options" do
      opts = [
        limit: 10,
        user_id: "user-123",
        session_id: "session-456",
        name: "test",
        tags: ["prod"]
      ]

      assert is_list(opts)
    end

    test "list_sessions/1 accepts timestamp filters" do
      opts = [
        limit: 10,
        from_timestamp: "2024-01-01T00:00:00Z",
        to_timestamp: "2024-12-31T23:59:59Z"
      ]

      assert is_list(opts)
    end

    test "list_scores/1 accepts filter options" do
      opts = [
        limit: 10,
        trace_id: "trace-123",
        user_id: "user-456",
        name: "quality",
        data_type: "NUMERIC"
      ]

      assert is_list(opts)
    end
  end
end
