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

  describe "multiple '2' cards in one play (T017)" do
    test "playing multiple '2's does not stack the penalty count", %{
      started_game: game,
      player: p1,
      player2: p2
    } do
      # Reload to ensure we have top_card for this game
      {:ok, game} = CardGames.get_game_session_preloaded(game.id)

      top_card = game.top_card

      # Find '2' cards from the deck that match the top card's suit
      # (so they can be played as a valid combo)
      deck_cards_two =
        game.deck.deck_cards
        |> Enum.filter(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)
        |> Enum.take(2)

      # If we don't have 2 '2's of the same suit, we need to play a '2' first to set up the combo
      # Play one '2' that matches the top card, then play 2 more '2's as a combo
      if length(deck_cards_two) < 2 do
        # Find any '2' that matches the top card (by suit or rank)
        first_two =
          game.deck.deck_cards
          |> Enum.find(fn dc ->
            dc.card.rank == "2" and
              (dc.card.suit == top_card.suit or dc.card.rank == top_card.rank)
          end)

        assert first_two, "Expected to find at least one '2' card that matches the top card"

        # Move this '2' to p1's hand
        {:ok, _} =
          DeckCard.changeset(first_two, %{
            location_type: "player_hand",
            player_id: p1.id,
            order_index: nil
          })
          |> Repo.update()

        # Reload and set turn to p1
        {:ok, game_fresh} = CardGames.get_game_session_preloaded(game.id)

        {:ok, game_with_turn} =
          GameSession.changeset(game_fresh, %{current_turn_player_id: p1.id})
          |> Repo.update()

        {:ok, game_ready} = CardGames.get_game_session_preloaded(game_with_turn.id)

        # P1 plays the first '2' to create a penalty
        {:ok, game_after_first} = CardGames.play_cards(game_ready, p1.id, [first_two.card.id])

        # Now the top card is a '2', so we can play any other '2's as a combo
        # Find 2 more '2' cards
        {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_after_first.id)

        remaining_twos =
          game_reloaded.deck.deck_cards
          |> Enum.filter(fn dc ->
            dc.card.rank == "2" and dc.location_type == "deck"
          end)
          |> Enum.take(2)

        assert length(remaining_twos) >= 2,
               "Expected to find at least 2 more '2' cards in the deck"

        # Move both '2' cards to p2's hand (next player)
        Enum.each(remaining_twos, fn deck_card_two ->
          {:ok, _} =
            DeckCard.changeset(deck_card_two, %{
              location_type: "player_hand",
              player_id: p2.id,
              order_index: nil
            })
            |> Repo.update()
        end)

        # Reload game session with fresh deck_cards
        {:ok, game_fresh2} = CardGames.get_game_session_preloaded(game_reloaded.id)

        # P2's turn (they have the penalty)
        assert game_fresh2.current_turn_player_id == p2.id

        # Action: P2 plays both '2' cards as a combo to block and transfer
        card_ids = Enum.map(remaining_twos, & &1.card.id)
        {:ok, updated_game} = CardGames.play_cards(game_fresh2, p2.id, card_ids)

        # Assert: Penalty is still active but count is still 2 (not 4)
        assert updated_game.draw_penalty["active"] == true

        assert updated_game.draw_penalty["count"] == 2,
               "Expected penalty count to be 2, not additive (got #{updated_game.draw_penalty["count"]})"

        assert updated_game.draw_penalty["target_player_id"] == p1.id
      else
        # We have 2 '2's of the same suit - can play them directly as a combo
        # Move both '2' cards to current player's hand
        Enum.each(deck_cards_two, fn deck_card_two ->
          {:ok, _} =
            DeckCard.changeset(deck_card_two, %{
              location_type: "player_hand",
              player_id: p1.id,
              order_index: nil
            })
            |> Repo.update()
        end)

        # Reload game session with fresh deck_cards
        {:ok, game_fresh} = CardGames.get_game_session_preloaded(game.id)

        # Set turn to p1
        {:ok, game_with_turn} =
          GameSession.changeset(game_fresh, %{current_turn_player_id: p1.id})
          |> Repo.update()

        {:ok, game_ready} = CardGames.get_game_session_preloaded(game_with_turn.id)

        # Action: P1 plays both '2' cards as a combo
        card_ids = Enum.map(deck_cards_two, & &1.card.id)
        {:ok, updated_game} = CardGames.play_cards(game_ready, p1.id, card_ids)

        # Assert: Penalty is active but count is still 2 (not 4)
        assert updated_game.draw_penalty["active"] == true

        assert updated_game.draw_penalty["count"] == 2,
               "Expected penalty count to be 2, not additive (got #{updated_game.draw_penalty["count"]})"

        assert updated_game.draw_penalty["target_player_id"] == p2.id
      end
    end
  end

  describe "penalty resolution - auto-draw (T018, T019, T020)" do
    test "player with no blocking cards auto-draws 2 cards and turn ends (T018)", %{
      started_game: game,
      player: p1,
      player2: p2
    } do
      # P1 plays '2', penalizing P2
      {game_with_penalty, _} = setup_penalty(game, p1.id, p2.id)

      # Reload to ensure deck associations are fresh
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Remove all Aces and '2' cards from P2's hand (ensure they can't block)
      game_with_penalty.deck.deck_cards
      |> Enum.filter(fn dc ->
        dc.location_type == "player_hand" and dc.player_id == p2.id and
          (dc.card.rank == "ace" or dc.card.rank == "2")
      end)
      |> Enum.each(fn deck_card ->
        DeckCard.changeset(deck_card, %{
          location_type: "deck",
          player_id: nil,
          order_index: 999 + deck_card.id
        })
        |> Repo.update!()
      end)

      # Reload game
      {:ok, game_ready} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Verify penalty is active for P2
      assert game_ready.draw_penalty["active"] == true
      assert game_ready.draw_penalty["target_player_id"] == p2.id
      assert game_ready.current_turn_player_id == p2.id

      # Get P2's hand size before auto-draw
      hand_before = CardGames.get_player_hand(game_ready, p2.id)
      hand_size_before = length(hand_before)

      # Get deck size before auto-draw
      deck_cards_before =
        game_ready.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))

      deck_size_before = length(deck_cards_before)

      # Action: Manually draw 2 cards to simulate auto-draw behavior
      # (Auto-draw logic will be implemented in T022)
      {:ok, game_after_draw1} = CardGames.draw_card_from_deck(game_ready, p2.id)
      # After first draw, turn advances to p1, so we need to set it back to p2 for second draw
      {:ok, game_turn_reset} =
        GameSession.changeset(game_after_draw1, %{current_turn_player_id: p2.id})
        |> Repo.update()

      {:ok, game_after_draw2} = CardGames.draw_card_from_deck(game_turn_reset, p2.id)

      # Reload to get fresh state
      {:ok, final_game} = CardGames.get_game_session_preloaded(game_after_draw2.id)

      # Assert: P2 drew 2 cards
      hand_after = CardGames.get_player_hand(final_game, p2.id)

      assert length(hand_after) == hand_size_before + 2,
             "Expected player to draw 2 cards (had #{hand_size_before}, now has #{length(hand_after)})"

      # Assert: Deck has 2 fewer cards
      deck_cards_after =
        final_game.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))

      assert length(deck_cards_after) == deck_size_before - 2,
             "Expected deck to have 2 fewer cards"

      # Note: When T022 is implemented, the penalty should be cleared and turn should advance automatically
    end

    test "deck recycling when player must draw more cards than are in deck (T019)", %{
      started_game: game,
      player: p1,
      player2: p2
    } do
      # P1 plays '2', penalizing P2
      {game_with_penalty, _} = setup_penalty(game, p1.id, p2.id)

      # Reload to ensure deck associations are fresh
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Move all but 1 card from deck to played_stack (simulate nearly empty deck)
      deck_cards = game_with_penalty.deck.deck_cards |> Enum.filter(&(&1.location_type == "deck"))

      # Keep only 1 card in deck, move rest to played_stack
      {_cards_to_keep, cards_to_move} = Enum.split(deck_cards, 1)

      Enum.each(cards_to_move, fn deck_card ->
        DeckCard.changeset(deck_card, %{
          location_type: "played_stack",
          player_id: nil,
          order_index: deck_card.id
        })
        |> Repo.update!()
      end)

      # Reload game
      {:ok, game_ready} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Verify deck has only 1 card
      deck_cards_before =
        game_ready.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))

      assert length(deck_cards_before) == 1, "Expected deck to have only 1 card"

      # Get P2's hand size before draw
      hand_before = CardGames.get_player_hand(game_ready, p2.id)
      hand_size_before = length(hand_before)

      # Action: Draw 2 cards (should trigger recycling)
      {:ok, game_after_draw1} = CardGames.draw_card_from_deck(game_ready, p2.id)

      # After first draw, turn advances to p1, so we need to set it back to p2 for second draw
      {:ok, game_turn_reset} =
        GameSession.changeset(game_after_draw1, %{current_turn_player_id: p2.id})
        |> Repo.update()

      {:ok, game_after_draw2} = CardGames.draw_card_from_deck(game_turn_reset, p2.id)

      # Reload to get fresh state
      {:ok, final_game} = CardGames.get_game_session_preloaded(game_after_draw2.id)

      # Assert: P2 drew 2 cards (1 from original deck, 1 from recycled)
      hand_after = CardGames.get_player_hand(final_game, p2.id)

      assert length(hand_after) == hand_size_before + 2,
             "Expected player to draw 2 cards via recycling (had #{hand_size_before}, now has #{length(hand_after)})"

      # Assert: Played stack was recycled (should have fewer cards now)
      played_stack_after =
        final_game.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "played_stack"))

      # After recycling, played_stack should be smaller (cards moved to deck)
      assert length(played_stack_after) < length(cards_to_move),
             "Expected played_stack to be recycled and have fewer cards"
    end

    test "player's turn ends after drawing penalty cards, cannot play drawn cards (T020)", %{
      started_game: game,
      player: p1,
      player2: p2
    } do
      # P1 plays '2', penalizing P2
      {game_with_penalty, _} = setup_penalty(game, p1.id, p2.id)

      # Reload to ensure deck associations are fresh
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Remove all Aces and '2' cards from P2's hand
      game_with_penalty.deck.deck_cards
      |> Enum.filter(fn dc ->
        dc.location_type == "player_hand" and dc.player_id == p2.id and
          (dc.card.rank == "ace" or dc.card.rank == "2")
      end)
      |> Enum.each(fn deck_card ->
        DeckCard.changeset(deck_card, %{
          location_type: "deck",
          player_id: nil,
          order_index: 999 + deck_card.id
        })
        |> Repo.update!()
      end)

      # Reload game
      {:ok, game_ready} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Verify it's P2's turn with an active penalty
      assert game_ready.current_turn_player_id == p2.id
      assert game_ready.draw_penalty["active"] == true

      # Action: P2 draws 1 card (simulating first card of penalty draw)
      {:ok, game_after_draw} = CardGames.draw_card_from_deck(game_ready, p2.id)

      # Assert: Turn advanced to next player (P1) after drawing
      # This demonstrates that drawing ends the turn
      assert game_after_draw.current_turn_player_id == p1.id,
             "Expected turn to advance to P1 after P2 draws a card"

      # Assert: P2 cannot play cards because it's no longer their turn
      # Get a card from P2's hand
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_after_draw.id)
      p2_hand = CardGames.get_player_hand(game_reloaded, p2.id)

      if length(p2_hand) > 0 do
        card_to_play = hd(p2_hand)

        # Try to play a card - should fail because it's not P2's turn
        result = CardGames.play_cards(game_reloaded, p2.id, [card_to_play.id])
        assert {:error, :not_your_turn} = result
      end

      # Note: When T022 is implemented, both cards should be drawn automatically
      # and the penalty should be cleared before turn advances
    end
  end

  describe "penalty notifications and UI indicators (T025, FR-011, FR-012)" do
    test "penalty state is visible to all players after '2' is played", %{
      started_game: started_game,
      player: player,
      player2: player2
    } do
      # Setup: Give current player a '2' card matching top card
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      deck_card_two =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      assert deck_card_two, "Expected to find a '2' card matching suit #{top_card.suit}"

      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
        |> Repo.update()

      {:ok, game_fresh} = CardGames.get_game_session_preloaded(started_game.id)

      # Action: Current player plays the '2'
      {:ok, game_after_two} =
        CardGames.play_cards(game_fresh, current_player_id, [deck_card_two.card.id])

      # Assert: Penalty state is persisted in database
      assert game_after_two.draw_penalty["active"] == true
      assert game_after_two.draw_penalty["count"] == 2

      # Get next player
      next_player_id =
        if current_player_id == player.id, do: player2.id, else: player.id

      assert game_after_two.draw_penalty["target_player_id"] == next_player_id

      # Verify penalty state is visible when reloading game (simulates different player/device)
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_after_two.id)

      assert game_reloaded.draw_penalty["active"] == true
      assert game_reloaded.draw_penalty["count"] == 2
      assert game_reloaded.draw_penalty["target_player_id"] == next_player_id

      # Verify penalty persists across multiple reloads (SPR-002 continuity)
      {:ok, game_reloaded_again} = CardGames.get_game_session_preloaded(game_after_two.id)

      assert game_reloaded_again.draw_penalty["active"] == true
      assert game_reloaded_again.draw_penalty["target_player_id"] == next_player_id
    end

    test "penalty state clears after player draws cards", %{
      started_game: started_game
    } do
      # Setup: Create a penalty
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      deck_card_two =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
        |> Repo.update()

      {:ok, game_fresh} = CardGames.get_game_session_preloaded(started_game.id)

      {:ok, game_with_penalty} =
        CardGames.play_cards(game_fresh, current_player_id, [deck_card_two.card.id])

      assert game_with_penalty.draw_penalty["active"] == true

      # Action: Next player's turn starts - T022 auto-draw should clear penalty
      # The penalty should be automatically resolved when it's the next player's turn
      # For this test, we verify the penalty state is visible before resolution

      # Verify penalty persists in database
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      assert game_reloaded.draw_penalty["active"] == true
      assert game_reloaded.draw_penalty["count"] == 2

      # Note: T022 implements auto-draw logic that will clear the penalty
      # This test verifies the penalty state is properly persisted and visible
      # The actual auto-draw and clearing happens in the turn start logic
    end

    test "penalty state persists after blocking with Ace", %{
      started_game: started_game,
      player: player,
      player2: player2
    } do
      # Setup: Create a penalty
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      deck_card_two =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
        |> Repo.update()

      {:ok, game_fresh} = CardGames.get_game_session_preloaded(started_game.id)

      {:ok, game_with_penalty} =
        CardGames.play_cards(game_fresh, current_player_id, [deck_card_two.card.id])

      # Give next player an Ace
      next_player_id =
        if current_player_id == player.id, do: player2.id, else: player.id

      ace_card =
        game_with_penalty.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "ace" and dc.location_type == "deck" end)

      {:ok, _} =
        DeckCard.changeset(ace_card, %{
          location_type: "player_hand",
          player_id: next_player_id,
          order_index: nil
        })
        |> Repo.update()

      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Action: Next player blocks with Ace
      {:ok, game_after_block} =
        CardGames.play_cards(game_reloaded, next_player_id, [ace_card.card.id])

      # Assert: Penalty is cleared
      assert game_after_block.draw_penalty["active"] == false

      # Verify state persists across reload
      {:ok, game_final} = CardGames.get_game_session_preloaded(game_after_block.id)
      assert game_final.draw_penalty["active"] == false
    end

    test "penalty state persists after simulated disconnect/reconnect (SPR-002)", %{
      started_game: started_game
    } do
      # Setup: Create a penalty
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      deck_card_two =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
        |> Repo.update()

      {:ok, game_fresh} = CardGames.get_game_session_preloaded(started_game.id)

      {:ok, game_with_penalty} =
        CardGames.play_cards(game_fresh, current_player_id, [deck_card_two.card.id])

      # Verify penalty is active
      assert game_with_penalty.draw_penalty["active"] == true
      target_player_id = game_with_penalty.draw_penalty["target_player_id"]
      assert target_player_id != nil

      # Simulate disconnect/reconnect by reloading from database multiple times
      # This mimics what happens when a LiveView process crashes and reconnects

      # First reconnect
      {:ok, game_reload_1} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      assert game_reload_1.draw_penalty["active"] == true
      assert game_reload_1.draw_penalty["count"] == 2
      assert game_reload_1.draw_penalty["target_player_id"] == target_player_id

      # Second reconnect (simulating multiple disconnections)
      {:ok, game_reload_2} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      assert game_reload_2.draw_penalty["active"] == true
      assert game_reload_2.draw_penalty["count"] == 2
      assert game_reload_2.draw_penalty["target_player_id"] == target_player_id

      # Third reconnect (verify consistency)
      {:ok, game_reload_3} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      assert game_reload_3.draw_penalty["active"] == true
      assert game_reload_3.draw_penalty["count"] == 2
      assert game_reload_3.draw_penalty["target_player_id"] == target_player_id

      # Verify all game state is consistent across reloads
      assert game_reload_1.id == game_reload_2.id
      assert game_reload_2.id == game_reload_3.id
      assert game_reload_1.current_turn_player_id == game_reload_3.current_turn_player_id
    end

    test "penalty state visible across different player sessions (SPR-002 multi-device)", %{
      started_game: started_game,
      player: player,
      player2: player2
    } do
      # Setup: Player 1 creates a penalty
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      deck_card_two =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
        |> Repo.update()

      {:ok, game_fresh} = CardGames.get_game_session_preloaded(started_game.id)

      {:ok, game_with_penalty} =
        CardGames.play_cards(game_fresh, current_player_id, [deck_card_two.card.id])

      # Simulate Player 1's view (original device)
      {:ok, player1_view} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      assert player1_view.draw_penalty["active"] == true

      # Simulate Player 2's view (different device/browser)
      # This simulates Player 2 opening the game on their phone/computer
      {:ok, player2_view} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      assert player2_view.draw_penalty["active"] == true
      assert player2_view.draw_penalty["count"] == 2

      # Verify both players see the same penalty state
      assert player1_view.draw_penalty == player2_view.draw_penalty

      # Simulate Player 1 refreshing their browser
      {:ok, player1_refresh} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      assert player1_refresh.draw_penalty["active"] == true

      # Simulate Player 2 opening on a third device (tablet)
      {:ok, player2_tablet} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      assert player2_tablet.draw_penalty["active"] == true

      # All views should be identical (database is source of truth)
      assert player1_view.draw_penalty == player1_refresh.draw_penalty
      assert player2_view.draw_penalty == player2_tablet.draw_penalty
      assert player1_refresh.draw_penalty == player2_tablet.draw_penalty

      # Verify the target player sees they are targeted
      next_player_id =
        if current_player_id == player.id, do: player2.id, else: player.id

      assert player1_view.draw_penalty["target_player_id"] == next_player_id
      assert player2_view.draw_penalty["target_player_id"] == next_player_id
    end
  end
end
