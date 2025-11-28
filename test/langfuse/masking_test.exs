defmodule Langfuse.MaskingTest do
  use ExUnit.Case, async: false

  alias Langfuse.Masking

  setup do
    original_config = Application.get_env(:langfuse, :masking)
    on_exit(fn -> Application.put_env(:langfuse, :masking, original_config) end)
    :ok
  end

  describe "mask/1" do
    test "returns value unchanged when masking is disabled" do
      Application.put_env(:langfuse, :masking, enabled: false)

      assert Masking.mask("sk-test1234567890abcdefghij") ==
               "sk-test1234567890abcdefghij"
    end

    test "masks API keys with default patterns when enabled" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result = Masking.mask("My API key is sk-test1234567890abcdefghij")
      assert result == "My API key is [MASKED_API_KEY]"
    end

    test "masks public keys with default patterns" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result = Masking.mask("Public key: pk-test1234567890abcdefghij")
      assert result == "Public key: [MASKED_PUBLIC_KEY]"
    end

    test "masks emails with default patterns" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result = Masking.mask("Contact: user@example.com for help")
      assert result == "Contact: [MASKED_EMAIL] for help"
    end

    test "masks sensitive keys in maps" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result = Masking.mask(%{username: "alice", password: "secret123"})
      assert result == %{username: "alice", password: "[MASKED]"}
    end

    test "masks nested maps" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result =
        Masking.mask(%{
          user: %{name: "alice", api_key: "secret"},
          data: "test"
        })

      assert result == %{
               user: %{name: "alice", api_key: "[MASKED]"},
               data: "test"
             }
    end

    test "masks lists of values" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result = Masking.mask(["sk-test1234567890abcdefghij", "normal text"])
      assert result == ["[MASKED_API_KEY]", "normal text"]
    end

    test "uses custom patterns when configured" do
      Application.put_env(:langfuse, :masking,
        enabled: true,
        patterns: [{~r/secret-\d+/, "[CUSTOM_MASKED]"}]
      )

      result = Masking.mask("Value is secret-12345")
      assert result == "Value is [CUSTOM_MASKED]"
    end

    test "uses custom mask keys when configured" do
      Application.put_env(:langfuse, :masking,
        enabled: true,
        mask_keys: [:custom_secret]
      )

      result = Masking.mask(%{custom_secret: "value", other: "visible"})
      assert result == %{custom_secret: "[MASKED]", other: "visible"}
    end

    test "uses custom mask function when configured" do
      Application.put_env(:langfuse, :masking,
        enabled: true,
        mask_fn: fn value -> "CUSTOM:#{inspect(value)}" end
      )

      result = Masking.mask("test")
      assert result == "CUSTOM:\"test\""
    end

    test "returns non-string/map values unchanged" do
      Application.put_env(:langfuse, :masking, enabled: true)

      assert Masking.mask(123) == 123
      assert Masking.mask(nil) == nil
      assert Masking.mask(true) == true
    end
  end

  describe "mask_string/1" do
    test "masks patterns in strings" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result = Masking.mask_string("API: sk-abcdefghijklmnopqrstuvwxyz")
      assert result == "API: [MASKED_API_KEY]"
    end

    test "returns non-strings unchanged" do
      assert Masking.mask_string(123) == 123
    end
  end

  describe "mask_map/1" do
    test "masks sensitive keys" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result = Masking.mask_map(%{password: "secret", name: "test"})
      assert result == %{password: "[MASKED]", name: "test"}
    end

    test "handles string keys" do
      Application.put_env(:langfuse, :masking, enabled: true)

      result = Masking.mask_map(%{"password" => "secret", "name" => "test"})
      assert result == %{"password" => "[MASKED]", "name" => "test"}
    end

    test "returns non-maps unchanged" do
      assert Masking.mask_map("string") == "string"
    end
  end

  describe "enabled?/0" do
    test "returns false when not configured" do
      Application.delete_env(:langfuse, :masking)
      refute Masking.enabled?()
    end

    test "returns false when explicitly disabled" do
      Application.put_env(:langfuse, :masking, enabled: false)
      refute Masking.enabled?()
    end

    test "returns true when enabled" do
      Application.put_env(:langfuse, :masking, enabled: true)
      assert Masking.enabled?()
    end
  end
end
