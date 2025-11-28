defmodule Langfuse.SessionTest do
  use ExUnit.Case, async: true

  alias Langfuse.Session

  describe "new_id/0" do
    test "generates a unique session ID" do
      id1 = Session.new_id()
      id2 = Session.new_id()

      assert String.starts_with?(id1, "session_")
      assert String.starts_with?(id2, "session_")
      assert id1 != id2
    end

    test "generates IDs with expected format" do
      id = Session.new_id()

      assert String.length(id) == 32
    end
  end

  describe "start/1" do
    test "creates a session with auto-generated ID" do
      session = Session.start()

      assert String.starts_with?(session.id, "session_")
      assert %DateTime{} = session.created_at
      assert session.metadata == nil
    end

    test "creates a session with custom ID" do
      session = Session.start(id: "my-session-123")

      assert session.id == "my-session-123"
    end

    test "creates a session with metadata" do
      session = Session.start(metadata: %{user_type: "premium"})

      assert session.metadata == %{user_type: "premium"}
    end
  end

  describe "get_id/1" do
    test "returns ID from session struct" do
      session = Session.start(id: "session-123")

      assert Session.get_id(session) == "session-123"
    end

    test "returns string ID as-is" do
      assert Session.get_id("session-456") == "session-456"
    end
  end

  describe "score/2" do
    test "scores a session by struct" do
      session = Session.start(id: "session-123")
      result = Session.score(session, name: "satisfaction", value: 4.5)

      assert result == :ok
    end

    test "scores a session by ID string" do
      result = Session.score("session-123", name: "satisfaction", value: 4.5)

      assert result == :ok
    end

    test "scores a session with categorical value" do
      result =
        Session.score("session-123",
          name: "outcome",
          string_value: "converted",
          data_type: :categorical
        )

      assert result == :ok
    end

    test "scores a session with boolean value" do
      result =
        Session.score("session-123",
          name: "goal_achieved",
          value: true,
          data_type: :boolean
        )

      assert result == :ok
    end

    test "scores a session with comment" do
      result =
        Session.score("session-123",
          name: "feedback",
          value: 5,
          comment: "Great experience"
        )

      assert result == :ok
    end
  end
end
