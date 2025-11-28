defmodule Langfuse.ErrorTest do
  use ExUnit.Case, async: true

  alias Langfuse.Error.{ConfigError, APIError, ValidationError, PromptNotFoundError}

  describe "ConfigError" do
    test "message with key and custom message" do
      error = %ConfigError{key: :public_key, message: "must be a string"}
      msg = Exception.message(error)

      assert msg =~ "public_key"
      assert msg =~ "must be a string"
    end

    test "message with key only" do
      error = %ConfigError{key: :secret_key, message: nil}
      msg = Exception.message(error)

      assert msg =~ "secret_key"
      assert msg =~ "missing required key"
    end
  end

  describe "APIError" do
    test "message with path" do
      error = %APIError{status: 401, body: "Unauthorized", path: "/api/public/ingestion"}
      msg = Exception.message(error)

      assert msg =~ "401"
      assert msg =~ "Unauthorized"
      assert msg =~ "/api/public/ingestion"
    end

    test "message without path" do
      error = %APIError{status: 500, body: "Internal server error", path: nil}
      msg = Exception.message(error)

      assert msg =~ "500"
      assert msg =~ "Internal server error"
    end

    test "message with map body" do
      error = %APIError{status: 400, body: %{"error" => "Invalid request"}, path: "/test"}
      msg = Exception.message(error)

      assert msg =~ "400"
      assert msg =~ "Invalid request"
    end
  end

  describe "ValidationError" do
    test "message with field, message, and value" do
      error = %ValidationError{field: :name, message: "must be a string", value: 123}
      msg = Exception.message(error)

      assert msg =~ "name"
      assert msg =~ "must be a string"
      assert msg =~ "123"
    end

    test "message with field and message only (nil value)" do
      error = %ValidationError{field: :model, message: "is required", value: nil}
      msg = Exception.message(error)

      assert msg =~ "model"
      assert msg =~ "is required"
      refute msg =~ "got:"
    end

    test "message with string field" do
      error = %ValidationError{field: "user_id", message: "must be non-empty", value: ""}
      msg = Exception.message(error)

      assert msg =~ "user_id"
      assert msg =~ "must be non-empty"
      assert msg =~ "got:"
    end
  end

  describe "PromptNotFoundError" do
    test "message with name only" do
      error = %PromptNotFoundError{name: "my-prompt", version: nil, label: nil}
      msg = Exception.message(error)

      assert msg == "Prompt 'my-prompt' not found"
    end

    test "message with name and version" do
      error = %PromptNotFoundError{name: "my-prompt", version: 3, label: nil}
      msg = Exception.message(error)

      assert msg =~ "my-prompt"
      assert msg =~ "version 3"
      assert msg =~ "not found"
    end

    test "message with name and label" do
      error = %PromptNotFoundError{name: "my-prompt", version: nil, label: "production"}
      msg = Exception.message(error)

      assert msg =~ "my-prompt"
      assert msg =~ "label"
      assert msg =~ "production"
    end

    test "message with name, version, and label" do
      error = %PromptNotFoundError{name: "my-prompt", version: 2, label: "staging"}
      msg = Exception.message(error)

      assert msg =~ "my-prompt"
      assert msg =~ "staging"
      assert msg =~ "2"
    end
  end

  describe "exception behaviour" do
    test "ConfigError is an exception" do
      assert_raise ConfigError, fn ->
        raise %ConfigError{key: :test, message: "test error"}
      end
    end

    test "APIError is an exception" do
      assert_raise APIError, fn ->
        raise %APIError{status: 500, body: "error", path: "/test"}
      end
    end

    test "ValidationError is an exception" do
      assert_raise ValidationError, fn ->
        raise %ValidationError{field: :test, message: "invalid"}
      end
    end

    test "PromptNotFoundError is an exception" do
      assert_raise PromptNotFoundError, fn ->
        raise %PromptNotFoundError{name: "test"}
      end
    end
  end
end
