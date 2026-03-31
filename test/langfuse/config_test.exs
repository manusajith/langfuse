defmodule Langfuse.ConfigTest do
  use ExUnit.Case, async: false

  alias Langfuse.Config

  setup do
    original_config = %{
      public_key: Application.get_env(:langfuse, :public_key),
      secret_key: Application.get_env(:langfuse, :secret_key),
      host: Application.get_env(:langfuse, :host),
      environment: Application.get_env(:langfuse, :environment),
      flush_interval: Application.get_env(:langfuse, :flush_interval),
      batch_size: Application.get_env(:langfuse, :batch_size),
      max_retries: Application.get_env(:langfuse, :max_retries),
      enabled: Application.get_env(:langfuse, :enabled),
      debug: Application.get_env(:langfuse, :debug),
      cacertfile: Application.get_env(:langfuse, :cacertfile)
    }

    on_exit(fn ->
      Enum.each(original_config, fn {key, value} ->
        if value do
          Application.put_env(:langfuse, key, value)
        else
          Application.delete_env(:langfuse, key)
        end
      end)

      Config.reload()
    end)

    :ok
  end

  describe "get/0" do
    test "returns config struct" do
      config = Config.get()
      assert %Config{} = config
    end

    test "returns default host when not configured" do
      Application.delete_env(:langfuse, :host)
      Config.reload()

      config = Config.get()
      assert config.host == "https://cloud.langfuse.com"
    end
  end

  describe "get/1" do
    test "returns specific config value" do
      Application.put_env(:langfuse, :host, "https://custom.example.com")
      Config.reload()

      assert Config.get(:host) == "https://custom.example.com"
    end

    test "returns nil for unconfigured keys" do
      Application.delete_env(:langfuse, :environment)
      Config.reload()

      assert Config.get(:environment) == nil
    end
  end

  describe "enabled?/0" do
    test "returns true by default" do
      Application.delete_env(:langfuse, :enabled)
      Config.reload()

      assert Config.enabled?() == true
    end

    test "returns false when disabled" do
      Application.put_env(:langfuse, :enabled, false)
      Config.reload()

      assert Config.enabled?() == false
    end

    test "handles string 'true'" do
      Application.put_env(:langfuse, :enabled, "true")
      Config.reload()

      assert Config.enabled?() == true
    end

    test "handles string 'false'" do
      Application.put_env(:langfuse, :enabled, "false")
      Config.reload()

      assert Config.enabled?() == false
    end

    test "returns default for invalid string" do
      Application.put_env(:langfuse, :enabled, "invalid")
      Config.reload()

      assert Config.enabled?() == true
    end
  end

  describe "configured?/0" do
    test "returns true when both keys are set" do
      Application.put_env(:langfuse, :public_key, "pk-test")
      Application.put_env(:langfuse, :secret_key, "sk-test")
      Config.reload()

      assert Config.configured?() == true
    end

    test "returns false when public_key is missing" do
      Application.delete_env(:langfuse, :public_key)
      Application.put_env(:langfuse, :secret_key, "sk-test")
      Config.reload()

      assert Config.configured?() == false
    end

    test "returns false when secret_key is missing" do
      Application.put_env(:langfuse, :public_key, "pk-test")
      Application.delete_env(:langfuse, :secret_key)
      Config.reload()

      assert Config.configured?() == false
    end
  end

  describe "debug?/0" do
    test "returns false by default" do
      Application.delete_env(:langfuse, :debug)
      Config.reload()

      assert Config.debug?() == false
    end

    test "returns true when enabled" do
      Application.put_env(:langfuse, :debug, true)
      Config.reload()

      assert Config.debug?() == true
    end

    test "handles string 'true'" do
      Application.put_env(:langfuse, :debug, "true")
      Config.reload()

      assert Config.debug?() == true
    end

    test "handles string 'false'" do
      Application.put_env(:langfuse, :debug, "false")
      Config.reload()

      assert Config.debug?() == false
    end
  end

  describe "reload/0" do
    test "reloads config from application env" do
      Application.put_env(:langfuse, :host, "https://old.example.com")
      Config.reload()

      assert Config.get(:host) == "https://old.example.com"

      Application.put_env(:langfuse, :host, "https://new.example.com")
      Config.reload()

      assert Config.get(:host) == "https://new.example.com"
    end
  end

  describe "integer config values" do
    test "handles integer flush_interval" do
      Application.put_env(:langfuse, :flush_interval, 10_000)
      Config.reload()

      assert Config.get(:flush_interval) == 10_000
    end

    test "returns default flush_interval when not configured" do
      Application.delete_env(:langfuse, :flush_interval)
      Config.reload()

      assert Config.get(:flush_interval) == 5_000
    end

    test "handles integer batch_size" do
      Application.put_env(:langfuse, :batch_size, 50)
      Config.reload()

      assert Config.get(:batch_size) == 50
    end

    test "returns default batch_size when not configured" do
      Application.delete_env(:langfuse, :batch_size)
      Config.reload()

      assert Config.get(:batch_size) == 100
    end

    test "handles integer max_retries" do
      Application.put_env(:langfuse, :max_retries, 5)
      Config.reload()

      assert Config.get(:max_retries) == 5
    end

    test "returns default max_retries when not configured" do
      Application.delete_env(:langfuse, :max_retries)
      Config.reload()

      assert Config.get(:max_retries) == 3
    end
  end

  describe "environment variable precedence" do
    test "env var overrides app config for public_key" do
      Application.put_env(:langfuse, :public_key, "app-public-key")
      System.put_env("LANGFUSE_PUBLIC_KEY", "env-public-key")
      Config.reload()

      assert Config.get(:public_key) == "env-public-key"

      System.delete_env("LANGFUSE_PUBLIC_KEY")
      Config.reload()
    end

    test "env var overrides app config for host" do
      Application.put_env(:langfuse, :host, "https://app.example.com")
      System.put_env("LANGFUSE_HOST", "https://env.example.com")
      Config.reload()

      assert Config.get(:host) == "https://env.example.com"

      System.delete_env("LANGFUSE_HOST")
      Config.reload()
    end

    test "env var overrides app config for environment" do
      Application.put_env(:langfuse, :environment, "app-env")
      System.put_env("LANGFUSE_ENVIRONMENT", "env-env")
      Config.reload()

      assert Config.get(:environment) == "env-env"

      System.delete_env("LANGFUSE_ENVIRONMENT")
      Config.reload()
    end

    test "env var overrides app config for cacertfile" do
      Application.put_env(:langfuse, :cacertfile, "/app/ca.pem")
      System.put_env("LANGFUSE_CACERTFILE", "/env/ca.pem")
      Config.reload()

      assert Config.get(:cacertfile) == "/env/ca.pem"

      System.delete_env("LANGFUSE_CACERTFILE")
      Config.reload()
    end
  end

  describe "cacertfile" do
    test "returns nil by default" do
      Application.delete_env(:langfuse, :cacertfile)
      Config.reload()

      assert Config.get(:cacertfile) == nil
    end

    test "returns configured path" do
      Application.put_env(:langfuse, :cacertfile, "/path/to/ca-cert.pem")
      Config.reload()

      assert Config.get(:cacertfile) == "/path/to/ca-cert.pem"
    end
  end
end
