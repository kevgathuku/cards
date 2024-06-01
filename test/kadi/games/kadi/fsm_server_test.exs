defmodule Kadi.Games.Poker.FSMServerTest do
  use ExUnit.Case, async: true
  import Finitomata.ExUnit
  import Mox

  alias Kadi.Games.Poker.FsmServer
  alias Kadi.Games.Poker.Player
  alias Kadi.Games.Poker.Card

  describe "Server FSM tests" do
    setup_finitomata do
      [
        fsm: [implementation: FsmServer, payload: %{}],
        context: [
          deck: [
            # P1
            %Card{suit: :hearts, number: :two},
            %Card{suit: :hearts, number: :eight},
            %Card{suit: :flowers, number: :eight},
            %Card{suit: :flowers, number: :six},
            # P2
            %Card{suit: :diamonds, number: :eight},
            %Card{suit: :diamonds, number: :six},
            %Card{suit: :diamonds, number: :five},
            %Card{suit: :flowers, number: :five},
            # Start
            %Card{suit: :spades, number: :eight},
            %Card{suit: :spades, number: :four}
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
            players: []
          })
      end
    end

    test "start with bogus config", ctx do
      assert_transition ctx, {:start, %{obviously_this_is_invalid: 67}} do
        :lobby ->
          assert_payload do
            deck ~> []
            played ~> []
            players ~> []
            player_turn ~> 0
          end
      end
    end

    test_path "adding players by name", _ctx do
      {:start, %{}} ->
        assert_state :lobby do
          assert_payload do
            players ~> []
          end
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

    test_path "with custom deck", %{deck: init_deck} = _ctx do
      {:start, %{}} ->
        assert_state :lobby do
          assert_payload do
            players ~> []
          end
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

      {:deal_player_cards, %{}} ->
        assert_state :awaiting_start_card do
          assert_payload(%{
            players: [
              %Player{
                name: "Kevin",
                cards: [
                  %Card{suit: :hearts, number: :two},
                  %Card{suit: :hearts, number: :eight},
                  %Card{suit: :flowers, number: :eight},
                  %Card{suit: :flowers, number: :six}
                ]
              },
              %Player{
                name: "Devin",
                cards: [
                  %Card{suit: :diamonds, number: :eight},
                  %Card{suit: :diamonds, number: :six},
                  %Card{suit: :diamonds, number: :five},
                  %Card{suit: :flowers, number: :five}
                ]
              }
            ],
            deck: [
              %Card{suit: :spades, number: :eight},
              %Card{suit: :spades, number: :four}
            ]
          })
        end

      {:deal_start_card, %{}} ->
        assert_state :live do
          # 8 is not a valid start card. Chooses the next card (4) instead
          assert_payload(%{
            deck: [
              %Card{suit: :spades, number: :eight}
            ],
            played: [
              %Card{suit: :spades, number: :four}
            ]
          })
        end

      {:pick, %{}} ->
        assert_state :live do
          assert_payload(%{
            # Reduce deck by one
            deck: [],
            # No added played cards
            played: [
              %Card{suit: :spades, number: :four}
            ],
            # Next player's turn
            player_turn: 1,
            players: [
              # Picked card added here...
              %Player{
                name: "Kevin",
                cards: [
                  %Card{suit: :hearts, number: :two},
                  %Card{suit: :hearts, number: :eight},
                  %Card{suit: :flowers, number: :eight},
                  %Card{suit: :flowers, number: :six},
                  %Card{suit: :spades, number: :eight},
                ]
              },
              %Player{
                name: "Devin",
                cards: [
                  %Card{suit: :diamonds, number: :eight},
                  %Card{suit: :diamonds, number: :six},
                  %Card{suit: :diamonds, number: :five},
                  %Card{suit: :flowers, number: :five}
                ]
              }
            ]
          })
        end

      {:play_hand, [%Card{suit: :flowers, number: :ten}]} ->
        # Devin's turn: Play invalid card -> back to live
        # No changes to any player's cards
        assert_state :live do
          assert_payload(%{
            # No added played cards
            played: [
              %Card{suit: :spades, number: :four}
            ],
            # Same player's turn
            player_turn: 1,
            # Same cards
            players: [
              %Player{
                name: "Kevin",
                cards: [
                  %Card{suit: :hearts, number: :two},
                  %Card{suit: :hearts, number: :eight},
                  %Card{suit: :flowers, number: :eight},
                  %Card{suit: :flowers, number: :six},
                  %Card{suit: :spades, number: :eight},
                ]
              },
              %Player{
                name: "Devin",
                cards: [
                  %Card{suit: :diamonds, number: :eight},
                  %Card{suit: :diamonds, number: :six},
                  %Card{suit: :diamonds, number: :five},
                  %Card{suit: :flowers, number: :five}
                ]
              }
            ]
          })
        end
    end
  end
end
