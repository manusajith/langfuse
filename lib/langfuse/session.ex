defmodule Langfuse.Session do
  @moduledoc """
  Session management for grouping related traces in Langfuse.

  Sessions allow you to group multiple traces together, typically representing
  a user's conversation or interaction sequence.

  ## Examples

      # Generate a new session ID
      session_id = Langfuse.Session.new_id()

      # Use session ID in traces
      trace1 = Langfuse.trace(name: "turn-1", session_id: session_id)
      trace2 = Langfuse.trace(name: "turn-2", session_id: session_id)

      # Score the entire session
      Langfuse.Session.score(session_id, name: "satisfaction", value: 4.5)

  """

  alias Langfuse.Score

  @type session_id :: String.t()

  @type t :: %__MODULE__{
          id: session_id(),
          metadata: map() | nil,
          created_at: DateTime.t()
        }

  defstruct [:id, :metadata, :created_at]

  @doc """
  Generates a new unique session ID.

  ## Examples

      iex> session_id = Langfuse.Session.new_id()
      iex> String.starts_with?(session_id, "session_")
      true

  """
  @spec new_id() :: session_id()
  def new_id do
    "session_" <> generate_id()
  end

  @doc """
  Creates a new session struct.

  ## Options

    * `:id` - Custom session ID (optional, auto-generated if not provided)
    * `:metadata` - Additional metadata map

  ## Examples

      session = Langfuse.Session.start()
      session = Langfuse.Session.start(id: "my-custom-session-id")

  """
  @spec start(keyword()) :: t()
  def start(opts \\ []) do
    %__MODULE__{
      id: opts[:id] || new_id(),
      metadata: opts[:metadata],
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Gets the session ID from a session struct or returns the string as-is.
  """
  @spec get_id(t() | session_id()) :: session_id()
  def get_id(%__MODULE__{id: id}), do: id
  def get_id(id) when is_binary(id), do: id

  @doc """
  Scores a session.

  ## Options

    * `:name` - Score name (required)
    * `:value` - Numeric value for numeric scores
    * `:string_value` - String value for categorical scores
    * `:data_type` - One of :numeric, :categorical, :boolean
    * `:comment` - Optional comment

  ## Examples

      Langfuse.Session.score("session-123", name: "satisfaction", value: 4.5)
      Langfuse.Session.score(session, name: "outcome", string_value: "converted", data_type: :categorical)

  """
  @spec score(t() | session_id(), keyword()) :: :ok | {:error, term()}
  def score(session, opts) do
    session_id = get_id(session)
    Score.score_session(session_id, opts)
  end

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
