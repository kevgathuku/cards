defmodule Games.Kadi.FSMServerTest do
  use ExUnit.Case, async: true
  import Finitomata.ExUnit
  import Mox

  alias Games.Kadi.FsmServer
  alias Games.Kadi.Player
  alias Games.Kadi.Card

  describe "Server FSM tests" do
    setup_finitomata do
      [
        fsm: [implementation: FsmServer, payload: %{}],
        context: [
          deck: [
            %Card{suit: :hearts, number: :two},
            %Card{suit: :hearts, number: :eight},
            %Card{suit: :flowers, number: :eight},
            %Card{suit: :flowers, number: :seven},
            %Card{suit: :diamonds, number: :eight},
            %Card{suit: :diamonds, number: :six}
          ]
        ]
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

    test "start with bogus config", %{finitomata: %{fsm: fsm}} do
      Finitomata.transition(fsm.name, {:start, %{obviously_this_is_invalid: 67}})
      state = Finitomata.state(fsm.name)
      assert match?(%{payload: %{rules: %{min_players: _, cards_to_deal: _}}}, state)
      # Ensure we don't save the invalid rule
      refute match?(%{payload: %{rules: %{obviously_this_is_invalid: _}}}, state)
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

      # Does not add duplicate players
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

    test_path "adding deck", %{deck: init_deck} = _ctx do
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

      {:add_deck, %{deck: init_deck}} ->
        assert_state :awaiting_deal_cards do
          assert_payload(%{
            deck: init_deck
          })
        end

          assert_payload(%{
            deck: init_deck
          })
        end
    end
  end
end
