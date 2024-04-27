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

    @tag :skip
    test "start with bogus config", ctx do
      assert_transition ctx, {:start, %{obviously_this_is_invalid: 67}} do
        :lobby ->
          # TODO: Find out how to test exclusion of a map key
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

    test_path "adding duplicate players", _ctx do
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

      {:add_player, "Kevin"} ->
        assert_state :lobby do
          assert_payload(%{
            players: [%Player{name: "Kevin", cards: []}]
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
        assert_state :awaiting_player_cards do
          assert_payload(%{
            deck: init_deck
          })
        end
    end
  end
end
