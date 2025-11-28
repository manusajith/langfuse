defmodule Langfuse.HTTPBehaviour do
  @moduledoc false

  @type response :: {:ok, map()} | {:error, term()}

  @callback ingest(list(map())) :: response()
  @callback get_prompt(String.t(), keyword()) :: response()
  @callback get(String.t(), keyword()) :: response()
  @callback post(String.t(), map()) :: response()
end
