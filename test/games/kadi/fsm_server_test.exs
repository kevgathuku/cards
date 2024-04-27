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

    test "start with no args", ctx do
      assert_transition ctx, {:start, %{}} do
        :lobby ->
          assert_payload(%{
            deck: [],
            played: [],
            player_turn: 0,
            players: [],
            rules: %{cards_to_deal: 4}
          })
      end
    end

    test "start with custom config", ctx do
      assert_transition ctx, {:start, %{cards_to_deal: 2, min_players: 3}} do
        :lobby ->
          assert_payload(%{
            deck: [],
            played: [],
            player_turn: 0,
            players: [],
            rules: %{cards_to_deal: 2, min_players: 3}
          })
      end
    end
  end
end
