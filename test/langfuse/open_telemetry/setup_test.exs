defmodule Langfuse.OpenTelemetry.SetupTest do
  use ExUnit.Case, async: false

  alias Langfuse.Config
  alias Langfuse.OpenTelemetry.Setup

  setup do
    original_cacertfile = Application.get_env(:langfuse, :cacertfile)

    original_exporter_config = %{
      otlp_protocol: Application.get_env(:opentelemetry_exporter, :otlp_protocol),
      otlp_endpoint: Application.get_env(:opentelemetry_exporter, :otlp_endpoint),
      otlp_headers: Application.get_env(:opentelemetry_exporter, :otlp_headers),
      ssl_options: Application.get_env(:opentelemetry_exporter, :ssl_options)
    }

    on_exit(fn ->
      if original_cacertfile do
        Application.put_env(:langfuse, :cacertfile, original_cacertfile)
      else
        Application.delete_env(:langfuse, :cacertfile)
      end

      Config.reload()

      Enum.each(original_exporter_config, fn {key, value} ->
        if value do
          Application.put_env(:opentelemetry_exporter, key, value)
        else
          Application.delete_env(:opentelemetry_exporter, key)
        end
      end)
    end)

    :ok
  end

  describe "exporter_config/1" do
    test "returns OTLP configuration with defaults" do
      config = Setup.exporter_config()

      assert config[:otlp_protocol] == :http_protobuf
      assert config[:otlp_endpoint] =~ "/api/public/otel/v1/traces"
      assert [{"Authorization", auth}] = config[:otlp_headers]
      assert String.starts_with?(auth, "Basic ")
    end

    test "uses custom host" do
      config = Setup.exporter_config(host: "https://custom.langfuse.com")

      assert config[:otlp_endpoint] == "https://custom.langfuse.com/api/public/otel/v1/traces"
    end

    test "uses custom credentials" do
      config =
        Setup.exporter_config(
          public_key: "pk-test",
          secret_key: "sk-test"
        )

      expected_auth = "Basic " <> Base.encode64("pk-test:sk-test")
      assert [{"Authorization", ^expected_auth}] = config[:otlp_headers]
    end

    test "uses configured cacertfile as exporter ssl_options" do
      Application.put_env(:langfuse, :cacertfile, "/etc/ssl/langfuse-root-ca.pem")
      Config.reload()

      config = Setup.exporter_config()

      assert config[:ssl_options] == [cacertfile: "/etc/ssl/langfuse-root-ca.pem"]
    end

    test "allows overriding cacertfile explicitly" do
      config = Setup.exporter_config(cacertfile: "/tmp/custom-root-ca.pem")

      assert config[:ssl_options] == [cacertfile: "/tmp/custom-root-ca.pem"]
    end
  end

  describe "configure_exporter/1" do
    test "sets application env for opentelemetry_exporter" do
      Setup.configure_exporter(
        host: "https://test.langfuse.com",
        public_key: "pk-test",
        secret_key: "sk-test"
      )

      assert Application.get_env(:opentelemetry_exporter, :otlp_protocol) == :http_protobuf

      assert Application.get_env(:opentelemetry_exporter, :otlp_endpoint) ==
               "https://test.langfuse.com/api/public/otel/v1/traces"

      headers = Application.get_env(:opentelemetry_exporter, :otlp_headers)
      assert [{"Authorization", _}] = headers
    end

    test "sets ssl_options when cacertfile is configured" do
      Setup.configure_exporter(
        host: "https://test.langfuse.com",
        public_key: "pk-test",
        secret_key: "sk-test",
        cacertfile: "/etc/ssl/langfuse-root-ca.pem"
      )

      assert Application.get_env(:opentelemetry_exporter, :ssl_options) == [
               cacertfile: "/etc/ssl/langfuse-root-ca.pem"
             ]
    end

    test "clears stale ssl_options when no cacertfile is configured" do
      Application.put_env(:opentelemetry_exporter, :ssl_options, cacertfile: "/tmp/stale.pem")

      Setup.configure_exporter(
        host: "https://test.langfuse.com",
        public_key: "pk-test",
        secret_key: "sk-test"
      )

      assert Application.get_env(:opentelemetry_exporter, :ssl_options) == nil
    end
  end

  describe "sdk_config/1" do
    test "returns SDK configuration" do
      config = Setup.sdk_config()

      assert config[:span_processor] == :batch
      assert config[:traces_exporter] == :otlp
      assert config[:resource][:service][:name]
    end

    test "allows custom service name" do
      config = Setup.sdk_config(service_name: "my-service")

      assert config[:resource][:service][:name] == "my-service"
    end
  end

  describe "status/0" do
    test "returns status info" do
      assert {:ok, info} = Setup.status()
      assert info.opentelemetry_loaded == true
      assert is_boolean(info.tracer_provider)
      assert is_boolean(info.langfuse_configured)
    end
  end

  describe "processor_config/1" do
    test "returns processor tuple with default config" do
      assert {Langfuse.OpenTelemetry.SpanProcessor, config} = Setup.processor_config()
      assert config.enabled == true
      assert config.filter_fn == nil
    end

    test "accepts enabled option" do
      assert {_, config} = Setup.processor_config(enabled: false)
      assert config.enabled == false
    end

    test "accepts filter_fn option" do
      filter = fn _span -> true end
      assert {_, config} = Setup.processor_config(filter_fn: filter)
      assert config.filter_fn == filter
    end
  end
end
