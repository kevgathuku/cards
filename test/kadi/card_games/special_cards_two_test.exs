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

  describe "blocking a '2' penalty (T010, T011, T012)" do
    # Helper to create a '2' penalty situation
    defp setup_penalty(game_session, from_player_id, to_player_id) do
      # Reload to ensure we have top_card for this game
      {:ok, game_session} = CardGames.get_game_session_preloaded(game_session.id)

      top_card = game_session.top_card

      # Find a '2' card from the deck that can be played on the top card
      deck_card_two =
        game_session.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      assert deck_card_two,
             "Expected to find a playable '2' card (matching suit or rank of #{top_card.suit} #{top_card.rank}) in the deck"

      # Move '2' to from_player's hand

      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: from_player_id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game with all associations and set the current turn
      {:ok, game_session_fresh} = CardGames.get_game_session_preloaded(game_session.id)

      # Set turn to from_player
      {:ok, game_with_turn} =
        GameSession.changeset(game_session_fresh, %{current_turn_player_id: from_player_id})
        |> Repo.update()

      # Reload one more time to get fresh state after turn update
      {:ok, game_ready} = CardGames.get_game_session_preloaded(game_with_turn.id)

      # Player plays the '2' to create penalty
      {:ok, game_with_penalty} =
        CardGames.play_cards(game_ready, from_player_id, [deck_card_two.card.id])

      # Verify penalty is active against to_player
      assert game_with_penalty.draw_penalty["active"] == true
      assert game_with_penalty.draw_penalty["target_player_id"] == to_player_id

      {game_with_penalty, deck_card_two.card}
    end

    test "player can block with an Ace (T010)", %{started_game: game, player: p1, player2: p2} do
      # P1 plays '2', penalizing P2
      {game_with_penalty, two_card_played} = setup_penalty(game, p1.id, p2.id)

      # Reload to ensure deck associations are fresh after penalty setup
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Give P2 an Ace card
      deck_card_ace =
        game_with_penalty.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace"))

      {:ok, _} =
        DeckCard.changeset(deck_card_ace, %{
          location_type: "player_hand",
          player_id: p2.id,
          order_index: nil
        })
        |> Repo.update()

      # Action: P2 plays the Ace to block
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      {:ok, updated_game} = CardGames.play_cards(game_reloaded, p2.id, [deck_card_ace.card.id])

      # Assert: Penalty is cleared
      assert updated_game.draw_penalty["active"] == false
      assert updated_game.draw_penalty["count"] == 0
      assert updated_game.draw_penalty["target_player_id"] == nil

      # Assert: action_suit is set to the suit of the '2' that was blocked
      assert updated_game.action_suit == two_card_played.suit

      # Assert: Turn advances to the next player (P1 in a 2-player game)
      assert updated_game.current_turn_player_id == p1.id
    end

    test "player can block and transfer penalty with another '2' (T011)", %{
      started_game: game,
      player: p1,
      player2: p2
    } do
      # P1 plays '2', penalizing P2
      {game_with_penalty, _two_card_played} = setup_penalty(game, p1.id, p2.id)

      # Reload to ensure deck associations are fresh after penalty setup
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Give P2 another '2' card
      deck_card_two =
        game_with_penalty.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "2"))

      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: p2.id,
          order_index: nil
        })
        |> Repo.update()

      # Action: P2 plays the '2' to block and transfer
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      {:ok, updated_game} = CardGames.play_cards(game_reloaded, p2.id, [deck_card_two.card.id])

      # Assert: Penalty is still active
      assert updated_game.draw_penalty["active"] == true
      assert updated_game.draw_penalty["count"] == 2

      # Assert: Penalty is transferred to the next player (P1 in a 2-player game)
      assert updated_game.draw_penalty["target_player_id"] == p1.id

      # Assert: Turn advanced to next player (which is P1)
      assert updated_game.current_turn_player_id == p1.id
    end

    test "player can block and transfer penalty with another '2' in a 2-player game (T011)", %{
      started_game: game,
      player: p1,
      player2: p2
    } do
      # P1 plays '2', penalizing P2
      {game_with_penalty, _two_card_played} = setup_penalty(game, p1.id, p2.id)

      # Reload to ensure deck associations are fresh after penalty setup
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Give P2 another '2' card
      deck_card_two =
        game_with_penalty.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "2"))

      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: p2.id,
          order_index: nil
        })
        |> Repo.update()

      # Action: P2 plays the '2' to block and transfer
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      {:ok, updated_game} = CardGames.play_cards(game_reloaded, p2.id, [deck_card_two.card.id])

      # Assert: Penalty is still active
      assert updated_game.draw_penalty["active"] == true
      assert updated_game.draw_penalty["count"] == 2

      # Assert: Penalty is transferred to the next player (P1 in a 2-player game)
      assert updated_game.draw_penalty["target_player_id"] == p1.id

      # Assert: Turn advanced to next player (which is P1)
      assert updated_game.current_turn_player_id == p1.id
    end
  end

  describe "blocking a '2' penalty with three players (T012)" do
    setup do
      p1 = player_fixture(%{email: "p1_3p@example.com"})
      p2 = player_fixture(%{email: "p2_3p@example.com"})
      p3 = player_fixture(%{email: "p3_3p@example.com"})

      {:ok, game} = CardGames.create_game_session(p1, %{short_code: "three-player-2-test"})
      {:ok, _} = CardGames.join_game_session(p2, game.id)
      {:ok, _} = CardGames.join_game_session(p3, game.id)

      {:ok, started_game} = CardGames.start_game(game, exclude_ranks: ["2"])
      {:ok, started_game} = CardGames.get_game_session_preloaded(started_game.id)
      %{game: started_game, p1: p1, p2: p2, p3: p3}
    end

    test "handles multi-player penalty chain reactions (A->B->C) (T012)", %{
      game: game,
      p1: p1,
      p2: p2,
      p3: p3
    } do
      # P1 plays '2', penalizing P2
      {game_p1_played, _} = setup_penalty(game, p1.id, p2.id)

      # Reload to ensure deck associations are fresh after penalty setup
      {:ok, game_p1_played} = CardGames.get_game_session_preloaded(game_p1_played.id)

      # Give P2 another '2' card
      deck_card_p2 =
        game_p1_played.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "2"))

      {:ok, _} =
        DeckCard.changeset(deck_card_p2, %{
          location_type: "player_hand",
          player_id: p2.id,
          order_index: nil
        })
        |> Repo.update()

      # Action 1: P2 plays their '2', transferring penalty to P3
      {:ok, game_reloaded_p2} = CardGames.get_game_session_preloaded(game_p1_played.id)

      {:ok, game_p2_played} =
        CardGames.play_cards(game_reloaded_p2, p2.id, [deck_card_p2.card.id])

      # Assert: Penalty is transferred to P3
      assert game_p2_played.draw_penalty["active"] == true
      assert game_p2_played.draw_penalty["count"] == 2
      assert game_p2_played.draw_penalty["target_player_id"] == p3.id
      assert game_p2_played.current_turn_player_id == p3.id
    end
  end
end
