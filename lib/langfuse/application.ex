defmodule Langfuse.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Langfuse.Config,
      Langfuse.Ingestion
    ]

    opts = [strategy: :one_for_one, name: Langfuse.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
