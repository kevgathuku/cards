defmodule Games.Kadi.FSMServerTest do
  use ExUnit.Case, async: true
  import Finitomata.ExUnit
  import Mox

  alias Games.Kadi.FsmServer
  alias Games.Kadi.Player

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

    @tag :skip
    test "start with bogus config", ctx do
      assert_transition ctx, {:start, %{obviously_this_is_invalid: 67}} do
        :lobby ->
          # TODO: Figure out a way to test the map keys
          assert_payload do
            rules.obviously_this_is_invalid ~> true
          end
      end
    end

    test_path "adding players by name", _ctx do
      {:start, %{min_players: 2}} ->
        assert_state :lobby do
          assert_payload(%{
            rules: %{min_players: 2}
          })
        end

      {:add_player, "Kevin"} ->
        assert_state :lobby do
          assert_payload(%{
            players: [%Player{name: "Kevin", cards: []}]
          })
        end

      {:add_player, "Devin"} ->
        assert_state :awaiting_deck do
          assert_payload(%{
            players: [%Player{name: "Kevin", cards: []}, %Player{name: "Devin", cards: []}]
          })
        end
    end
  end
end
