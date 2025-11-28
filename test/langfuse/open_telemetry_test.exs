defmodule Langfuse.OpenTelemetryTest do
  use ExUnit.Case, async: true

  alias Langfuse.OpenTelemetry

  describe "extract_ids/1" do
    test "extracts trace and span IDs from valid span context tuple" do
      trace_id = 0x0AF7651916CD43DD8448EB211C80319C
      span_id = 0xB7AD6B7169203331
      span_ctx = {trace_id, span_id, 1, [], true}

      {extracted_trace, extracted_span} = OpenTelemetry.extract_ids(span_ctx)

      assert extracted_trace == "0af7651916cd43dd8448eb211c80319c"
      assert extracted_span == "b7ad6b7169203331"
    end

    test "pads short IDs with leading zeros" do
      trace_id = 0x123
      span_id = 0x456
      span_ctx = {trace_id, span_id, 0, [], true}

      {extracted_trace, extracted_span} = OpenTelemetry.extract_ids(span_ctx)

      assert String.length(extracted_trace) == 32
      assert String.length(extracted_span) == 16
      assert extracted_trace == "00000000000000000000000000000123"
      assert extracted_span == "0000000000000456"
    end

    test "returns nil for invalid span context" do
      assert OpenTelemetry.extract_ids(nil) == nil
      assert OpenTelemetry.extract_ids(:invalid) == nil
      assert OpenTelemetry.extract_ids({}) == nil
    end
  end

  describe "map_attributes/1" do
    test "maps gen_ai model attributes" do
      attrs = %{"gen_ai.request.model" => "gpt-4"}
      assert OpenTelemetry.map_attributes(attrs) == %{model: "gpt-4"}

      attrs = %{"gen_ai.response.model" => "gpt-4-turbo"}
      assert OpenTelemetry.map_attributes(attrs) == %{model: "gpt-4-turbo"}
    end

    test "maps gen_ai prompt and completion" do
      attrs = %{
        "gen_ai.prompt" => "Hello",
        "gen_ai.completion" => "Hi there!"
      }

      result = OpenTelemetry.map_attributes(attrs)

      assert result.input == "Hello"
      assert result.output == "Hi there!"
    end

    test "maps gen_ai usage tokens to nested usage map" do
      attrs = %{
        "gen_ai.usage.input_tokens" => 100,
        "gen_ai.usage.output_tokens" => 50,
        "gen_ai.usage.total_tokens" => 150
      }

      result = OpenTelemetry.map_attributes(attrs)

      assert result.usage.input == 100
      assert result.usage.output == 50
      assert result.usage.total == 150
    end

    test "maps langfuse-specific attributes" do
      attrs = %{
        "langfuse.trace.user_id" => "user-123",
        "langfuse.trace.session_id" => "session-456",
        "langfuse.observation.level" => "WARNING"
      }

      result = OpenTelemetry.map_attributes(attrs)

      assert result.user_id == "user-123"
      assert result.session_id == "session-456"
      assert result.level == :warning
    end

    test "ignores unknown attributes" do
      attrs = %{
        "gen_ai.request.model" => "gpt-4",
        "custom.attribute" => "value",
        "another.unknown" => 123
      }

      result = OpenTelemetry.map_attributes(attrs)

      assert result == %{model: "gpt-4"}
    end

    test "handles empty attributes" do
      assert OpenTelemetry.map_attributes(%{}) == %{}
    end
  end

  describe "exporter_config/1" do
    test "returns valid OTEL exporter configuration" do
      config = OpenTelemetry.exporter_config(
        host: "https://example.langfuse.com",
        public_key: "pk-test",
        secret_key: "sk-test"
      )

      assert config[:otlp_protocol] == :http_protobuf
      assert config[:otlp_endpoint] == "https://example.langfuse.com/api/public/otel/v1/traces"

      [{header_key, header_value}] = config[:otlp_headers]
      assert header_key == "Authorization"
      assert String.starts_with?(header_value, "Basic ")

      decoded = header_value |> String.replace("Basic ", "") |> Base.decode64!()
      assert decoded == "pk-test:sk-test"
    end

    test "uses default cloud host when not specified" do
      config = OpenTelemetry.exporter_config(
        public_key: "pk",
        secret_key: "sk"
      )

      assert config[:otlp_endpoint] =~ "cloud.langfuse.com"
    end
  end

  describe "trace_from_context/2" do
    test "creates trace with OTEL trace ID" do
      trace_id = 0x0AF7651916CD43DD8448EB211C80319C
      span_id = 0xB7AD6B7169203331
      span_ctx = {trace_id, span_id, 1, [], true}

      {:ok, trace} = OpenTelemetry.trace_from_context(span_ctx, name: "test-trace")

      assert trace.id == "0af7651916cd43dd8448eb211c80319c"
      assert trace.name == "test-trace"
    end

    test "returns error for invalid context" do
      assert {:error, :invalid_context} = OpenTelemetry.trace_from_context(nil, name: "test")
      assert {:error, :invalid_context} = OpenTelemetry.trace_from_context(:invalid, name: "test")
    end

    test "passes through additional options" do
      trace_id = 0x123
      span_id = 0x456
      span_ctx = {trace_id, span_id, 0, [], true}

      {:ok, trace} = OpenTelemetry.trace_from_context(span_ctx,
        name: "test",
        user_id: "user-123",
        session_id: "session-456"
      )

      assert trace.user_id == "user-123"
      assert trace.session_id == "session-456"
    end
  end
end
