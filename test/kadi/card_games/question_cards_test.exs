defmodule Kadi.CardGames.QuestionCardsTest do
  use Kadi.DataCase, async: true

  import Ecto.Query, warn: false
  alias Kadi.CardGames
  alias Kadi.Games.DeckCard

  import Kadi.AccountsFixtures

  setup do
    player = player_fixture()
    player2 = player_fixture()

    {:ok, game_session} = CardGames.create_game_session(player, %{short_code: "Q8TEST"})
    {:ok, _} = CardGames.join_game_session(player2, game_session.id)
    # Exclude 8 and queen cards from initial deal so they're available for testing
    {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["8", "queen"])

    {:ok, preloaded_game} = CardGames.get_game_session_preloaded(game_session)
    %{game_session: preloaded_game, player: player, player2: player2}
  end

  describe "play_cards/3 - incomplete question (Q or 8 without answer)" do
    test "playing 8 card without answer returns :needs_draw", %{
      game_session: game_session
    } do
      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find one 8 card matching the top card's suit or rank
      eight_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "8" and dc.location_type == "deck" and
            (dc.card.suit == top_card.suit or dc.card.rank == top_card.rank)
        end)

      # Move the 8 to current player's hand
      {:ok, _} =
        DeckCard.changeset(eight_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload
      {:ok, game_session} = CardGames.get_game_session_preloaded(game_session.id)

      # Play the 8 without an answer
      result = CardGames.play_cards(game_session, current_player.id, [eight_card.card.id])

      # Verify result is :needs_draw
      assert {:ok, :needs_draw, updated_game} = result

      # Verify card was moved to played pile
      assert updated_game.top_card_id == eight_card.card.id

      # Verify turn did NOT advance (player must draw)
      assert updated_game.current_turn_player_id == current_player.id
    end

    test "playing queen cards without answer returns :needs_draw", %{
      game_session: game_session
    } do
      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find one queen card matching the top card's suit or rank
      queen_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "queen" and dc.location_type == "deck" and
            (dc.card.suit == top_card.suit or dc.card.rank == top_card.rank)
        end)

      # Move the queen to current player's hand
      {:ok, _} =
        DeckCard.changeset(queen_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload
      {:ok, game_session} = CardGames.get_game_session_preloaded(game_session.id)

      # Play the queen without an answer
      result = CardGames.play_cards(game_session, current_player.id, [queen_card.card.id])

      # Verify result is :needs_draw
      assert {:ok, :needs_draw, updated_game} = result

      # Verify card was moved to played pile
      assert updated_game.top_card_id == queen_card.card.id

      # Verify turn did NOT advance (player must draw)
      assert updated_game.current_turn_player_id == current_player.id
    end
  end

  describe "play_cards/3 - complete question (Q or 8 with answer)" do
    test "playing 8 cards with answer advances turn normally", %{
      game_session: game_session
    } do
      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find first 8 card matching the top card's suit or rank
      eight1 =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "8" and dc.location_type == "deck" and
            (dc.card.suit == top_card.suit or dc.card.rank == top_card.rank)
        end)

      # Find second 8 card (any suit)
      eight2 =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "8" and dc.location_type == "deck" and
            dc.id != eight1.id
        end)

      # Find an answer card matching the second 8's suit (any non-Q, non-8 card)
      answer_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.suit == eight2.card.suit and
            dc.card.rank not in ["queen", "8"] and
            dc.location_type == "deck"
        end)

      # Move all cards to current player's hand
      Repo.update_all(
        from(dc in DeckCard, where: dc.id in [^eight1.id, ^eight2.id, ^answer_card.id]),
        set: [location_type: "player_hand", player_id: current_player.id, order_index: nil]
      )

      # Reload
      {:ok, game_session} = CardGames.get_game_session_preloaded(game_session.id)

      # Play 8, 8, answer (complete question with answer)
      result =
        CardGames.play_cards(game_session, current_player.id, [
          eight1.card.id,
          eight2.card.id,
          answer_card.card.id
        ])

      # Verify result is normal success (not :needs_draw)
      assert {:ok, updated_game} = result

      # Verify cards were moved to played pile
      assert updated_game.top_card_id == answer_card.card.id

      # Verify turn advanced to next player
      assert updated_game.current_turn_player_id != current_player.id
    end

    test "playing queen cards with answer advances turn normally", %{
      game_session: game_session
    } do
      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find first queen card matching the top card's suit or rank
      queen1 =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "queen" and dc.location_type == "deck" and
            (dc.card.suit == top_card.suit or dc.card.rank == top_card.rank)
        end)

      # Find second queen card (any suit)
      queen2 =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "queen" and dc.location_type == "deck" and
            dc.id != queen1.id
        end)

      # Find an answer card matching the second queen's suit (any non-Q, non-8 card)
      answer_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.suit == queen2.card.suit and
            dc.card.rank not in ["queen", "8"] and
            dc.location_type == "deck"
        end)

      # Move all cards to current player's hand
      Repo.update_all(
        from(dc in DeckCard, where: dc.id in [^queen1.id, ^queen2.id, ^answer_card.id]),
        set: [location_type: "player_hand", player_id: current_player.id, order_index: nil]
      )

      # Reload
      {:ok, game_session} = CardGames.get_game_session_preloaded(game_session.id)

      # Play queen, queen, answer (complete question with answer)
      result =
        CardGames.play_cards(game_session, current_player.id, [
          queen1.card.id,
          queen2.card.id,
          answer_card.card.id
        ])

      # Verify result is normal success (not :needs_draw)
      assert {:ok, updated_game} = result

      # Verify cards were moved to played pile
      assert updated_game.top_card_id == answer_card.card.id

      # Verify turn advanced to next player
      assert updated_game.current_turn_player_id != current_player.id
    end
  end

  describe "answer_question_by_drawing/2" do
    test "draws one card and advances turn after incomplete question", %{
      game_session: game_session
    } do
      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find one 8 card matching the top card's suit or rank
      eight_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "8" and dc.location_type == "deck" and
            (dc.card.suit == top_card.suit or dc.card.rank == top_card.rank)
        end)

      # Move the 8 to current player's hand
      {:ok, _} =
        DeckCard.changeset(eight_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload
      {:ok, game_session} = CardGames.get_game_session_preloaded(game_session.id)

      # Count player's cards before
      initial_card_count = CardGames.count_player_cards(game_session, current_player.id)

      # Play the 8 without an answer (returns :needs_draw)
      {:ok, :needs_draw, game_after_play} =
        CardGames.play_cards(game_session, current_player.id, [eight_card.card.id])

      # Verify turn did NOT advance yet
      assert game_after_play.current_turn_player_id == current_player.id

      # Now answer the question by drawing
      {:ok, updated_game} =
        CardGames.answer_question_by_drawing(game_after_play, current_player.id)

      # Verify one card was drawn (initial - 1 for played card + 1 for drawn = initial)
      final_card_count = CardGames.count_player_cards(updated_game, current_player.id)
      assert final_card_count == initial_card_count

      # Verify turn advanced to next player
      assert updated_game.current_turn_player_id != current_player.id
    end

    test "returns error when not player's turn", %{game_session: game_session, player2: player2} do
      current_player = game_session.current_turn_player

      # Try to draw when it's not player2's turn
      if current_player.id != player2.id do
        result = CardGames.answer_question_by_drawing(game_session, player2.id)
        assert {:error, :not_your_turn} = result
      end
    end

    test "recycles played pile when deck is empty", %{game_session: game_session} do
      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find one 8 card matching the top card's suit or rank
      eight_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "8" and dc.location_type == "deck" and
            (dc.card.suit == top_card.suit or dc.card.rank == top_card.rank)
        end)

      # Move the 8 to current player's hand
      {:ok, _} =
        DeckCard.changeset(eight_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Move all other deck cards to played pile (except the starting card)
      # Assign unique order_index values to avoid constraint violation
      deck_cards_to_move =
        from(dc in DeckCard,
          where:
            dc.deck_id == ^game_session.deck.id and dc.location_type == "deck" and
              dc.id != ^eight_card.id
        )
        |> Repo.all()

      deck_cards_to_move
      |> Enum.with_index(2)
      |> Enum.each(fn {dc, index} ->
        DeckCard.changeset(dc, %{location_type: "played_stack", order_index: index})
        |> Repo.update!()
      end)

      # Reload
      {:ok, game_session} = CardGames.get_game_session_preloaded(game_session.id)

      # Count player's cards before playing
      initial_card_count = CardGames.count_player_cards(game_session, current_player.id)

      # Play the 8 without an answer
      {:ok, :needs_draw, game_after_play} =
        CardGames.play_cards(game_session, current_player.id, [eight_card.card.id])

      # Now answer the question by drawing (should recycle first)
      {:ok, updated_game} =
        CardGames.answer_question_by_drawing(game_after_play, current_player.id)

      # Verify player has same number of cards (played 1, drew 1)
      final_card_count = CardGames.count_player_cards(updated_game, current_player.id)
      assert final_card_count == initial_card_count

      # Verify turn advanced
      assert updated_game.current_turn_player_id != current_player.id

      # Verify deck has cards (recycling worked)
      deck_count = CardGames.count_deck_cards(updated_game)
      assert deck_count > 0
    end
  end
end
