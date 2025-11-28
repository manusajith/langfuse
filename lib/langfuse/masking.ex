defmodule Langfuse.Masking do
  @moduledoc """
  Data masking for sensitive information in Langfuse traces.

  This module provides utilities to mask sensitive data (like API keys,
  passwords, credit card numbers) before sending to Langfuse. Masking
  helps comply with data privacy requirements while still enabling
  observability.

  ## Configuration

  Configure masking patterns in your application config:

      config :langfuse,
        masking: [
          enabled: true,
          patterns: [
            {~r/sk-[a-zA-Z0-9]{32,}/, "[MASKED_API_KEY]"},
            {~r/\\b\\d{4}[- ]?\\d{4}[- ]?\\d{4}[- ]?\\d{4}\\b/, "[MASKED_CARD]"},
            {~r/password[\"']?\\s*[:=]\\s*[\"']?[^\"'\\s]+/, "password: [MASKED]"}
          ],
          mask_keys: [:password, :secret, :api_key, :token, :authorization]
        ]

  ## Usage

  Masking is automatically applied when configured. You can also
  apply it manually:

      masked = Langfuse.Masking.mask("My API key is sk-abc123...")
      # => "My API key is [MASKED_API_KEY]"

      masked = Langfuse.Masking.mask_value(%{password: "secret123", name: "test"})
      # => %{password: "[MASKED]", name: "test"}

  ## Custom Masking Function

  For complex masking logic, provide a custom function:

      config :langfuse,
        masking: [
          enabled: true,
          mask_fn: &MyApp.Masking.custom_mask/1
        ]

  """

  @default_patterns [
    {~r/sk-[a-zA-Z0-9]{20,}/, "[MASKED_API_KEY]"},
    {~r/pk-[a-zA-Z0-9]{20,}/, "[MASKED_PUBLIC_KEY]"},
    {~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, "[MASKED_EMAIL]"}
  ]

  @default_mask_keys [:password, :secret, :api_key, :token, :authorization, :secret_key, :private_key]

  @typedoc "Masking configuration options."
  @type config :: [
          enabled: boolean(),
          patterns: [{Regex.t(), String.t()}],
          mask_keys: [atom()],
          mask_fn: (term() -> term()) | nil
        ]

  @doc """
  Masks sensitive data in the given value.

  Applies configured patterns and key-based masking to strings and maps.
  Returns the original value unchanged if masking is disabled.

  ## Examples

      iex> Langfuse.Masking.mask("API key: sk-test1234567890abcdefghij")
      "API key: [MASKED_API_KEY]"

      iex> Langfuse.Masking.mask(%{user: "alice", password: "secret"})
      %{user: "alice", password: "[MASKED]"}

  """
  @spec mask(term()) :: term()
  def mask(value) do
    config = get_config()

    if config[:enabled] do
      case config[:mask_fn] do
        nil -> do_mask(value, config)
        fun when is_function(fun, 1) -> fun.(value)
      end
    else
      value
    end
  end

  @doc """
  Masks a string using configured patterns.

  ## Examples

      iex> Langfuse.Masking.mask_string("Contact: test@example.com")
      "Contact: [MASKED_EMAIL]"

  """
  @spec mask_string(String.t()) :: String.t()
  def mask_string(string) when is_binary(string) do
    patterns = get_patterns()

    Enum.reduce(patterns, string, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  def mask_string(value), do: value

  @doc """
  Masks sensitive keys in a map.

  Keys matching configured `mask_keys` have their values replaced
  with "[MASKED]".

  ## Examples

      iex> Langfuse.Masking.mask_map(%{username: "alice", password: "secret123"})
      %{username: "alice", password: "[MASKED]"}

  """
  @spec mask_map(map()) :: map()
  def mask_map(map) when is_map(map) do
    mask_keys = get_mask_keys()

    Map.new(map, fn {key, value} ->
      if should_mask_key?(key, mask_keys) do
        {key, "[MASKED]"}
      else
        {key, do_mask(value, get_config())}
      end
    end)
  end

  def mask_map(value), do: value

  @doc """
  Returns whether masking is enabled.

  ## Examples

      iex> Langfuse.Masking.enabled?()
      false

  """
  @spec enabled?() :: boolean()
  def enabled? do
    config = get_config()
    config[:enabled] == true
  end

  defp do_mask(value, config) when is_binary(value) do
    patterns = config[:patterns] || @default_patterns

    Enum.reduce(patterns, value, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  defp do_mask(value, config) when is_map(value) do
    mask_keys = config[:mask_keys] || @default_mask_keys

    Map.new(value, fn {key, val} ->
      if should_mask_key?(key, mask_keys) do
        {key, "[MASKED]"}
      else
        {key, do_mask(val, config)}
      end
    end)
  end

  defp do_mask(value, config) when is_list(value) do
    Enum.map(value, &do_mask(&1, config))
  end

  defp do_mask(value, _config), do: value

  defp should_mask_key?(key, mask_keys) when is_atom(key) do
    key in mask_keys or
      (key |> Atom.to_string() |> String.downcase() |> String.to_atom()) in mask_keys
  end

  defp should_mask_key?(key, mask_keys) when is_binary(key) do
    String.to_atom(key) in mask_keys or
      (key |> String.downcase() |> String.to_atom()) in mask_keys
  end

  defp should_mask_key?(_key, _mask_keys), do: false

  defp get_config do
    Application.get_env(:langfuse, :masking, [])
  end

  defp get_patterns do
    config = get_config()
    config[:patterns] || @default_patterns
  end

  defp get_mask_keys do
    config = get_config()
    config[:mask_keys] || @default_mask_keys
  end
end
