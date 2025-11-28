defmodule Langfuse.DoctestTest do
  use ExUnit.Case, async: true

  doctest Langfuse
  doctest Langfuse.Trace
  doctest Langfuse.Span
  doctest Langfuse.Generation
  doctest Langfuse.Event
  doctest Langfuse.Score
  doctest Langfuse.Session
  doctest Langfuse.Prompt
  doctest Langfuse.Telemetry
end
