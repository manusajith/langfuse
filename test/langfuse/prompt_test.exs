defmodule Langfuse.PromptTest do
  use ExUnit.Case, async: true

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
end
