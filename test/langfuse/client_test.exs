defmodule Langfuse.ClientTest do
  use ExUnit.Case, async: false

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

  describe "with bypass" do
    setup do
      bypass = Bypass.open()

      original_host = Application.get_env(:langfuse, :host)
      original_public_key = Application.get_env(:langfuse, :public_key)
      original_secret_key = Application.get_env(:langfuse, :secret_key)
      original_max_retries = Application.get_env(:langfuse, :max_retries)

      Application.put_env(:langfuse, :host, "http://localhost:#{bypass.port}")
      Application.put_env(:langfuse, :public_key, "pk-test")
      Application.put_env(:langfuse, :secret_key, "sk-test")
      Application.put_env(:langfuse, :max_retries, 0)

      Langfuse.Config.reload()

      on_exit(fn ->
        if original_host do
          Application.put_env(:langfuse, :host, original_host)
        else
          Application.delete_env(:langfuse, :host)
        end

        if original_public_key do
          Application.put_env(:langfuse, :public_key, original_public_key)
        else
          Application.delete_env(:langfuse, :public_key)
        end

        if original_secret_key do
          Application.put_env(:langfuse, :secret_key, original_secret_key)
        else
          Application.delete_env(:langfuse, :secret_key)
        end

        if original_max_retries do
          Application.put_env(:langfuse, :max_retries, original_max_retries)
        else
          Application.delete_env(:langfuse, :max_retries)
        end

        Langfuse.Config.reload()
      end)

      {:ok, bypass: bypass}
    end

    test "get_dataset/1 fetches dataset by name", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/datasets/my-dataset", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{name: "my-dataset", id: "ds-123"}))
      end)

      assert {:ok, dataset} = Client.get_dataset("my-dataset")
      assert dataset["name"] == "my-dataset"
    end

    test "create_dataset/1 creates a dataset", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/v2/datasets", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["name"] == "test-dataset"
        assert payload["description"] == "A test dataset"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{name: "test-dataset", id: "ds-456"}))
      end)

      assert {:ok, result} =
               Client.create_dataset(name: "test-dataset", description: "A test dataset")

      assert result["name"] == "test-dataset"
    end

    test "list_datasets/1 returns datasets", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/datasets", fn conn ->
        assert conn.query_string =~ "limit=10"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{name: "ds-1"}, %{name: "ds-2"}]}))
      end)

      assert {:ok, result} = Client.list_datasets(limit: 10)
      assert result["data"] |> length() == 2
    end

    test "create_dataset_item/1 creates an item", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/v2/dataset-items", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["datasetName"] == "test-ds"
        assert payload["input"] == %{"question" => "What is AI?"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "item-123"}))
      end)

      assert {:ok, result} =
               Client.create_dataset_item(
                 dataset_name: "test-ds",
                 input: %{question: "What is AI?"}
               )

      assert result["id"] == "item-123"
    end

    test "get_dataset_item/1 fetches item", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/dataset-items/item-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "item-123", input: %{}}))
      end)

      assert {:ok, item} = Client.get_dataset_item("item-123")
      assert item["id"] == "item-123"
    end

    test "update_dataset_item/2 updates item", %{bypass: bypass} do
      Bypass.expect_once(bypass, "PATCH", "/api/public/v2/dataset-items/item-123", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["input"] == %{"updated" => true}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "item-123", input: %{updated: true}}))
      end)

      assert {:ok, result} = Client.update_dataset_item("item-123", input: %{updated: true})
      assert result["id"] == "item-123"
    end

    test "create_dataset_run/1 creates a run", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/v2/dataset-runs", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["name"] == "eval-run-1"
        assert payload["datasetName"] == "test-ds"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "run-123", name: "eval-run-1"}))
      end)

      assert {:ok, result} =
               Client.create_dataset_run(name: "eval-run-1", dataset_name: "test-ds")

      assert result["name"] == "eval-run-1"
    end

    test "create_dataset_run_item/1 links trace to item", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/v2/dataset-run-items", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["runName"] == "eval-run-1"
        assert payload["datasetItemId"] == "item-123"
        assert payload["traceId"] == "trace-456"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "run-item-789"}))
      end)

      assert {:ok, result} =
               Client.create_dataset_run_item(
                 run_name: "eval-run-1",
                 dataset_item_id: "item-123",
                 trace_id: "trace-456"
               )

      assert result["id"] == "run-item-789"
    end

    test "list_score_configs/1 returns configs", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/score-configs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{name: "accuracy"}]}))
      end)

      assert {:ok, result} = Client.list_score_configs()
      assert result["data"] |> length() == 1
    end

    test "get_score_config/1 fetches config", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/score-configs/cfg-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "cfg-123", name: "accuracy"}))
      end)

      assert {:ok, config} = Client.get_score_config("cfg-123")
      assert config["name"] == "accuracy"
    end

    test "create_score_config/1 creates config", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/v2/score-configs", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["name"] == "quality"
        assert payload["dataType"] == "NUMERIC"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "cfg-456", name: "quality"}))
      end)

      assert {:ok, result} = Client.create_score_config(name: "quality", data_type: "NUMERIC")
      assert result["name"] == "quality"
    end

    test "get_trace/1 fetches trace", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/traces/trace-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "trace-123", name: "test-trace"}))
      end)

      assert {:ok, trace} = Client.get_trace("trace-123")
      assert trace["id"] == "trace-123"
    end

    test "list_traces/1 returns traces with filters", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/traces", fn conn ->
        assert conn.query_string =~ "userId=user-123"
        assert conn.query_string =~ "limit=5"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{id: "trace-1"}]}))
      end)

      assert {:ok, result} = Client.list_traces(user_id: "user-123", limit: 5)
      assert result["data"] |> length() == 1
    end

    test "get_session/1 fetches session", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/sessions/session-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "session-123"}))
      end)

      assert {:ok, session} = Client.get_session("session-123")
      assert session["id"] == "session-123"
    end

    test "list_sessions/1 returns sessions", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/sessions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{id: "sess-1"}, %{id: "sess-2"}]}))
      end)

      assert {:ok, result} = Client.list_sessions()
      assert result["data"] |> length() == 2
    end

    test "get_score/1 fetches score", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/scores/score-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "score-123", value: 0.95}))
      end)

      assert {:ok, score} = Client.get_score("score-123")
      assert score["value"] == 0.95
    end

    test "list_scores/1 returns scores", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/scores", fn conn ->
        assert conn.query_string =~ "traceId=trace-123"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{id: "score-1"}]}))
      end)

      assert {:ok, result} = Client.list_scores(trace_id: "trace-123")
      assert result["data"] |> length() == 1
    end

    test "delete_score/1 deletes score", %{bypass: bypass} do
      Bypass.expect_once(bypass, "DELETE", "/api/public/scores/score-123", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      assert :ok = Client.delete_score("score-123")
    end

    test "get_observation/1 fetches observation", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/observations/obs-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "obs-123", type: "GENERATION"}))
      end)

      assert {:ok, obs} = Client.get_observation("obs-123")
      assert obs["type"] == "GENERATION"
    end

    test "list_observations/1 returns observations", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/observations", fn conn ->
        assert conn.query_string =~ "traceId=trace-123"
        assert conn.query_string =~ "type=GENERATION"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{id: "obs-1"}]}))
      end)

      assert {:ok, result} = Client.list_observations(trace_id: "trace-123", type: "GENERATION")
      assert result["data"] |> length() == 1
    end

    test "delete_dataset/1 deletes dataset", %{bypass: bypass} do
      Bypass.expect_once(bypass, "DELETE", "/api/public/v2/datasets/my-dataset", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      assert :ok = Client.delete_dataset("my-dataset")
    end

    test "delete_dataset_item/1 deletes item", %{bypass: bypass} do
      Bypass.expect_once(bypass, "DELETE", "/api/public/v2/dataset-items/item-123", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      assert :ok = Client.delete_dataset_item("item-123")
    end

    test "get_model/1 fetches model", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/models/model-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "model-123", name: "gpt-4"}))
      end)

      assert {:ok, model} = Client.get_model("model-123")
      assert model["name"] == "gpt-4"
    end

    test "list_models/1 returns models", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/models", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{name: "gpt-4"}, %{name: "claude-3"}]}))
      end)

      assert {:ok, result} = Client.list_models()
      assert result["data"] |> length() == 2
    end

    test "raw get/2 makes GET request", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/custom", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{custom: true}))
      end)

      assert {:ok, result} = Client.get("/api/public/custom")
      assert result["custom"] == true
    end

    test "raw post/2 makes POST request", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/custom", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["data"] == "test"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{success: true}))
      end)

      assert {:ok, result} = Client.post("/api/public/custom", %{data: "test"})
      assert result["success"] == true
    end

    test "list_prompts/1 returns prompts", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{name: "prompt-1"}, %{name: "prompt-2"}]}))
      end)

      assert {:ok, result} = Client.list_prompts()
      assert length(result["data"]) == 2
    end

    test "create_prompt/1 creates a prompt", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/v2/prompts", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["name"] == "test-prompt"
        assert payload["prompt"] == "Hello {{name}}"
        assert payload["type"] == "text"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{name: "test-prompt", version: 1}))
      end)

      assert {:ok, result} = Client.create_prompt(name: "test-prompt", prompt: "Hello {{name}}")
      assert result["name"] == "test-prompt"
    end

    test "update_prompt_labels/3 updates labels", %{bypass: bypass} do
      Bypass.expect_once(
        bypass,
        "PATCH",
        "/api/public/v2/prompts/my-prompt/versions/2",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)

          assert payload["labels"] == ["production", "latest"]

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{name: "my-prompt", version: 2}))
        end
      )

      assert {:ok, result} =
               Client.update_prompt_labels("my-prompt", 2, labels: ["production", "latest"])

      assert result["version"] == 2
    end

    test "get_prompt/2 fetches prompt by name", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts/my-prompt", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            name: "my-prompt",
            version: 1,
            type: "text",
            prompt: "Hello {{name}}",
            labels: ["production"],
            tags: []
          })
        )
      end)

      assert {:ok, result} = Client.get_prompt("my-prompt")
      assert result["name"] == "my-prompt"
      assert result["prompt"] == "Hello {{name}}"
    end

    test "get_prompt/2 fetches specific version", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts/my-prompt", fn conn ->
        assert conn.query_string =~ "version=2"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{name: "my-prompt", version: 2}))
      end)

      assert {:ok, result} = Client.get_prompt("my-prompt", version: 2)
      assert result["version"] == 2
    end

    test "get_prompt/2 fetches by label", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts/my-prompt", fn conn ->
        assert conn.query_string =~ "label=staging"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{name: "my-prompt", version: 3, labels: ["staging"]})
        )
      end)

      assert {:ok, result} = Client.get_prompt("my-prompt", label: "staging")
      assert result["labels"] == ["staging"]
    end

    test "get_dataset_run/2 fetches run", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/datasets/my-dataset/runs/run-1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{name: "run-1", datasetName: "my-dataset"}))
      end)

      assert {:ok, result} = Client.get_dataset_run("my-dataset", "run-1")
      assert result["name"] == "run-1"
    end

    test "list_dataset_runs/2 returns runs", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/datasets/my-dataset/runs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{name: "run-1"}, %{name: "run-2"}]}))
      end)

      assert {:ok, result} = Client.list_dataset_runs("my-dataset")
      assert length(result["data"]) == 2
    end

    test "delete_dataset_run/2 deletes run", %{bypass: bypass} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/public/datasets/my-dataset/runs/run-1",
        fn conn ->
          Plug.Conn.resp(conn, 204, "")
        end
      )

      assert :ok = Client.delete_dataset_run("my-dataset", "run-1")
    end

    test "list_dataset_items/1 returns items", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/dataset-items", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{id: "item-1"}, %{id: "item-2"}]}))
      end)

      assert {:ok, result} = Client.list_dataset_items()
      assert length(result["data"]) == 2
    end

    test "list_dataset_run_items/1 returns run items", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/dataset-run-items", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: [%{id: "ri-1"}, %{id: "ri-2"}]}))
      end)

      assert {:ok, result} = Client.list_dataset_run_items()
      assert length(result["data"]) == 2
    end

    test "create_model/1 creates a custom model", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/models", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["modelName"] == "custom-model"
        assert payload["matchPattern"] == "custom-.*"
        assert payload["inputPrice"] == 0.001
        assert payload["outputPrice"] == 0.002

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "model-123", modelName: "custom-model"}))
      end)

      assert {:ok, result} =
               Client.create_model(
                 model_name: "custom-model",
                 match_pattern: "custom-.*",
                 input_price: 0.001,
                 output_price: 0.002
               )

      assert result["modelName"] == "custom-model"
    end

    test "delete_model/1 deletes model", %{bypass: bypass} do
      Bypass.expect_once(bypass, "DELETE", "/api/public/models/model-123", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      assert :ok = Client.delete_model("model-123")
    end
  end

  describe "prompt operations" do
    test "create_prompt/1 requires name and prompt" do
      assert_raise KeyError, fn ->
        Client.create_prompt(prompt: "Hello")
      end

      assert_raise KeyError, fn ->
        Client.create_prompt(name: "test")
      end
    end

    test "update_prompt_labels/3 requires labels" do
      assert_raise KeyError, fn ->
        Client.update_prompt_labels("test", 1, [])
      end
    end
  end

  describe "model operations" do
    test "create_model/1 requires model_name, match_pattern, and prices" do
      assert_raise KeyError, fn ->
        Client.create_model(match_pattern: ".*", input_price: 0.001, output_price: 0.002)
      end

      assert_raise KeyError, fn ->
        Client.create_model(model_name: "test", input_price: 0.001, output_price: 0.002)
      end

      assert_raise KeyError, fn ->
        Client.create_model(model_name: "test", match_pattern: ".*", output_price: 0.002)
      end

      assert_raise KeyError, fn ->
        Client.create_model(model_name: "test", match_pattern: ".*", input_price: 0.001)
      end
    end
  end

  describe "not configured" do
    setup do
      original_public_key = Application.get_env(:langfuse, :public_key)
      original_secret_key = Application.get_env(:langfuse, :secret_key)

      Application.delete_env(:langfuse, :public_key)
      Application.delete_env(:langfuse, :secret_key)

      Langfuse.Config.reload()

      on_exit(fn ->
        if original_public_key do
          Application.put_env(:langfuse, :public_key, original_public_key)
        end

        if original_secret_key do
          Application.put_env(:langfuse, :secret_key, original_secret_key)
        end

        Langfuse.Config.reload()
      end)

      :ok
    end

    test "returns error when credentials not configured" do
      assert {:error, :not_configured} = Client.get_dataset("test")
      assert {:error, :not_configured} = Client.list_traces()
      assert {:error, :not_configured} = Client.delete_score("test")
    end
  end
end
