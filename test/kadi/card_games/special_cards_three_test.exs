defmodule Kadi.CardGames.SpecialCardsThreeTest do
  use Kadi.DataCase, async: true

  alias Kadi.CardGames
  alias Kadi.Games.GameSession
  alias Kadi.Games.DeckCard

  import Kadi.AccountsFixtures

  setup do
    player = player_fixture()
    # Setup: Create a game session with two players
    player2 = player_fixture(%{email: "player2_three_test@example.com"})

    {:ok, game_session} = CardGames.create_game_session(player, %{short_code: "three-test-1"})
    {:ok, _} = CardGames.join_game_session(player2, game_session.id)

    # Start game with rank "3" excluded from dealing so we can manually add it
    {:ok, started_game} = CardGames.start_game(game_session, exclude_ranks: ["3"])
    {:ok, preloaded_started_game} = CardGames.get_game_session_preloaded(started_game.id)
    %{player: player, player2: player2, started_game: preloaded_started_game}
  end

  describe "playing a '3' card creates penalty" do
    test "forces the next player to draw 3 cards with correct penalty_type", %{
      started_game: started_game
    } do
      # Get the top card and current player
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      # Find a '3' card from the deck that matches the top card suit
      deck_card_three =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "3" and dc.card.suit == top_card.suit end)

      assert deck_card_three,
             "Expected to find a '3' card matching suit #{top_card.suit} (excluded from dealing)"

      # Move the '3' to current player's hand
      {:ok, _updated_deck_card} =
        DeckCard.changeset(deck_card_three, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session with fresh deck_cards
      {:ok, game_session_fresh} = CardGames.get_game_session_preloaded(started_game.id)

      # Get the next player
      players = CardGames.get_game_session_players(game_session_fresh.id)
      # Works only because the game has 2 players
      next_player = Enum.find(players, fn p -> p.id != current_player_id end)

      # Action: Current player plays the '3' (pass card ID, not struct)
      {:ok, updated_game_session} =
        CardGames.play_cards(game_session_fresh, current_player_id, [deck_card_three.card.id])

      # Assert: Game state is updated to indicate next player must draw 3 cards
      assert updated_game_session.draw_penalty["active"] == true
      assert updated_game_session.draw_penalty["penalty_type"] == "three"
      assert updated_game_session.draw_penalty["target_player_id"] == next_player.id
    end

    test "allows '3' as last card - player becomes cardless, penalty applies", %{
      started_game: started_game
    } do
      # Get the top card and current player
      top_card = started_game.top_card
      current_player_id = started_game.current_turn_player_id

      # Find a '3' card from the deck that matches the top card suit
      deck_card_three =
        started_game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "3" and dc.card.suit == top_card.suit end)

      assert deck_card_three,
             "Expected to find a '3' card matching suit #{top_card.suit}"

      # Give current player ONLY the '3' card (empty their hand first)
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

      # Move the '3' to current player's hand as their ONLY card
      {:ok, _updated_deck_card} =
        DeckCard.changeset(deck_card_three, %{
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

      # Action: Current player plays the '3' as their last card
      {:ok, updated_game_session} =
        CardGames.play_cards(game_session_fresh, current_player_id, [deck_card_three.card.id])

      # Assert: Player becomes cardless (hand is empty)
      final_hand = CardGames.get_player_hand(updated_game_session, current_player_id)
      assert length(final_hand) == 0, "Player should have empty hand after playing last card"

      # Assert: Penalty is activated for next player
      assert updated_game_session.draw_penalty["active"] == true
      assert updated_game_session.draw_penalty["penalty_type"] == "three"
      assert updated_game_session.draw_penalty["target_player_id"] == next_player.id

      # Assert: Game continues (turn advanced to next player)
      assert updated_game_session.current_turn_player_id == next_player.id

      # Assert: Player entered "cardless" status
      player_session =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: updated_game_session.id,
          player_id: current_player_id
        )

      assert player_session.status == "cardless",
             "Player should enter 'cardless' status when playing '3' as last card"
    end
  end

  describe "blocking a '3' penalty" do
    # Helper to create a '3' penalty situation
    defp setup_penalty(game_session, from_player_id, to_player_id) do
      # Reload to ensure we have top_card for this game
      {:ok, game_session} = CardGames.get_game_session_preloaded(game_session.id)

      top_card = game_session.top_card

      # Find a '3' card from the deck that can be played on the top card
      deck_card_three =
        game_session.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "3" and dc.card.suit == top_card.suit end)

      assert deck_card_three,
             "Expected to find a playable '3' card (matching suit of #{top_card.suit}) in the deck"

      # Move '3' to from_player's hand
      {:ok, _} =
        DeckCard.changeset(deck_card_three, %{
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

      # Player plays the '3' to create penalty
      {:ok, game_with_penalty} =
        CardGames.play_cards(game_ready, from_player_id, [deck_card_three.card.id])

      # Verify penalty is active against to_player
      assert game_with_penalty.draw_penalty["active"] == true
      assert game_with_penalty.draw_penalty["target_player_id"] == to_player_id

      {game_with_penalty, deck_card_three.card}
    end

    test "player can block with an Ace", %{started_game: game, player: p1, player2: p2} do
      # P1 plays '3', penalizing P2
      {game_with_penalty, three_card_played} = setup_penalty(game, p1.id, p2.id)

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
      assert updated_game.draw_penalty["penalty_type"] == nil
      assert updated_game.draw_penalty["target_player_id"] == nil

      # Assert: action_suit is set to the suit of the '3' that was blocked
      assert updated_game.action_suit == three_card_played.suit

      # Assert: Turn advances to the next player (P1 in a 2-player game)
      assert updated_game.current_turn_player_id == p1.id
    end

    test "player can block and transfer penalty with another '3'", %{
      started_game: game,
      player: p1,
      player2: p2
    } do
      # P1 plays '3', penalizing P2
      {game_with_penalty, _three_card_played} = setup_penalty(game, p1.id, p2.id)

      # Reload to ensure deck associations are fresh after penalty setup
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      # Give P2 another '3' card
      deck_card_three =
        game_with_penalty.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "3"))

      {:ok, _} =
        DeckCard.changeset(deck_card_three, %{
          location_type: "player_hand",
          player_id: p2.id,
          order_index: nil
        })
        |> Repo.update()

      # Action: P2 plays the '3' to block and transfer
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      {:ok, updated_game} = CardGames.play_cards(game_reloaded, p2.id, [deck_card_three.card.id])

      # Assert: Penalty is still active
      assert updated_game.draw_penalty["active"] == true
      assert updated_game.draw_penalty["penalty_type"] == "three"

      # Assert: Penalty is transferred to the next player (P1 in a 2-player game)
      assert updated_game.draw_penalty["target_player_id"] == p1.id

      # Assert: Turn advanced to next player (which is P1)
      assert updated_game.current_turn_player_id == p1.id
    end
  end

  describe "cross-blocking prevention" do
    test "rejects '3' blocking '2' penalty", %{started_game: game, player: p1, player2: p2} do
      # Setup: Create a '2' penalty situation
      {:ok, game} = CardGames.get_game_session_preloaded(game.id)
      top_card = game.top_card

      # Find a '2' card from the deck that matches the top card suit
      deck_card_two =
        game.deck.deck_cards
        |> Enum.find(fn dc -> dc.card.rank == "2" and dc.card.suit == top_card.suit end)

      assert deck_card_two, "Expected to find a '2' card matching suit #{top_card.suit}"

      # Move '2' to p1's hand
      {:ok, _} =
        DeckCard.changeset(deck_card_two, %{
          location_type: "player_hand",
          player_id: p1.id,
          order_index: nil
        })
        |> Repo.update()

      # Set turn to p1
      {:ok, game_fresh} = CardGames.get_game_session_preloaded(game.id)

      {:ok, game_with_turn} =
        GameSession.changeset(game_fresh, %{current_turn_player_id: p1.id})
        |> Repo.update()

      {:ok, game_ready} = CardGames.get_game_session_preloaded(game_with_turn.id)

      # P1 plays '2' to create penalty
      {:ok, game_with_penalty} =
        CardGames.play_cards(game_ready, p1.id, [deck_card_two.card.id])

      # Verify penalty is active with type "two"
      assert game_with_penalty.draw_penalty["active"] == true
      assert game_with_penalty.draw_penalty["penalty_type"] == "two"
      assert game_with_penalty.draw_penalty["target_player_id"] == p2.id

      # Reload and give P2 a '3' card
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      deck_card_three =
        game_with_penalty.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "3"))

      {:ok, _} =
        DeckCard.changeset(deck_card_three, %{
          location_type: "player_hand",
          player_id: p2.id,
          order_index: nil
        })
        |> Repo.update()

      # Action: P2 tries to play '3' to block '2' penalty
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      result = CardGames.play_cards(game_reloaded, p2.id, [deck_card_three.card.id])

      # Assert: Play is rejected
      assert {:error, :invalid_play} = result
    end

    test "rejects '2' blocking '3' penalty", %{started_game: game, player: p1, player2: p2} do
      # P1 plays '3', penalizing P2
      {game_with_penalty, _three_card} = setup_penalty(game, p1.id, p2.id)

      # Verify penalty is active with type "three"
      assert game_with_penalty.draw_penalty["active"] == true
      assert game_with_penalty.draw_penalty["penalty_type"] == "three"

      # Reload and give P2 a '2' card
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)

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

      # Action: P2 tries to play '2' to block '3' penalty
      {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_with_penalty.id)

      result = CardGames.play_cards(game_reloaded, p2.id, [deck_card_two.card.id])

      # Assert: Play is rejected
      assert {:error, :invalid_play} = result
    end
  end

  describe "multiple '3' cards in one play (non-cumulative)" do
    test "playing multiple '3's does not stack the penalty count", %{
      started_game: game,
      player: p1,
      player2: p2
    } do
      # Reload to ensure we have top_card for this game
      {:ok, game} = CardGames.get_game_session_preloaded(game.id)

      top_card = game.top_card

      # Find '3' cards from the deck that match the top card's suit
      deck_cards_three =
        game.deck.deck_cards
        |> Enum.filter(fn dc -> dc.card.rank == "3" and dc.card.suit == top_card.suit end)
        |> Enum.take(2)

      # If we don't have 2 '3's of the same suit, play one '3' first to set up the combo
      if length(deck_cards_three) < 2 do
        # Find any '3' that matches the top card (by suit or rank)
        first_three =
          game.deck.deck_cards
          |> Enum.find(fn dc ->
            dc.card.rank == "3" and
              (dc.card.suit == top_card.suit or dc.card.rank == top_card.rank)
          end)

        assert first_three, "Expected to find at least one '3' card that matches the top card"

        # Move this '3' to p1's hand
        {:ok, _} =
          DeckCard.changeset(first_three, %{
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

        # P1 plays the first '3' to create a penalty
        {:ok, game_after_first} = CardGames.play_cards(game_ready, p1.id, [first_three.card.id])

        # Now the top card is a '3', so we can play any other '3's as a combo
        {:ok, game_reloaded} = CardGames.get_game_session_preloaded(game_after_first.id)

        remaining_threes =
          game_reloaded.deck.deck_cards
          |> Enum.filter(fn dc ->
            dc.card.rank == "3" and dc.location_type == "deck"
          end)
          |> Enum.take(2)

        assert length(remaining_threes) >= 2,
               "Expected to find at least 2 more '3' cards in the deck"

        # Move both '3' cards to p2's hand (next player)
        Enum.each(remaining_threes, fn deck_card_three ->
          {:ok, _} =
            DeckCard.changeset(deck_card_three, %{
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

        # Action: P2 plays both '3' cards as a combo to block and transfer
        card_ids = Enum.map(remaining_threes, & &1.card.id)
        {:ok, updated_game} = CardGames.play_cards(game_fresh2, p2.id, card_ids)

        # Assert: Penalty is still active with type "three" (not additive)
        assert updated_game.draw_penalty["active"] == true

        assert updated_game.draw_penalty["penalty_type"] == "three",
               "Expected penalty type to be 'three', not additive"

        assert updated_game.draw_penalty["target_player_id"] == p1.id
      else
        # We have 2 '3's of the same suit - can play them directly as a combo
        Enum.each(deck_cards_three, fn deck_card_three ->
          {:ok, _} =
            DeckCard.changeset(deck_card_three, %{
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

        # Action: P1 plays both '3' cards as a combo
        card_ids = Enum.map(deck_cards_three, & &1.card.id)
        {:ok, updated_game} = CardGames.play_cards(game_ready, p1.id, card_ids)

        # Assert: Penalty is active with type "three" (not additive)
        assert updated_game.draw_penalty["active"] == true

        assert updated_game.draw_penalty["penalty_type"] == "three",
               "Expected penalty type to be 'three', not additive"

        assert updated_game.draw_penalty["target_player_id"] == p2.id
      end
    end
  end

  describe "process_draw_penalty/2 with '3' penalty" do
    test "draws 3 cards for penalty_type='three'", %{started_game: game, player: p1, player2: p2} do
      # P1 plays '3', penalizing P2
      {game_with_penalty, _three_card} = setup_penalty(game, p1.id, p2.id)

      # Verify penalty is active
      assert game_with_penalty.draw_penalty["active"] == true
      assert game_with_penalty.draw_penalty["penalty_type"] == "three"
      assert game_with_penalty.draw_penalty["target_player_id"] == p2.id

      # Get P2's hand size before drawing
      {:ok, game_with_penalty} = CardGames.get_game_session_preloaded(game_with_penalty.id)
      hand_before = CardGames.get_player_hand(game_with_penalty, p2.id)
      hand_size_before = length(hand_before)

      # Action: P2 accepts penalty and draws 3 cards
      {:ok, updated_game} = CardGames.process_draw_penalty(game_with_penalty, p2.id)

      # Assert: P2 drew 3 cards
      hand_after = CardGames.get_player_hand(updated_game, p2.id)

      assert length(hand_after) == hand_size_before + 3,
             "Expected player to draw 3 cards (had #{hand_size_before}, now has #{length(hand_after)})"

      # Assert: Penalty is cleared
      assert updated_game.draw_penalty["active"] == false
      assert updated_game.draw_penalty["penalty_type"] == nil

      # Assert: Turn advanced to next player
      assert updated_game.current_turn_player_id == p1.id
    end
  end
end
