defmodule Langfuse.HTTPTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "auth_check/0 with mock" do
    test "mock returns true when configured to succeed" do
      expect(Langfuse.HTTPMock, :auth_check, fn ->
        true
      end)

      assert Langfuse.HTTPMock.auth_check() == true
    end

    test "mock returns false when configured to fail" do
      expect(Langfuse.HTTPMock, :auth_check, fn ->
        false
      end)

      assert Langfuse.HTTPMock.auth_check() == false
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

    test "auth_check/0 returns true on successful health check", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/health", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{status: "ok"}))
      end)

      assert Langfuse.HTTP.auth_check() == true
    end

    test "auth_check/0 returns false on failed health check", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/health", fn conn ->
        Plug.Conn.resp(conn, 401, Jason.encode!(%{error: "unauthorized"}))
      end)

      assert Langfuse.HTTP.auth_check() == false
    end

    test "auth_check/0 returns false on connection error", %{bypass: bypass} do
      Bypass.down(bypass)
      assert Langfuse.HTTP.auth_check() == false
    end

    test "ingest/1 sends batch of events", %{bypass: bypass} do
      events = [
        %{id: "evt-1", type: "trace-create", body: %{id: "trace-1", name: "test"}},
        %{id: "evt-2", type: "span-create", body: %{id: "span-1", traceId: "trace-1"}}
      ]

      Bypass.expect_once(bypass, "POST", "/api/public/ingestion", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert length(payload["batch"]) == 2
        assert payload["metadata"]["sdk_name"] == "langfuse-elixir"
        assert payload["metadata"]["public_key"] == "pk-test"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            successes: [%{id: "evt-1", status: 201}, %{id: "evt-2", status: 201}],
            errors: []
          })
        )
      end)

      assert {:ok, response} = Langfuse.HTTP.ingest(events)
      assert response["successes"] |> length() == 2
      assert response["errors"] == []
    end

    test "ingest/1 handles partial failure", %{bypass: bypass} do
      events = [
        %{id: "evt-1", type: "trace-create", body: %{id: "trace-1"}},
        %{id: "evt-2", type: "invalid", body: %{}}
      ]

      Bypass.expect_once(bypass, "POST", "/api/public/ingestion", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            successes: [%{id: "evt-1", status: 201}],
            errors: [%{id: "evt-2", status: 400, message: "invalid type"}]
          })
        )
      end)

      assert {:ok, response} = Langfuse.HTTP.ingest(events)
      assert length(response["successes"]) == 1
      assert length(response["errors"]) == 1
    end

    test "ingest/1 handles server error", %{bypass: bypass} do
      Bypass.stub(bypass, "POST", "/api/public/ingestion", fn conn ->
        Plug.Conn.resp(conn, 500, Jason.encode!(%{error: "internal error"}))
      end)

      assert {:error, %{status: 500}} = Langfuse.HTTP.ingest([%{id: "evt-1"}])
    end

    test "get_prompt/2 fetches prompt by name", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts/test-prompt", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            name: "test-prompt",
            type: "text",
            prompt: "Hello {{name}}",
            version: 1,
            labels: ["production"],
            config: %{}
          })
        )
      end)

      assert {:ok, prompt} = Langfuse.HTTP.get_prompt("test-prompt")
      assert prompt["name"] == "test-prompt"
      assert prompt["prompt"] == "Hello {{name}}"
    end

    test "get_prompt/2 with version option", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts/test-prompt", fn conn ->
        assert conn.query_string =~ "version=3"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{name: "test-prompt", version: 3, prompt: "v3 content"})
        )
      end)

      assert {:ok, prompt} = Langfuse.HTTP.get_prompt("test-prompt", version: 3)
      assert prompt["version"] == 3
    end

    test "get_prompt/2 with label option", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts/test-prompt", fn conn ->
        assert conn.query_string =~ "label=staging"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{name: "test-prompt", labels: ["staging"], prompt: "staging content"})
        )
      end)

      assert {:ok, prompt} = Langfuse.HTTP.get_prompt("test-prompt", label: "staging")
      assert "staging" in prompt["labels"]
    end

    test "get_prompt/2 with resolve option", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts/test-prompt", fn conn ->
        assert conn.query_string =~ "resolve=false"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{name: "test-prompt", version: 1, prompt: "raw {{dep}}"})
        )
      end)

      assert {:ok, prompt} = Langfuse.HTTP.get_prompt("test-prompt", resolve: false)
      assert prompt["prompt"] == "raw {{dep}}"
    end

    test "get_prompt/2 handles not found", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts/nonexistent", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(%{error: "Prompt not found"}))
      end)

      assert {:error, %{status: 404}} = Langfuse.HTTP.get_prompt("nonexistent")
    end

    test "get/2 makes GET request with params", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/traces", fn conn ->
        assert conn.query_string =~ "limit=10"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: []}))
      end)

      assert {:ok, _} = Langfuse.HTTP.get("/api/public/traces", limit: 10)
    end

    test "post/2 makes POST request with body", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/public/test", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["foo"] == "bar"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{success: true}))
      end)

      assert {:ok, %{"success" => true}} = Langfuse.HTTP.post("/api/public/test", %{foo: "bar"})
    end

    test "requests include basic auth header", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/health", fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        assert [auth] = auth_header
        assert String.starts_with?(auth, "Basic ")

        decoded = auth |> String.replace("Basic ", "") |> Base.decode64!()
        assert decoded == "pk-test:sk-test"

        Plug.Conn.resp(conn, 200, Jason.encode!(%{status: "ok"}))
      end)

      Langfuse.HTTP.auth_check()
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

    test "get/2 returns error when not configured" do
      assert {:error, :not_configured} = Langfuse.HTTP.get("/api/public/health")
    end

    test "post/2 returns error when not configured" do
      assert {:error, :not_configured} = Langfuse.HTTP.post("/api/public/test", %{})
    end
  end
end
