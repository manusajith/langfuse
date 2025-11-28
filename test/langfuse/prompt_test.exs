defmodule Langfuse.PromptTest do
  use ExUnit.Case, async: false

  alias Langfuse.Prompt

  describe "compile/2 with text prompts" do
    test "compiles a text prompt with variables" do
      prompt = %Prompt{
        name: "greeting",
        version: 1,
        type: :text,
        prompt: "Hello {{name}}, welcome to {{place}}!",
        config: nil,
        labels: [],
        tags: []
      }

      result = Prompt.compile(prompt, %{name: "Alice", place: "Wonderland"})

      assert result == "Hello Alice, welcome to Wonderland!"
    end

    test "handles missing variables" do
      prompt = %Prompt{
        name: "test",
        version: 1,
        type: :text,
        prompt: "Hello {{name}}, your balance is {{balance}}",
        config: nil,
        labels: [],
        tags: []
      }

      result = Prompt.compile(prompt, %{name: "Bob"})

      assert result == "Hello Bob, your balance is {{balance}}"
    end

    test "handles empty variables map" do
      prompt = %Prompt{
        name: "test",
        version: 1,
        type: :text,
        prompt: "Static text",
        config: nil,
        labels: [],
        tags: []
      }

      result = Prompt.compile(prompt, %{})

      assert result == "Static text"
    end

    test "handles numeric values" do
      prompt = %Prompt{
        name: "test",
        version: 1,
        type: :text,
        prompt: "You have {{count}} items worth ${{total}}",
        config: nil,
        labels: [],
        tags: []
      }

      result = Prompt.compile(prompt, %{count: 5, total: 99.99})

      assert result == "You have 5 items worth $99.99"
    end

    test "handles string keys in variables map" do
      prompt = %Prompt{
        name: "test",
        version: 1,
        type: :text,
        prompt: "Hello {{name}}!",
        config: nil,
        labels: [],
        tags: []
      }

      result = Prompt.compile(prompt, %{"name" => "Charlie"})

      assert result == "Hello Charlie!"
    end
  end

  describe "compile/2 with chat prompts" do
    test "compiles a chat prompt with variables" do
      prompt = %Prompt{
        name: "chat-assistant",
        version: 1,
        type: :chat,
        prompt: [
          %{"role" => "system", "content" => "You are helping {{user_name}}"},
          %{"role" => "user", "content" => "Tell me about {{topic}}"}
        ],
        config: nil,
        labels: [],
        tags: []
      }

      result = Prompt.compile(prompt, %{user_name: "Alice", topic: "weather"})

      assert result == [
               %{"role" => "system", "content" => "You are helping Alice"},
               %{"role" => "user", "content" => "Tell me about weather"}
             ]
    end

    test "preserves messages without variables" do
      prompt = %Prompt{
        name: "test",
        version: 1,
        type: :chat,
        prompt: [
          %{"role" => "system", "content" => "You are a helpful assistant"},
          %{"role" => "user", "content" => "Hello {{name}}"}
        ],
        config: nil,
        labels: [],
        tags: []
      }

      result = Prompt.compile(prompt, %{name: "Bob"})

      assert result == [
               %{"role" => "system", "content" => "You are a helpful assistant"},
               %{"role" => "user", "content" => "Hello Bob"}
             ]
    end

    test "handles messages without content field" do
      prompt = %Prompt{
        name: "test",
        version: 1,
        type: :chat,
        prompt: [
          %{"role" => "system"},
          %{"role" => "user", "content" => "Hello {{name}}"}
        ],
        config: nil,
        labels: [],
        tags: []
      }

      result = Prompt.compile(prompt, %{name: "Test"})

      assert result == [
               %{"role" => "system", "content" => ""},
               %{"role" => "user", "content" => "Hello Test"}
             ]
    end
  end

  describe "link_meta/1" do
    test "returns metadata for linking to generations" do
      prompt = %Prompt{
        name: "my-prompt",
        version: 3,
        type: :text,
        prompt: "template",
        config: nil,
        labels: [],
        tags: []
      }

      meta = Prompt.link_meta(prompt)

      assert meta == %{prompt_name: "my-prompt", prompt_version: 3}
    end
  end

  describe "invalidate/2" do
    test "returns :ok for non-existent cache" do
      assert Prompt.invalidate("non-existent") == :ok
    end

    test "returns :ok with version option" do
      assert Prompt.invalidate("my-prompt", version: 2) == :ok
    end

    test "returns :ok with label option" do
      assert Prompt.invalidate("my-prompt", label: "production") == :ok
    end

    test "invalidates cached prompt" do
      try do
        :ets.new(:langfuse_prompt_cache, [:set, :public, :named_table])
      rescue
        ArgumentError -> :ok
      end

      prompt = %Prompt{name: "cached", version: 1, type: :text, prompt: "test", labels: [], tags: []}
      key = {"cached", nil, nil}
      expires_at = System.monotonic_time(:millisecond) + 60_000
      :ets.insert(:langfuse_prompt_cache, {key, prompt, expires_at})

      assert :ets.lookup(:langfuse_prompt_cache, key) != []

      Prompt.invalidate("cached")

      assert :ets.lookup(:langfuse_prompt_cache, key) == []
    end
  end

  describe "invalidate_all/0" do
    test "returns :ok even when cache is empty" do
      assert Prompt.invalidate_all() == :ok
    end

    test "clears all cached prompts" do
      try do
        :ets.new(:langfuse_prompt_cache, [:set, :public, :named_table])
      rescue
        ArgumentError -> :ok
      end

      prompt = %Prompt{name: "test", version: 1, type: :text, prompt: "test", labels: [], tags: []}
      expires_at = System.monotonic_time(:millisecond) + 60_000
      :ets.insert(:langfuse_prompt_cache, {{"test", nil, nil}, prompt, expires_at})
      :ets.insert(:langfuse_prompt_cache, {{"test", 2, nil}, prompt, expires_at})

      Prompt.invalidate_all()

      assert :ets.tab2list(:langfuse_prompt_cache) == []
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

      Prompt.invalidate_all()

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
        Prompt.invalidate_all()
      end)

      {:ok, bypass: bypass}
    end

    test "fetch/2 fetches prompt from API", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        assert conn.query_string =~ "name=test-prompt"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            name: "test-prompt",
            version: 1,
            type: "text",
            prompt: "Hello {{name}}!",
            config: %{temperature: 0.7},
            labels: ["production"],
            tags: ["greeting"]
          })
        )
      end)

      assert {:ok, prompt} = Prompt.fetch("test-prompt")
      assert prompt.name == "test-prompt"
      assert prompt.version == 1
      assert prompt.type == :text
      assert prompt.prompt == "Hello {{name}}!"
      assert prompt.config == %{"temperature" => 0.7}
      assert prompt.labels == ["production"]
      assert prompt.tags == ["greeting"]
    end

    test "fetch/2 with version option", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        assert conn.query_string =~ "name=test-prompt"
        assert conn.query_string =~ "version=3"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{name: "test-prompt", version: 3, type: "text", prompt: "v3"})
        )
      end)

      assert {:ok, prompt} = Prompt.fetch("test-prompt", version: 3)
      assert prompt.version == 3
    end

    test "fetch/2 with label option", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        assert conn.query_string =~ "name=test-prompt"
        assert conn.query_string =~ "label=staging"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{name: "test-prompt", version: 2, type: "text", prompt: "staging"})
        )
      end)

      assert {:ok, prompt} = Prompt.fetch("test-prompt", label: "staging")
      assert prompt.version == 2
    end

    test "fetch/2 returns not_found for 404", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(%{error: "Prompt not found"}))
      end)

      assert {:error, :not_found} = Prompt.fetch("nonexistent")
    end

    test "fetch/2 parses chat type prompts", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            name: "chat-prompt",
            version: 1,
            type: "chat",
            prompt: [%{"role" => "system", "content" => "You are helpful"}]
          })
        )
      end)

      assert {:ok, prompt} = Prompt.fetch("chat-prompt")
      assert prompt.type == :chat
      assert is_list(prompt.prompt)
    end

    test "get/2 caches prompts", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{name: "cached-prompt", version: 1, type: "text", prompt: "cached"})
        )
      end)

      assert {:ok, prompt1} = Prompt.get("cached-prompt")
      assert {:ok, prompt2} = Prompt.get("cached-prompt")

      assert prompt1.name == prompt2.name
    end

    test "get/2 with fallback prompt struct on error", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        Plug.Conn.resp(conn, 500, Jason.encode!(%{error: "Server error"}))
      end)

      fallback = %Prompt{
        name: "fallback",
        version: 0,
        type: :text,
        prompt: "Fallback template",
        config: nil,
        labels: [],
        tags: []
      }

      assert {:ok, prompt} = Prompt.get("failing-prompt", fallback: fallback)
      assert prompt.name == "failing-prompt"
      assert prompt.prompt == "Fallback template"
    end

    test "get/2 with fallback template string on error", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        Plug.Conn.resp(conn, 500, Jason.encode!(%{error: "Server error"}))
      end)

      assert {:ok, prompt} = Prompt.get("failing-prompt", fallback: "Default {{name}}")
      assert prompt.name == "failing-prompt"
      assert prompt.version == 0
      assert prompt.type == :text
      assert prompt.prompt == "Default {{name}}"
    end

    test "get/2 with fallback chat messages on error", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        Plug.Conn.resp(conn, 500, Jason.encode!(%{error: "Server error"}))
      end)

      messages = [%{"role" => "system", "content" => "Default assistant"}]

      assert {:ok, prompt} = Prompt.get("failing-prompt", fallback: messages)
      assert prompt.type == :chat
      assert prompt.prompt == messages
    end

    test "get/2 returns error without fallback", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        Plug.Conn.resp(conn, 404, Jason.encode!(%{error: "Not found"}))
      end)

      assert {:error, :not_found} = Prompt.get("missing-prompt")
    end

    test "get/2 respects cache_ttl option", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/api/public/v2/prompts", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{name: "ttl-test", version: 1, type: "text", prompt: "test"})
        )
      end)

      assert {:ok, _} = Prompt.get("ttl-test", cache_ttl: 1)

      Process.sleep(10)

      assert {:ok, _} = Prompt.get("ttl-test", cache_ttl: 1)
    end
  end
end
