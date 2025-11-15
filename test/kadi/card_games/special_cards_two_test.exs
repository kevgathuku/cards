defmodule Kadi.CardGames.SpecialCardsTwoTest do
  use Kadi.DataCase, async: true

  alias Kadi.CardGames
  alias Kadi.Games.GameSession
  alias Kadi.Games.DeckCard

  import Kadi.AccountsFixtures

  setup do
    player = player_fixture()
    # Setup: Create a game session with two players
    player2 = player_fixture(%{email: "player2_two_test@example.com"})

    {:ok, game_session} = CardGames.create_game_session(player, %{short_code: "two-test-1"})
    {:ok, _} = CardGames.join_game_session(player2, game_session.id)

    # Start game with rank "2" excluded from dealing so we can manually add it
    {:ok, started_game} = CardGames.start_game(game_session, exclude_ranks: ["2"])
    {:ok, preloaded_started_game} = CardGames.get_game_session_preloaded(started_game)
    %{player: player, player2: player2, started_game: preloaded_started_game}
  end

  describe "playing a '2' card (T003)" do
    test "forces the next player to draw 2 cards", %{started_game: started_game} do
      # Get the top card and current player
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      # Find a '2' card from the deck that matches the top card suit
      deck_card_two =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      assert deck_card_two,
             "Expected to find a '2' card matching suit #{top_card.suit} (excluded from dealing)"

      # Move the '2' to current player's hand

      {:ok, _updated_deck_card} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session with fresh deck_cards
      {:ok, game_session_fresh} = CardGames.get_game_session_preloaded(started_game.id)

      # Get the next player
      players = CardGames.get_game_session_players(game_session_fresh.id)
      next_player = Enum.find(players, fn p -> p.id != current_player_id end)

      # Action: Current player plays the '2' (pass card ID, not struct)
      {:ok, updated_game_session} =
        CardGames.play_cards(game_session_fresh, current_player_id, [deck_card_two.card.id])

      # Assert: Game state is updated to indicate next player must draw 2 cards
      # Note: PostgreSQL :map type returns string keys, not atom keys
      assert updated_game_session.draw_penalty["active"] == true
      assert updated_game_session.draw_penalty["count"] == 2
      assert updated_game_session.draw_penalty["target_player_id"] == next_player.id
    end

    test "allows '2' as last card - player becomes cardless, penalty applies, game continues", %{
      started_game: started_game
    } do
      # Get the top card and current player
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      # Find a '2' card from the deck that matches the top card suit
      deck_card_two =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      assert deck_card_two,
             "Expected to find a '2' card matching suit #{top_card.suit} (excluded from dealing)"

      # Give current player ONLY the '2' card (empty their hand first)
      started_game.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player_id))
      |> Enum.each(fn deck_card ->
        DeckCard.changeset(deck_card, %{
          location_type: "deck",
          player_id: nil,
          order_index: 999 + deck_card.id
        })
        |> Repo.update!()
      end)

      # Move the '2' to current player's hand as their ONLY card
      {:ok, _updated_deck_card} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session with fresh deck_cards
      {:ok, game_session_fresh} = CardGames.get_game_session_preloaded(started_game.id)

      # Verify player has exactly 1 card
      player_hand = CardGames.get_player_hand(game_session_fresh, current_player_id)
      assert length(player_hand) == 1

      # Get the next player
      players = CardGames.get_game_session_players(game_session_fresh.id)
      next_player = Enum.find(players, fn p -> p.id != current_player_id end)

      # Action: Current player plays the '2' as their last card
      {:ok, updated_game_session} =
        CardGames.play_cards(game_session_fresh, current_player_id, [deck_card_two.card.id])

      # Assert: Player becomes cardless (hand is empty)
      final_hand = CardGames.get_player_hand(updated_game_session, current_player_id)
      assert length(final_hand) == 0, "Player should have empty hand after playing last card"

      # Assert: Penalty is activated for next player
      assert updated_game_session.draw_penalty["active"] == true
      assert updated_game_session.draw_penalty["count"] == 2
      assert updated_game_session.draw_penalty["target_player_id"] == next_player.id

      # Assert: Game continues (turn advanced to next player)
      assert updated_game_session.current_turn_player_id == next_player.id

      # Assert: Player entered "cardless" status (playing '2' as last card triggers cardless)
      player_session =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: updated_game_session.id,
          player_id: current_player_id
        )

      assert player_session.status == "cardless",
             "Player should enter 'cardless' status when playing '2' as last card"
    end
  end
end
