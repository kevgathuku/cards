defmodule Kadi.CardGames.DeckRecyclingTest do
  use Kadi.DataCase, async: true

  import Ecto.Query, warn: false
  alias Kadi.CardGames

  import Kadi.AccountsFixtures

  describe "recycle_played_stack/1" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "recycle-player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "recycle-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "successfully recycles cards from played stack", %{
      game_session: game_session,
      player1: _player1,
      player2: _player2
    } do
      # Reload to get fresh state after start_game
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # After start_game:
      # - 8 cards in player_hands (4 each for 2 players)
      # - 1 card in played_stack
      # - 43 cards in deck

      # Take 4 more cards from deck and add to played_stack (total 5 in played_stack)
      deck_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.sort_by(& &1.order_index)
        |> Enum.take(4)

      # Move to played_stack, keeping original order_index
      Enum.each(deck_cards, fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{location_type: "played_stack"})
        |> Repo.update!()
      end)

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Execute recycle
      {:ok, recycled} = CardGames.recycle_played_stack(game_session)

      # Verify: 4 cards recycled into deck (total 43 in deck), 1 topmost in played_stack
      recycled = Repo.preload(recycled, [deck: [deck_cards: :card]], force: true)

      deck_count =
        recycled.deck.deck_cards
        |> Enum.count(&(&1.location_type == "deck"))

      played_count =
        recycled.deck.deck_cards
        |> Enum.count(&(&1.location_type == "played_stack"))

      # After recycle: 43 cards remain (39 that were in deck + 4 recycled from played_stack)
      assert deck_count == 43
      assert played_count == 1
    end

    test "keeps topmost card (highest order_index) in played stack", %{
      game_session: game_session
    } do
      # Reload to get fresh state after start_game
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # Setup: 5 cards in played_stack with their original order_index
      deck_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.sort_by(& &1.order_index)
        |> Enum.take(5)

      # Move cards to played_stack, keeping their original order_index
      Enum.each(deck_cards, fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{location_type: "played_stack"})
        |> Repo.update!()
      end)

      topmost_card_id = Enum.at(deck_cards, 4).id

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      {:ok, recycled} = CardGames.recycle_played_stack(game_session)

      # Verify topmost card still in played_stack
      recycled = Repo.preload(recycled, [deck: [deck_cards: :card]], force: true)

      topmost_card =
        recycled.deck.deck_cards
        |> Enum.find(&(&1.location_type == "played_stack"))

      assert topmost_card.id == topmost_card_id
      assert topmost_card.order_index == Enum.at(deck_cards, 4).order_index
    end

    test "assigns sequential shuffled indices to recycled cards", %{game_session: game_session} do
      # Reload to get fresh state after start_game
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # After start_game:
      # - 8 cards in player_hands (4 each for 2 players)
      # - 1 card in played_stack (with lowest order_index)
      # - 43 cards in deck

      initial_deck_count =
        game_session.deck.deck_cards
        |> Enum.count(&(&1.location_type == "deck"))

      # Take 9 more cards from deck and add to played_stack (total 10 in played_stack)
      deck_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.sort_by(& &1.order_index)
        |> Enum.take(9)

      # Move to played_stack, keeping original order_index
      Enum.each(deck_cards, fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{location_type: "played_stack"})
        |> Repo.update!()
      end)

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      {:ok, recycled} = CardGames.recycle_played_stack(game_session)

      # Verify: 9 cards recycled back to deck (10 in played_stack - 1 topmost)
      recycled = Repo.preload(recycled, [deck: [deck_cards: :card]], force: true)

      deck_cards_after =
        recycled.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))

      # After recycle: 43 cards total in deck (34 original + 9 recycled)
      assert length(deck_cards_after) == initial_deck_count

      # Verify ALL deck cards now have sequential indices
      # The recycle assigns indices 1..9 to the 9 recycled cards
      # The existing 34 deck cards had indices 9-52 (with gaps)
      # After recycle, we should have cards with indices 1..9 (recycled) plus original cards
      all_indices =
        deck_cards_after
        |> Enum.map(& &1.order_index)
        |> Enum.sort()

      # The recycled cards should occupy indices 1-9
      recycled_indices = Enum.take(all_indices, 9)
      assert recycled_indices == Enum.to_list(1..9)

      # Verify we have exactly 43 cards in deck
      assert length(all_indices) == 43
    end

    test "returns error when played stack is empty", %{game_session: game_session} do
      # Reload to get fresh state - after start_game, there's 1 card in played_stack
      # Remove it for this test
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # Move the played_stack card back to deck to create empty played_stack
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "played_stack"))
      |> Enum.each(fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{location_type: "deck"})
        |> Repo.update!()
      end)

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Setup: no cards in played_stack (all in deck)
      assert {:error, :no_cards_in_played_stack} =
               CardGames.recycle_played_stack(game_session)
    end

    test "returns error when only 1 card in played stack", %{game_session: game_session} do
      # Reload to get fresh state - after start_game, there's already 1 card in played_stack
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # The start_game already created 1 card in played_stack - perfect for this test!
      assert {:error, :insufficient_cards_to_recycle} =
               CardGames.recycle_played_stack(game_session)
    end

    test "clears player_id on recycled cards", %{
      game_session: game_session,
      player1: player1
    } do
      # Reload to get fresh state after start_game
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # Simulate cards that came from player_hand (which have player_id)
      # First, take 3 cards from deck and move them to player_hand with player_id
      deck_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.sort_by(& &1.order_index)
        |> Enum.take(3)

      # Move cards to player_hand first (which allows player_id)
      Enum.each(deck_cards, fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{
          location_type: "player_hand",
          player_id: player1.id,
          order_index: nil
        })
        |> Repo.update!()
      end)

      # Now move them from player_hand to played_stack
      # (This simulates cards being played from hand)
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      player_hand_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player1.id))
        |> Enum.take(3)

      # Move from player_hand to played_stack
      # Note: In real gameplay, player_id might persist if not explicitly cleared
      Enum.each(player_hand_cards, fn dc ->
        # Use Ecto.Changeset.change to bypass validations for this test
        dc
        |> Ecto.Changeset.change(%{location_type: "played_stack"})
        |> Repo.update!()
      end)

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Execute recycle
      {:ok, recycled} = CardGames.recycle_played_stack(game_session)

      # Verify all recycled cards have player_id = nil
      recycled = Repo.preload(recycled, [deck: [deck_cards: :card]], force: true)

      deck_player_ids =
        recycled.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.map(& &1.player_id)

      assert Enum.all?(deck_player_ids, &is_nil/1)
    end
  end
end
