defmodule Langfuse.Instrumentation do
  @moduledoc """
  Macros for automatic function tracing in Langfuse.

  This module provides declarative instrumentation for tracing function
  calls without modifying function bodies. Use these macros to automatically
  capture inputs, outputs, timing, and errors.

  ## Using `@observe`

  The `@observe` attribute marks functions for automatic tracing:

      defmodule MyApp.Pipeline do
        use Langfuse.Instrumentation

        @observe name: "fetch-data"
        def fetch_data(query) do
          # Function body - automatically traced
          {:ok, results}
        end

        @observe as_type: :generation, model: "gpt-4"
        def call_llm(messages) do
          # LLM call - traced as generation
          {:ok, response}
        end
      end

  ## Using `with_trace/2`

  For ad-hoc tracing of code blocks:

      with_trace "process-request", user_id: user.id do
        # Code block is traced
        process(request)
      end

  ## Options

    * `:name` - Custom name for the observation (defaults to function name)
    * `:as_type` - Observation type: `:span` (default) or `:generation`
    * `:capture_input` - Whether to capture function arguments (default: true)
    * `:capture_output` - Whether to capture return value (default: true)
    * `:model` - Model name (for generations)
    * `:metadata` - Static metadata to include

  """

  @doc """
  Enables instrumentation macros in the using module.

  ## Example

      defmodule MyApp.Service do
        use Langfuse.Instrumentation

        @observe name: "my-operation"
        def my_function(arg), do: process(arg)
      end

  """
  defmacro __using__(_opts) do
    quote do
      import Langfuse.Instrumentation, only: [with_trace: 2, with_trace: 3]
      Module.register_attribute(__MODULE__, :observe, accumulate: false)
      @on_definition Langfuse.Instrumentation
      @before_compile Langfuse.Instrumentation
    end
  end

  @doc false
  def __on_definition__(env, kind, name, args, _guards, _body) when kind in [:def, :defp] do
    case Module.get_attribute(env.module, :observe) do
      nil ->
        :ok

      opts ->
        observed = Module.get_attribute(env.module, :langfuse_observed) || []
        arity = length(args)
        entry = {name, arity, opts}
        Module.put_attribute(env.module, :langfuse_observed, [entry | observed])
        Module.delete_attribute(env.module, :observe)
    end
  end

  def __on_definition__(_env, _kind, _name, _args, _guards, _body), do: :ok

  @doc false
  defmacro __before_compile__(env) do
    observed = Module.get_attribute(env.module, :langfuse_observed) || []

    overrides =
      for {name, arity, opts} <- observed do
        generate_wrapper(name, arity, opts)
      end

    quote do
      unquote_splicing(overrides)
    end
  end

  defp generate_wrapper(name, arity, opts) do
    args = Macro.generate_arguments(arity, __MODULE__)
    obs_name = Keyword.get(opts, :name, Atom.to_string(name))
    as_type = Keyword.get(opts, :as_type, :span)
    capture_input = Keyword.get(opts, :capture_input, true)
    capture_output = Keyword.get(opts, :capture_output, true)
    model = Keyword.get(opts, :model)
    metadata = Keyword.get(opts, :metadata, %{})

    quote do
      defoverridable [{unquote(name), unquote(arity)}]

      def unquote(name)(unquote_splicing(args)) do
        input =
          if unquote(capture_input) do
            unquote(args) |> Enum.with_index() |> Map.new(fn {v, i} -> {"arg#{i}", v} end)
          else
            nil
          end

        trace = Langfuse.trace(name: unquote(obs_name), metadata: unquote(Macro.escape(metadata)))

        observation =
          case unquote(as_type) do
            :generation ->
              Langfuse.generation(trace,
                name: unquote(obs_name),
                model: unquote(model),
                input: input,
                metadata: unquote(Macro.escape(metadata))
              )

            _ ->
              Langfuse.span(trace,
                name: unquote(obs_name),
                input: input,
                metadata: unquote(Macro.escape(metadata))
              )
          end

        try do
          result = super(unquote_splicing(args))

          output = if unquote(capture_output), do: result, else: nil

          Langfuse.update(observation, output: output)
          Langfuse.end_observation(observation)

          result
        rescue
          e ->
            Langfuse.update(observation,
              level: :error,
              status_message: Exception.message(e)
            )

            Langfuse.end_observation(observation)
            reraise e, __STACKTRACE__
        end
      end
    end
  end

  @doc """
  Traces a code block with a new trace and span.

  Creates a trace with the given name and executes the block within a span.
  The span automatically captures the block's return value and timing.

  ## Options

    * `:user_id` - User identifier for the trace
    * `:session_id` - Session identifier for the trace
    * `:metadata` - Additional metadata
    * `:tags` - Tags for categorization

  ## Examples

      result = with_trace "process-request" do
        fetch_and_process(data)
      end

      result = with_trace "user-action", user_id: current_user.id do
        perform_action(params)
      end

  """
  defmacro with_trace(name, do: block) do
    quote do
      with_trace(unquote(name), [], do: unquote(block))
    end
  end

  defmacro with_trace(name, opts, do: block) do
    quote do
      trace_opts =
        [name: unquote(name)]
        |> Keyword.merge(unquote(opts))

      trace = Langfuse.trace(trace_opts)
      span = Langfuse.span(trace, name: unquote(name))

      try do
        result = unquote(block)
        Langfuse.update(span, output: result)
        Langfuse.end_observation(span)
        result
      rescue
        e ->
          Langfuse.update(span, level: :error, status_message: Exception.message(e))
          Langfuse.end_observation(span)
          reraise e, __STACKTRACE__
      end
    end
  end
end
