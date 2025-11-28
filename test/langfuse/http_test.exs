defmodule Langfuse.HTTPTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  describe "auth_check/0 with mock" do
    test "mock returns true when configured to succeed" do
      expect(Langfuse.HTTPMock, :auth_check, fn ->
        true
      end)

      assert Langfuse.HTTPMock.auth_check() == true
    end

    test "mock returns false when configured to fail" do
      expect(Langfuse.HTTPMock, :auth_check, fn ->
        false
      end)

      assert Langfuse.HTTPMock.auth_check() == false
    end
  end

  describe "auth_check/0 module integration" do
    test "auth_check function exists and returns boolean" do
      result = Langfuse.HTTP.auth_check()
      assert is_boolean(result)
    end
  end
end
