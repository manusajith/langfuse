import Config

if config_env() == :prod do
  config :langfuse,
    public_key: System.get_env("LANGFUSE_PUBLIC_KEY"),
    secret_key: System.get_env("LANGFUSE_SECRET_KEY"),
    host: System.get_env("LANGFUSE_HOST", "https://cloud.langfuse.com")
end
