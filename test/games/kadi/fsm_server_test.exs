defmodule Games.Kadi.FSMServerTest do
  use ExUnit.Case, async: true
  import Finitomata.ExUnit
  import Mox

  alias Games.Kadi.FsmServer

  describe "Server FSM tests" do
    setup_finitomata do
      [
        fsm: [implementation: FsmServer, payload: %{}],
        context: []
      ]
    end

    test "start path", ctx do
      assert_transition ctx, {:start, %{cards_to_deal: 2}} do
        :lobby ->
          assert_payload(%{rules: %{cards_to_deal: 2}})
      end
    end
  end
end
