defmodule Kadi.CardGames.TurnManagementTest do
  use Kadi.DataCase

  import Ecto.Query, warn: false
  alias Kadi.CardGames

  import Kadi.AccountsFixtures

  describe "draw_card_from_deck/2" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})
      player3 = player_fixture(%{email: "player3@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "draw-test"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{
        player1: player1,
        player2: player2,
        player3: player3,
        game_session: game_session
      }
    end

    test "successfully draws a card when it's player's turn", %{
      game_session: game_session
    } do
      current_player_id = game_session.current_turn_player_id

      {:ok, updated_session} =
        CardGames.draw_card_from_deck(game_session, current_player_id)

      # Player should have one more card (started with 4, drew 1)
      assert CardGames.count_player_cards(updated_session, current_player_id) == 5

      # Turn should have advanced
      assert updated_session.current_turn_player_id != current_player_id
    end

    test "advances turn to next player in sequence (2 players)", %{
      player1: player1,
      player2: player2
    } do
      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "two-player"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      first_player_id = game_session.current_turn_player_id

      {:ok, updated_session} =
        CardGames.draw_card_from_deck(game_session, first_player_id)

      second_player_id = updated_session.current_turn_player_id

      # Turn should advance to other player
      assert second_player_id != first_player_id
      assert second_player_id in [player1.id, player2.id]
    end

    test "turn wraps around from last player to first", %{
      game_session: game_session
    } do
      # Draw cards until we cycle through all players
      session = game_session
      seen_order = []

      # Draw 3 times to complete one full cycle
      {session, seen_order} =
        Enum.reduce(1..3, {session, seen_order}, fn _, {sess, order} ->
          current_id = sess.current_turn_player_id
          {:ok, updated_sess} = CardGames.draw_card_from_deck(sess, current_id)
          reloaded = Repo.get!(Kadi.Games.GameSession, updated_sess.id)
          {reloaded, order ++ [current_id]}
        end)

      # After 3 draws, should be back to first player
      assert session.current_turn_player_id == hd(seen_order)
    end

    test "returns error when it's not player's turn", %{
      game_session: game_session,
      player2: player2,
      player3: player3
    } do
      current_player_id = game_session.current_turn_player_id

      # Find a player who is NOT the current turn player
      wrong_player_id =
        if current_player_id == player2.id, do: player3.id, else: player2.id

      assert {:error, :not_your_turn} =
               CardGames.draw_card_from_deck(game_session, wrong_player_id)
    end

    test "returns error when deck is empty and no cards to recycle" do
      player = player_fixture()

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "empty-deck"})

      # Manually empty the deck for testing
      game_session = Repo.preload(game_session, deck: :deck_cards)

      Enum.each(game_session.deck.deck_cards, fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{
          location_type: "player_hand",
          player_id: player.id,
          order_index: nil
        })
        |> Repo.update!()
      end)

      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{
          status: "live",
          current_turn_player_id: player.id
        })
        |> Repo.update!()

      # Reload to get updated associations
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # With no cards in played stack, recycling fails
      assert {:error, :no_cards_in_played_stack} =
               CardGames.draw_card_from_deck(game_session, player.id)
    end
  end

  describe "draw_card_from_deck/2 with automatic recycle" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "draw-recycle"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "drawing from empty deck triggers recycle and succeeds", %{
      player1: player1,
      game_session: game_session
    } do
      # Setup: Empty deck, multiple cards in played_stack
      game_session = Repo.preload(game_session, deck: [deck_cards: :card])

      # After start_game:
      # - 8 cards in player_hands (4 each for 2 players)
      # - 1 card in played_stack
      # - 43 cards in deck

      # Get existing played card (from start_game)
      existing_played_max_index =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "played_stack"))
        |> Enum.map(& &1.order_index)
        |> Enum.max(fn -> 0 end)

      # Take 4 cards from deck to add to played_stack
      deck_cards_to_played =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.take(4)

      # Move these 4 cards to played_stack (total will be 5 in played_stack)
      Enum.with_index(deck_cards_to_played, existing_played_max_index + 1)
      |> Enum.each(fn {dc, idx} ->
        Kadi.Games.DeckCard.changeset(dc, %{location_type: "played_stack", order_index: idx})
        |> Repo.update!()
      end)

      # Move ALL remaining deck cards to player hand to empty the deck
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      remaining_deck_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))

      Enum.each(remaining_deck_cards, fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{
          location_type: "player_hand",
          player_id: player1.id,
          order_index: nil
        })
        |> Repo.update!()
      end)

      # Set current turn to player1
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Repo.update!()

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Execute draw (deck is empty, should trigger recycle)
      {:ok, updated} = CardGames.draw_card_from_deck(game_session, player1.id)

      # Verify: player drew 1 card, deck has recycled cards minus the one drawn
      updated = Repo.preload(updated, [deck: [deck_cards: :card]], force: true)

      player_cards =
        updated.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player1.id))

      deck_cards_after =
        updated.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))

      # Started with 4 cards in hand (from start_game) + 39 moved + 1 drawn = 44 total
      assert length(player_cards) == 44

      # Recycle process: 5 in played_stack -> keep 1 topmost, recycle 4 -> draw 1 = 3 left in deck
      assert length(deck_cards_after) == 3
    end
  end

  describe "draw_card_from_deck/2 - gameplay integration" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "Draw Test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{game_session: game_session, player1: player1, player2: player2}
    end

    test "drawn card cannot be played immediately (turn advances)", %{
      game_session: game_session
    } do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      # Draw a card
      {:ok, updated_session} = CardGames.draw_card_from_deck(game_session, current_player_id)

      # Reload with associations
      updated_session = Repo.preload(updated_session, [deck: [deck_cards: :card]], force: true)

      # Get the drawn card (should be in current player's hand)
      drawn_cards =
        updated_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player_id))

      # Try to play the drawn card immediately (should fail because turn has advanced)
      if length(drawn_cards) > 0 do
        card = hd(drawn_cards)

        # This should fail with :not_your_turn because draw advances turn
        assert {:error, :not_your_turn} =
                 CardGames.play_cards(updated_session, current_player_id, [card.card_id])
      end
    end
  end
end
