defmodule Langfuse.OpenTelemetry do
  @moduledoc """
  OpenTelemetry integration for Langfuse.

  This module provides comprehensive OpenTelemetry support including:

    * **Span Processor** - Intercept OTEL spans and convert to Langfuse observations
    * **Attribute Mapping** - Map GenAI semantic conventions to Langfuse fields
    * **W3C Trace Context** - Distributed tracing with traceparent headers
    * **Setup Helpers** - Easy configuration for OTEL export

  ## Quick Start

  ### Option 1: Native OTEL Export (Simplest)

  Configure OpenTelemetry to export directly to Langfuse:

      # config/runtime.exs
      config :opentelemetry_exporter,
        otlp_protocol: :http_protobuf,
        otlp_endpoint: System.get_env("LANGFUSE_HOST", "https://cloud.langfuse.com") <>
                       "/api/public/otel/v1/traces",
        otlp_headers: [
          {"Authorization", "Basic " <> Base.encode64(
            System.get_env("LANGFUSE_PUBLIC_KEY") <> ":" <>
            System.get_env("LANGFUSE_SECRET_KEY")
          )}
        ]

  Or programmatically:

      Langfuse.OpenTelemetry.Setup.configure_exporter()

  ### Option 2: Span Processor (More Control)

  Use Langfuse's span processor for fine-grained control:

      # In your application supervisor
      Langfuse.OpenTelemetry.Setup.register_processor()

      # Or with filtering
      Langfuse.OpenTelemetry.Setup.register_processor(
        filter_fn: fn span ->
          attrs = elem(span, 7)
          Map.has_key?(attrs, "gen_ai.request.model")
        end
      )

  ## Attribute Mapping

  The integration automatically maps OpenTelemetry semantic conventions to
  Langfuse fields. See `Langfuse.OpenTelemetry.AttributeMapper` for the
  complete mapping reference.

  ### GenAI Conventions

  | OTEL Attribute | Langfuse Field |
  |----------------|----------------|
  | `gen_ai.request.model` | `model` |
  | `gen_ai.usage.input_tokens` | `usage.input` |
  | `gen_ai.usage.output_tokens` | `usage.output` |
  | `gen_ai.prompt` | `input` |
  | `gen_ai.completion` | `output` |
  | `gen_ai.request.temperature` | `modelParameters.temperature` |

  ### Langfuse Namespace

  | OTEL Attribute | Langfuse Field |
  |----------------|----------------|
  | `langfuse.user.id` | `userId` |
  | `langfuse.session.id` | `sessionId` |
  | `langfuse.trace.tags` | `tags` |
  | `langfuse.observation.level` | `level` |

  ## Distributed Tracing

  Propagate trace context across service boundaries using W3C Trace Context:

      # Extract from incoming request
      context = Langfuse.OpenTelemetry.TraceContext.extract!(conn.req_headers)
      trace = Langfuse.trace(id: context.trace_id, name: "api-request")

      # Inject into outgoing request
      headers = Langfuse.OpenTelemetry.TraceContext.inject(trace.id, span.id)
      Req.post(downstream_url, headers: headers, json: payload)

  ## Example: Tracing LLM Calls

      defmodule MyApp.LLM do
        require OpenTelemetry.Tracer, as: Tracer

        def generate(prompt, opts \\\\ []) do
          model = Keyword.get(opts, :model, "gpt-4")

          Tracer.with_span "llm.generate", kind: :client do
            Tracer.set_attributes([
              {"gen_ai.system", "openai"},
              {"gen_ai.request.model", model},
              {"gen_ai.prompt", prompt},
              {"langfuse.user.id", opts[:user_id]}
            ])

            {response, usage} = call_openai(prompt, model)

            Tracer.set_attributes([
              {"gen_ai.completion", response},
              {"gen_ai.usage.input_tokens", usage.input},
              {"gen_ai.usage.output_tokens", usage.output}
            ])

            response
          end
        end
      end

  ## Submodules

    * `Langfuse.OpenTelemetry.SpanProcessor` - OTEL span processor behaviour
    * `Langfuse.OpenTelemetry.AttributeMapper` - Attribute mapping logic
    * `Langfuse.OpenTelemetry.TraceContext` - W3C Trace Context support
    * `Langfuse.OpenTelemetry.Setup` - Configuration helpers

  """

  alias Langfuse.OpenTelemetry.{AttributeMapper, Setup, TraceContext}

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
          format_trace_id(trace_id),
          format_span_id(span_id)
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

  All standard `Langfuse.trace/1` options are supported.

  ## Examples

      span_ctx = OpenTelemetry.Tracer.current_span_ctx()
      {:ok, trace} = Langfuse.OpenTelemetry.trace_from_context(
        span_ctx,
        name: "my-operation",
        user_id: "user-123"
      )

  """
  @spec trace_from_context(term(), keyword()) ::
          {:ok, Langfuse.Trace.t()} | {:error, :invalid_context}
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

  Delegates to `Langfuse.OpenTelemetry.AttributeMapper.map_attributes/1`.

  ## Examples

      iex> attrs = %{"gen_ai.request.model" => "gpt-4", "gen_ai.usage.input_tokens" => 100}
      iex> Langfuse.OpenTelemetry.map_attributes(attrs)
      %{model: "gpt-4", usage: %{input: 100}}

  """
  @spec map_attributes(map()) :: map()
  defdelegate map_attributes(attrs), to: AttributeMapper

  @doc """
  Extracts W3C Trace Context from HTTP headers.

  Delegates to `Langfuse.OpenTelemetry.TraceContext.extract/1`.

  ## Examples

      headers = [{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"}]
      {:ok, context} = Langfuse.OpenTelemetry.extract_trace_context(headers)

  """
  @spec extract_trace_context(list() | map()) ::
          {:ok, TraceContext.t()} | {:error, atom()}
  defdelegate extract_trace_context(headers), to: TraceContext, as: :extract

  @doc """
  Generates W3C Trace Context headers for outgoing requests.

  Delegates to `Langfuse.OpenTelemetry.TraceContext.inject/3`.

  ## Examples

      headers = Langfuse.OpenTelemetry.inject_trace_context(trace_id, span_id)

  """
  @spec inject_trace_context(String.t(), String.t(), keyword()) ::
          list({String.t(), String.t()})
  defdelegate inject_trace_context(trace_id, span_id, opts \\ []), to: TraceContext, as: :inject

  @doc """
  Returns the OTEL exporter configuration for sending to Langfuse.

  Delegates to `Langfuse.OpenTelemetry.Setup.exporter_config/1`.

  ## Examples

      config = Langfuse.OpenTelemetry.exporter_config()

  """
  @spec exporter_config(keyword()) :: keyword()
  defdelegate exporter_config(opts \\ []), to: Setup

  @doc """
  Configures the OpenTelemetry exporter to send to Langfuse.

  Delegates to `Langfuse.OpenTelemetry.Setup.configure_exporter/1`.

  ## Examples

      Langfuse.OpenTelemetry.configure_exporter()

  """
  @spec configure_exporter(keyword()) :: :ok
  defdelegate configure_exporter(opts \\ []), to: Setup

  @doc """
  Returns the span processor configuration for OpenTelemetry.

  Delegates to `Langfuse.OpenTelemetry.Setup.processor_config/1`.

  ## Examples

      config :opentelemetry,
        processors: [
          Langfuse.OpenTelemetry.processor_config()
        ]

  """
  @spec processor_config(keyword()) :: {module(), map()}
  defdelegate processor_config(opts \\ []), to: Setup

  defp format_trace_id(trace_id) when is_integer(trace_id) do
    trace_id
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(32, "0")
  end

  defp format_span_id(span_id) when is_integer(span_id) do
    span_id
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(16, "0")
  end
end
