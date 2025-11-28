defmodule Langfuse.OpenTelemetry do
  @moduledoc """
  OpenTelemetry integration utilities for Langfuse.

  This module provides utilities for bridging OpenTelemetry instrumentation
  with Langfuse's tracing capabilities. It supports two integration modes:

  ## Mode 1: Native OTEL Export (Recommended)

  Configure your OTEL exporter to send traces directly to Langfuse's
  OpenTelemetry endpoint. Add to your `config/runtime.exs`:

      config :opentelemetry_exporter,
        otlp_protocol: :http_protobuf,
        otlp_endpoint: "https://cloud.langfuse.com/api/public/otel/v1/traces",
        otlp_headers: [
          {"Authorization", "Basic " <> Base.encode64("pk-lf-xxx:sk-lf-xxx")}
        ]

  This sends all OTEL spans to Langfuse where they are converted to traces
  and observations.

  ## Mode 2: Bridge to Langfuse SDK

  Use the bridging functions to convert OTEL spans to Langfuse observations
  within your application:

      # Start a trace from an OTEL span context
      {:ok, trace} = Langfuse.OpenTelemetry.trace_from_context(ctx)

      # Or extract trace/span IDs for correlation
      {trace_id, span_id} = Langfuse.OpenTelemetry.extract_ids(ctx)

  ## Attribute Mapping

  OTEL attributes are automatically mapped to Langfuse fields:

  | OTEL Attribute | Langfuse Field |
  |----------------|----------------|
  | `gen_ai.request.model` | `model` |
  | `gen_ai.usage.input_tokens` | `usage.input` |
  | `gen_ai.usage.output_tokens` | `usage.output` |
  | `gen_ai.prompt` | `input` |
  | `gen_ai.completion` | `output` |
  | `langfuse.trace.user_id` | `user_id` |
  | `langfuse.trace.session_id` | `session_id` |
  | `langfuse.observation.level` | `level` |

  See the [Langfuse OTEL documentation](https://langfuse.com/docs/integrations/otel)
  for the complete attribute mapping reference.

  ## Example: Tracing with OpenTelemetry

      defmodule MyApp.LLMService do
        require OpenTelemetry.Tracer, as: Tracer

        def call_llm(prompt) do
          Tracer.with_span "llm-generation", kind: :client do
            Tracer.set_attributes([
              {"gen_ai.request.model", "gpt-4"},
              {"gen_ai.prompt", prompt},
              {"langfuse.trace.user_id", get_user_id()}
            ])

            response = make_api_call(prompt)

            Tracer.set_attributes([
              {"gen_ai.completion", response},
              {"gen_ai.usage.input_tokens", count_tokens(prompt)},
              {"gen_ai.usage.output_tokens", count_tokens(response)}
            ])

            response
          end
        end
      end

  """

  @doc """
  Extracts trace and span IDs from an OpenTelemetry span context.

  Returns a tuple of `{trace_id, span_id}` as hex strings suitable for
  use with Langfuse's trace correlation.

  ## Examples

      ctx = OpenTelemetry.Ctx.get_current()
      span_ctx = OpenTelemetry.Tracer.current_span_ctx(ctx)
      {trace_id, span_id} = Langfuse.OpenTelemetry.extract_ids(span_ctx)

  """
  @spec extract_ids(term()) :: {String.t(), String.t()} | nil
  def extract_ids(span_ctx) do
    case span_ctx do
      {trace_id, span_id, _trace_flags, _tracestate, _is_valid}
      when is_integer(trace_id) and is_integer(span_id) ->
        {
          Integer.to_string(trace_id, 16) |> String.downcase() |> String.pad_leading(32, "0"),
          Integer.to_string(span_id, 16) |> String.downcase() |> String.pad_leading(16, "0")
        }

      _ ->
        nil
    end
  end

  @doc """
  Creates a Langfuse trace correlated with an OpenTelemetry span context.

  The trace will use the OTEL trace ID for correlation, enabling unified
  tracing across OTEL and Langfuse instrumented code.

  ## Options

  All standard `Langfuse.trace/1` options are supported, plus:

    * `:span_ctx` - OpenTelemetry span context (required)

  ## Examples

      span_ctx = OpenTelemetry.Tracer.current_span_ctx()
      {:ok, trace} = Langfuse.OpenTelemetry.trace_from_context(
        span_ctx,
        name: "my-operation",
        user_id: "user-123"
      )

  """
  @spec trace_from_context(term(), keyword()) :: {:ok, Langfuse.Trace.t()} | {:error, :invalid_context}
  def trace_from_context(span_ctx, opts \\ []) do
    case extract_ids(span_ctx) do
      {trace_id, _span_id} ->
        trace_opts = Keyword.put(opts, :id, trace_id)
        {:ok, Langfuse.trace(trace_opts)}

      nil ->
        {:error, :invalid_context}
    end
  end

  @doc """
  Maps OpenTelemetry semantic convention attributes to Langfuse fields.

  This is useful when processing OTEL spans and converting them to
  Langfuse observations.

  ## Examples

      iex> attrs = %{"gen_ai.request.model" => "gpt-4", "gen_ai.usage.input_tokens" => 100}
      iex> Langfuse.OpenTelemetry.map_attributes(attrs)
      %{model: "gpt-4", usage: %{input: 100}}

  """
  @spec map_attributes(map()) :: map()
  def map_attributes(otel_attrs) when is_map(otel_attrs) do
    Enum.reduce(otel_attrs, %{}, fn {key, value}, acc ->
      case map_attribute(key, value) do
        nil -> acc
        {field, mapped_value} -> deep_merge(acc, %{field => mapped_value})
      end
    end)
  end

  defp map_attribute("gen_ai.request.model", value), do: {:model, value}
  defp map_attribute("gen_ai.response.model", value), do: {:model, value}
  defp map_attribute("gen_ai.prompt", value), do: {:input, value}
  defp map_attribute("gen_ai.completion", value), do: {:output, value}
  defp map_attribute("gen_ai.usage.input_tokens", value), do: {:usage, %{input: value}}
  defp map_attribute("gen_ai.usage.output_tokens", value), do: {:usage, %{output: value}}
  defp map_attribute("gen_ai.usage.total_tokens", value), do: {:usage, %{total: value}}
  defp map_attribute("langfuse.trace.user_id", value), do: {:user_id, value}
  defp map_attribute("langfuse.trace.session_id", value), do: {:session_id, value}
  defp map_attribute("langfuse.observation.level", value), do: {:level, String.to_atom(String.downcase(value))}
  defp map_attribute("langfuse.observation.model", value), do: {:model, value}
  defp map_attribute(_key, _value), do: nil

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = l, %{} = r -> deep_merge(l, r)
      _key, _l, r -> r
    end)
  end

  @doc """
  Returns the OTEL exporter configuration for sending to Langfuse.

  ## Options

    * `:host` - Langfuse host (default: from config or "https://cloud.langfuse.com")
    * `:public_key` - Public API key (default: from config)
    * `:secret_key` - Secret API key (default: from config)

  ## Examples

      config = Langfuse.OpenTelemetry.exporter_config()
      # => [
      #      otlp_protocol: :http_protobuf,
      #      otlp_endpoint: "https://cloud.langfuse.com/api/public/otel/v1/traces",
      #      otlp_headers: [{"Authorization", "Basic cGstbGYtLi4uOnNrLWxmLS4uLg=="}]
      #    ]

  """
  @spec exporter_config(keyword()) :: keyword()
  def exporter_config(opts \\ []) do
    config = Langfuse.Config.get()

    host = Keyword.get(opts, :host, config.host || "https://cloud.langfuse.com")
    public_key = Keyword.get(opts, :public_key, config.public_key)
    secret_key = Keyword.get(opts, :secret_key, config.secret_key)

    auth = Base.encode64("#{public_key}:#{secret_key}")

    [
      otlp_protocol: :http_protobuf,
      otlp_endpoint: "#{host}/api/public/otel/v1/traces",
      otlp_headers: [{"Authorization", "Basic #{auth}"}]
    ]
  end
end
