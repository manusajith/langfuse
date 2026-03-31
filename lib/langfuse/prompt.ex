defmodule Langfuse.Prompt do
  @moduledoc """
  Fetch, cache, and compile prompts from Langfuse.

  Prompts in Langfuse enable version-controlled prompt management. This module
  provides functions to fetch prompts, compile them with variables, and link
  them to generations for tracking which prompt version was used.

  ## Prompt Types

  Langfuse supports two prompt types:

    * `:text` - Simple string prompts with `{{variable}}` placeholders
    * `:chat` - List of message maps with role/content structure

  ## Fetching Prompts

  Fetch prompts by name, with optional version or label:

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt")
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", version: 2)
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", label: "production")

  ## Compiling Prompts

  Substitute variables in prompt templates:

      {:ok, prompt} = Langfuse.Prompt.get("greeting")
      compiled = Langfuse.Prompt.compile(prompt, %{name: "Alice"})

  ## Linking to Generations

  Track which prompt version was used in a generation:

      {:ok, prompt} = Langfuse.Prompt.get("chat-template")

      generation = Langfuse.generation(trace,
        name: "completion",
        model: "gpt-4",
        prompt_name: prompt.name,
        prompt_version: prompt.version
      )

  ## Caching

  Prompts are cached by default for 60 seconds. Configure TTL per request:

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", cache_ttl: 300_000)

  Use `fetch/2` to bypass the cache entirely.

  """

  alias Langfuse.HTTP

  @typedoc "Prompt type: text or chat."
  @type prompt_type :: :text | :chat

  @typedoc """
  A prompt struct containing all prompt attributes.

  The `:prompt` field contains the template content: a string for text
  prompts, or a list of message maps for chat prompts.
  """
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
  Fetches a prompt from Langfuse with caching.

  Returns the cached prompt if available and not expired. Otherwise,
  fetches from the API and caches the result.

  ## Options

    * `:version` - Specific version number to fetch.
    * `:label` - Label to fetch (e.g., "production", "latest").
    * `:resolve` - Whether to resolve prompt dependencies before returning (defaults to `true` on server).
    * `:cache_ttl` - Cache TTL in milliseconds. Defaults to 60,000 (1 minute).
    * `:fallback` - Fallback prompt struct or template to use if fetch fails.
      Can be a `%Langfuse.Prompt{}` struct or a string template.

  ## Examples

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt")
      prompt.name
      #=> "my-prompt"

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", version: 2)

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", label: "production")

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", cache_ttl: 300_000)

      # With fallback prompt struct
      fallback = %Langfuse.Prompt{
        name: "my-prompt",
        version: 0,
        type: :text,
        prompt: "Default template {{name}}",
        labels: [],
        tags: []
      }
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt", fallback: fallback)

      # With fallback template string (creates text prompt)
      {:ok, prompt} = Langfuse.Prompt.get("my-prompt",
        fallback: "Default template {{name}}"
      )

  ## Errors

  Returns `{:error, :not_found}` if the prompt does not exist and no fallback provided.

  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def get(name, opts \\ []) do
    cache_key = cache_key(name, opts)
    cache_ttl = Keyword.get(opts, :cache_ttl, 60_000)
    fallback = Keyword.get(opts, :fallback)

    case get_cached(cache_key) do
      {:ok, prompt} ->
        {:ok, prompt}

      :miss ->
        case fetch_prompt(name, opts) do
          {:ok, prompt} ->
            cache_prompt(cache_key, prompt, cache_ttl)
            {:ok, prompt}

          error ->
            handle_fetch_error(error, name, fallback)
        end
    end
  end

  defp handle_fetch_error(_error, name, %__MODULE__{} = fallback) do
    {:ok, %{fallback | name: name}}
  end

  defp handle_fetch_error(_error, name, template) when is_binary(template) do
    prompt = %__MODULE__{
      name: name,
      version: 0,
      type: :text,
      prompt: template,
      config: nil,
      labels: [],
      tags: []
    }

    {:ok, prompt}
  end

  defp handle_fetch_error(_error, name, messages) when is_list(messages) do
    prompt = %__MODULE__{
      name: name,
      version: 0,
      type: :chat,
      prompt: messages,
      config: nil,
      labels: [],
      tags: []
    }

    {:ok, prompt}
  end

  defp handle_fetch_error(error, _name, nil) do
    error
  end

  @doc """
  Fetches a prompt directly from Langfuse without caching.

  Use this when you need the latest version and want to bypass the cache.

  ## Options

    * `:version` - Specific version number to fetch.
    * `:label` - Label to fetch (e.g., "production", "latest").
    * `:resolve` - Whether to resolve prompt dependencies before returning (defaults to `true` on server).

  ## Examples

      {:ok, prompt} = Langfuse.Prompt.fetch("my-prompt")
      {:ok, prompt} = Langfuse.Prompt.fetch("my-prompt", version: 3)

  """
  @spec fetch(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def fetch(name, opts \\ []) do
    fetch_prompt(name, opts)
  end

  @doc """
  Compiles a prompt by substituting variables.

  For text prompts, replaces `{{variable}}` patterns in the template string.
  For chat prompts, replaces variables in each message's content field.

  Variable names in the template must match the keys in the variables map.
  Keys can be atoms or strings.

  ## Examples

      # Text prompt with template: "Hello {{name}}, let's talk about {{topic}}"
      compiled = Langfuse.Prompt.compile(text_prompt, %{name: "Alice", topic: "weather"})
      # => "Hello Alice, let's talk about weather"

      # Chat prompt with system message containing {{user_name}}
      compiled = Langfuse.Prompt.compile(chat_prompt, %{user_name: "Bob"})
      # => [%{"role" => "system", "content" => "You are helping Bob"}, ...]

      # Using atom keys
      compiled = Langfuse.Prompt.compile(prompt, %{name: "Alice"})

      # Using string keys
      compiled = Langfuse.Prompt.compile(prompt, %{"name" => "Alice"})

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

  The returned map can be merged into generation options to track
  which prompt version was used.

  ## Examples

      {:ok, prompt} = Langfuse.Prompt.get("my-prompt")
      meta = Langfuse.Prompt.link_meta(prompt)
      # => %{prompt_name: "my-prompt", prompt_version: 2}

      # Use with generation
      generation = Langfuse.generation(trace,
        [name: "completion", model: "gpt-4"] ++ Map.to_list(meta)
      )

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

  @doc """
  Invalidates a cached prompt by name.

  Removes all cached versions and labels for the given prompt name.
  Use this when you know a prompt has been updated in Langfuse and want
  to force a fresh fetch on the next `get/2` call.

  ## Options

    * `:version` - Only invalidate a specific version.
    * `:label` - Only invalidate a specific label.

  ## Examples

      iex> Langfuse.Prompt.invalidate("my-prompt")
      :ok

      iex> Langfuse.Prompt.invalidate("my-prompt", version: 2)
      :ok

      iex> Langfuse.Prompt.invalidate("my-prompt", label: "production")
      :ok

  """
  @spec invalidate(String.t(), keyword()) :: :ok
  def invalidate(name, opts \\ []) do
    if opts[:version] || opts[:label] do
      delete_cache_entries(name, opts[:version], opts[:label])
    else
      delete_cache_by_name(name)
    end

    :ok
  end

  @doc """
  Clears all cached prompts.

  Use this to force fresh fetches for all prompts. This is useful
  when deploying new prompt versions across the board.

  ## Examples

      iex> Langfuse.Prompt.invalidate_all()
      :ok

  """
  @spec invalidate_all() :: :ok
  def invalidate_all do
    try do
      :ets.delete_all_objects(:langfuse_prompt_cache)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  defp cache_key(name, opts) do
    version = opts[:version]
    label = opts[:label]
    resolve = if(opts[:resolve] == false, do: false, else: true)
    {name, version, label, resolve}
  end

  defp delete_cache_entries(name, version, label) do
    :ets.match_delete(
      :langfuse_prompt_cache,
      {{name, cache_match(version), cache_match(label), :_}, :_, :_}
    )
  rescue
    ArgumentError -> :ok
  end

  defp delete_cache_by_name(name) do
    :ets.match_delete(:langfuse_prompt_cache, {{name, :_, :_, :_}, :_, :_})
  rescue
    ArgumentError -> :ok
  end

  defp cache_match(nil), do: :_
  defp cache_match(value), do: value

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
