defmodule Langfuse.Prompt do
  @moduledoc """
  Prompt management for Langfuse.

  Fetches, caches, and compiles prompts from Langfuse. Supports both
  text and chat prompt types with variable substitution.

  ## Examples

      # Fetch a prompt by name
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt")

      # Fetch a specific version
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", version: 2)

      # Fetch by label
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", label: "production")

      # Compile with variables
      compiled = Langfuse.Prompt.compile(prompt, %{name: "Alice", topic: "weather"})

      # Link prompt to generation
      generation = Langfuse.generation(trace,
        name: "chat",
        prompt_name: prompt.name,
        prompt_version: prompt.version
      )

  """

  alias Langfuse.HTTP

  @type prompt_type :: :text | :chat

  @type t :: %__MODULE__{
          name: String.t(),
          version: pos_integer(),
          type: prompt_type(),
          prompt: String.t() | list(map()),
          config: map() | nil,
          labels: list(String.t()),
          tags: list(String.t())
        }

  defstruct [:name, :version, :type, :prompt, :config, :labels, :tags]

  @doc """
  Fetches a prompt from Langfuse.

  ## Options

    * `:version` - Specific version number to fetch
    * `:label` - Label to fetch (e.g., "production", "latest")
    * `:cache_ttl` - Cache TTL in milliseconds (default: 60_000)

  ## Examples

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt")
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", version: 2)
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", label: "production")

  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def get(name, opts \\ []) do
    cache_key = cache_key(name, opts)
    cache_ttl = Keyword.get(opts, :cache_ttl, 60_000)

    case get_cached(cache_key) do
      {:ok, prompt} ->
        {:ok, prompt}

      :miss ->
        case fetch_prompt(name, opts) do
          {:ok, prompt} ->
            cache_prompt(cache_key, prompt, cache_ttl)
            {:ok, prompt}

          error ->
            error
        end
    end
  end

  @doc """
  Fetches a prompt without caching.
  """
  @spec fetch(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def fetch(name, opts \\ []) do
    fetch_prompt(name, opts)
  end

  @doc """
  Compiles a prompt by substituting variables.

  For text prompts, replaces `{{variable}}` patterns.
  For chat prompts, replaces variables in each message's content.

  ## Examples

      # Text prompt: "Hello {{name}}, let's talk about {{topic}}"
      compiled = Langfuse.Prompt.compile(prompt, %{name: "Alice", topic: "weather"})
      # => "Hello Alice, let's talk about weather"

      # Chat prompt
      compiled = Langfuse.Prompt.compile(chat_prompt, %{user_name: "Bob"})
      # => [%{role: "system", content: "You are helping Bob"}, ...]

  """
  @spec compile(t(), map()) :: String.t() | list(map())
  def compile(%__MODULE__{type: :text, prompt: template}, variables) when is_binary(template) do
    compile_template(template, variables)
  end

  def compile(%__MODULE__{type: :chat, prompt: messages}, variables) when is_list(messages) do
    Enum.map(messages, fn message ->
      Map.update(message, "content", "", fn content ->
        compile_template(content, variables)
      end)
    end)
  end

  @doc """
  Returns prompt metadata for linking to generations.

  ## Examples

      meta = Langfuse.Prompt.link_meta(prompt)
      # => %{prompt_name: "my-prompt", prompt_version: 2}

  """
  @spec link_meta(t()) :: %{prompt_name: String.t(), prompt_version: pos_integer()}
  def link_meta(%__MODULE__{name: name, version: version}) do
    %{prompt_name: name, prompt_version: version}
  end

  defp fetch_prompt(name, opts) do
    case HTTP.get_prompt(name, opts) do
      {:ok, data} ->
        {:ok, parse_prompt(data)}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_prompt(data) do
    %__MODULE__{
      name: data["name"],
      version: data["version"],
      type: parse_type(data["type"]),
      prompt: data["prompt"],
      config: data["config"],
      labels: data["labels"] || [],
      tags: data["tags"] || []
    }
  end

  defp parse_type("text"), do: :text
  defp parse_type("chat"), do: :chat
  defp parse_type(_), do: :text

  defp compile_template(template, variables) do
    Enum.reduce(variables, template, fn {key, value}, acc ->
      pattern = "{{#{key}}}"
      String.replace(acc, pattern, to_string(value))
    end)
  end

  defp cache_key(name, opts) do
    version = opts[:version]
    label = opts[:label]
    {name, version, label}
  end

  defp get_cached(key) do
    case :ets.lookup(:langfuse_prompt_cache, key) do
      [{^key, prompt, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, prompt}
        else
          :ets.delete(:langfuse_prompt_cache, key)
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_prompt(key, prompt, ttl) do
    expires_at = System.monotonic_time(:millisecond) + ttl

    try do
      :ets.insert(:langfuse_prompt_cache, {key, prompt, expires_at})
    rescue
      ArgumentError ->
        :ets.new(:langfuse_prompt_cache, [:set, :public, :named_table])
        :ets.insert(:langfuse_prompt_cache, {key, prompt, expires_at})
    end
  end
end
