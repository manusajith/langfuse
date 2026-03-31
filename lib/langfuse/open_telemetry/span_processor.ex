defmodule Langfuse.OpenTelemetry.SpanProcessor do
  @moduledoc """
  OpenTelemetry span processor that exports spans to Langfuse.

  This module implements the `:otel_span_processor` behaviour, intercepting
  OpenTelemetry spans and converting them to Langfuse observations. Spans are
  automatically categorized as traces, spans, or generations based on their
  attributes.

  ## Setup

  Add the processor to your OpenTelemetry SDK configuration:

      # In config/runtime.exs
      config :opentelemetry,
        processors: [
          {:otel_batch_processor, %{}},
          {Langfuse.OpenTelemetry.SpanProcessor, %{}}
        ]

  Or programmatically:

      :otel_batch_processor.set_exporter(:otel_exporter_otlp)
      Langfuse.OpenTelemetry.SpanProcessor.start_link()

  ## Span to Observation Mapping

  OpenTelemetry spans are converted to Langfuse observations based on attributes:

    * Spans with `gen_ai.*` or `model` attributes become **generations**
    * Root spans (no parent) create a new **trace** + root **span**
    * Child spans become nested **spans** under their parent

  ## Attribute Mapping

  The processor maps OpenTelemetry attributes to Langfuse fields following
  the GenAI semantic conventions. See `Langfuse.OpenTelemetry.AttributeMapper`
  for the complete mapping reference.

  ## Configuration

  The processor accepts these options in its config map:

    * `:enabled` - Whether to process spans (default: true)
    * `:filter_fn` - Optional function `(span) -> boolean` to filter spans

  ## Example

      # Filter to only process LLM-related spans
      config :opentelemetry,
        processors: [
          {Langfuse.OpenTelemetry.SpanProcessor, %{
            filter_fn: fn span ->
              attrs = elem(span, 7)
              Map.has_key?(attrs, "gen_ai.request.model")
            end
          }}
        ]

  """

  @behaviour :otel_span_processor

  alias Langfuse.Ingestion
  alias Langfuse.OpenTelemetry.AttributeMapper

  @typedoc "Processor configuration options."
  @type config :: %{
          optional(:enabled) => boolean(),
          optional(:filter_fn) => (term() -> boolean())
        }

  @doc false
  def start_link(config \\ %{}) do
    :otel_span_processor.start_link(__MODULE__, config)
  end

  @impl :otel_span_processor
  def on_start(_ctx, span, _config) do
    span
  end

  @impl :otel_span_processor
  def on_end(span, config) do
    if config[:enabled] == false do
      :dropped
    else
      case should_process?(span, config) do
        true ->
          process_span(span)
          true

        false ->
          :dropped
      end
    end
  end

  @impl :otel_span_processor
  def force_flush(_config) do
    Ingestion.flush()
    :ok
  end

  defp should_process?(span, config) do
    case config[:filter_fn] do
      nil -> true
      fun when is_function(fun, 1) -> fun.(span)
      _ -> true
    end
  end

  defp process_span(span) do
    {trace_id, span_id, parent_span_id, name, _kind, start_time, end_time, attributes, _events,
     _links, status, _is_recording} = normalize_span(span)

    trace_id_hex = format_trace_id(trace_id)
    span_id_hex = format_span_id(span_id)
    parent_span_id_hex = format_span_id(parent_span_id)

    mapped_attrs = AttributeMapper.map_attributes(attributes)
    is_generation = generation?(attributes, mapped_attrs)
    is_root = is_nil(parent_span_id) or parent_span_id == 0

    if is_root do
      create_trace_event(trace_id_hex, name, mapped_attrs, start_time)
    end

    if is_generation do
      create_generation_event(
        trace_id_hex,
        span_id_hex,
        parent_span_id_hex,
        name,
        mapped_attrs,
        start_time,
        end_time,
        status
      )
    else
      create_span_event(
        trace_id_hex,
        span_id_hex,
        parent_span_id_hex,
        name,
        mapped_attrs,
        start_time,
        end_time,
        status
      )
    end
  end

  defp normalize_span(span) when is_tuple(span) do
    case tuple_size(span) do
      12 ->
        span

      13 ->
        {trace_id, span_id, _trace_flags, _trace_state, parent_span_id, name, kind, start_time,
         end_time, attributes, events, links, status} = span

        {trace_id, span_id, parent_span_id, name, kind, start_time, end_time, attributes, events,
         links, status, true}

      _ ->
        nil
    end
  end

  defp normalize_span(_), do: nil

  defp generation?(attributes, mapped_attrs) do
    Map.has_key?(mapped_attrs, :model) or
      has_genai_attribute?(attributes)
  end

  defp has_genai_attribute?(attributes) when is_map(attributes) do
    Enum.any?(attributes, fn {key, _value} ->
      key_str = to_string(key)
      String.starts_with?(key_str, "gen_ai.") or String.starts_with?(key_str, "llm.")
    end)
  end

  defp has_genai_attribute?(_), do: false

  defp create_trace_event(trace_id, name, attrs, start_time) do
    event = %{
      id: generate_id(),
      type: "trace-create",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body:
        %{
          id: trace_id,
          name: attrs[:trace_name] || name,
          timestamp: format_timestamp(start_time)
        }
        |> maybe_put(:userId, attrs[:user_id])
        |> maybe_put(:sessionId, attrs[:session_id])
        |> maybe_put(:metadata, attrs[:trace_metadata])
        |> maybe_put(:tags, attrs[:tags])
        |> maybe_put(:public, attrs[:public])
        |> maybe_put(:input, attrs[:trace_input])
        |> maybe_put(:output, attrs[:trace_output])
        |> maybe_put(:version, attrs[:version])
        |> maybe_put(:release, attrs[:release])
        |> maybe_put(:environment, attrs[:environment] || Langfuse.Config.get(:environment))
    }

    Ingestion.enqueue(event)
  end

  defp create_span_event(
         trace_id,
         span_id,
         parent_span_id,
         name,
         attrs,
         start_time,
         end_time,
         status
       ) do
    {level, status_message} = map_status(status)

    event = %{
      id: generate_id(),
      type: "span-create",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body:
        %{
          id: span_id,
          traceId: trace_id,
          name: name,
          startTime: format_timestamp(start_time)
        }
        |> maybe_put(
          :parentObservationId,
          if(parent_span_id != "0000000000000000", do: parent_span_id)
        )
        |> maybe_put(:endTime, format_timestamp(end_time))
        |> maybe_put(:input, attrs[:input])
        |> maybe_put(:output, attrs[:output])
        |> maybe_put(:metadata, attrs[:metadata])
        |> maybe_put(:level, level)
        |> maybe_put(:statusMessage, status_message || attrs[:status_message])
        |> maybe_put(:version, attrs[:version])
        |> maybe_put(:environment, attrs[:environment] || Langfuse.Config.get(:environment))
    }

    Ingestion.enqueue(event)
  end

  defp create_generation_event(
         trace_id,
         span_id,
         parent_span_id,
         name,
         attrs,
         start_time,
         end_time,
         status
       ) do
    {level, status_message} = map_status(status)

    event = %{
      id: generate_id(),
      type: "generation-create",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      body:
        %{
          id: span_id,
          traceId: trace_id,
          name: name,
          startTime: format_timestamp(start_time)
        }
        |> maybe_put(
          :parentObservationId,
          if(parent_span_id != "0000000000000000", do: parent_span_id)
        )
        |> maybe_put(:endTime, format_timestamp(end_time))
        |> maybe_put(:model, attrs[:model])
        |> maybe_put(:modelParameters, attrs[:model_parameters])
        |> maybe_put(:input, attrs[:input])
        |> maybe_put(:output, attrs[:output])
        |> maybe_put(:usage, format_usage(attrs[:usage]))
        |> maybe_put(:metadata, attrs[:metadata])
        |> maybe_put(:level, level)
        |> maybe_put(:statusMessage, status_message || attrs[:status_message])
        |> maybe_put(:promptName, attrs[:prompt_name])
        |> maybe_put(:promptVersion, attrs[:prompt_version])
        |> maybe_put(:completionStartTime, attrs[:completion_start_time])
        |> maybe_put(:version, attrs[:version])
        |> maybe_put(:environment, attrs[:environment] || Langfuse.Config.get(:environment))
    }

    Ingestion.enqueue(event)
  end

  defp map_status({:status, :unset, _}), do: {nil, nil}
  defp map_status({:status, :ok, _}), do: {nil, nil}
  defp map_status({:status, :error, message}), do: {"ERROR", to_string(message)}
  defp map_status(:undefined), do: {nil, nil}
  defp map_status(nil), do: {nil, nil}
  defp map_status(_), do: {nil, nil}

  defp format_usage(nil), do: nil

  defp format_usage(usage) when is_map(usage) do
    usage
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
    |> case do
      empty when map_size(empty) == 0 -> nil
      usage_map -> usage_map
    end
  end

  defp format_trace_id(trace_id) when is_integer(trace_id) do
    trace_id
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(32, "0")
  end

  defp format_trace_id(_), do: generate_id() <> generate_id()

  defp format_span_id(span_id) when is_integer(span_id) and span_id > 0 do
    span_id
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(16, "0")
  end

  defp format_span_id(_), do: nil

  defp format_timestamp(nil), do: nil

  defp format_timestamp(timestamp) when is_integer(timestamp) do
    timestamp
    |> DateTime.from_unix!(:nanosecond)
    |> DateTime.to_iso8601()
  end

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, val) when val == %{}, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
