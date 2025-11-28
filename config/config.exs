import Config

config :langfuse,
  host: "https://cloud.langfuse.com",
  flush_interval: 5_000,
  batch_size: 100,
  max_retries: 3,
  enabled: true

import_config "#{config_env()}.exs"
