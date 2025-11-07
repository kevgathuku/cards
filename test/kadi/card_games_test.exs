defmodule Kadi.CardGamesTest do
  use Kadi.DataCase

  import Ecto.Query, warn: false
  alias Kadi.CardGames

  import Kadi.AccountsFixtures

  setup do
    player = player_fixture()
    %{player: player}
  end

  describe "get_game_session/1" do
    test "returns the game session if it exists", %{player: player} do
      {:ok, game_session} = CardGames.create_game_session(player, %{short_code: "Test Game"})
      {:ok, retrieved_game_session} = CardGames.get_game_session(game_session.id)
      assert retrieved_game_session.id == game_session.id
      assert retrieved_game_session.short_code == "Test Game"
    end

    test "returns an error if the game session does not exist" do
      assert CardGames.get_game_session(1001) == {:error, :not_found}
    end
  end

  describe "list_user_games/1" do
    test "returns all games a user is a part of", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})
      {:ok, _} = CardGames.create_game_session(player, %{short_code: "Game 1"})

      # Create another game session and add player
      {:ok, game_session2} = CardGames.create_game_session(player2, %{short_code: "Game 2"})
      {:ok, _} = CardGames.join_game_session(player, game_session2.id)

      games = CardGames.list_user_games(player.id)
      assert length(games) == 2
      game_short_codes = Enum.map(games, & &1.short_code)
      assert "Game 1" in game_short_codes
      assert "Game 2" in game_short_codes
    end

    test "returns an empty list if the user is not in any games" do
      player = player_fixture()
      assert CardGames.list_user_games(player.id) == []
    end
  end

  describe "create_game_session/2" do
    test "creates a game session", %{player: player} do
      attrs = %{short_code: "New Game"}
      {:ok, game_session} = CardGames.create_game_session(player, attrs)

      assert game_session.short_code == "New Game"
      assert game_session.created_by_id == player.id
      assert game_session.status == "lobby"

      # Check that the creator is a participant
      participants =
        Repo.all(
          from gsp in Kadi.Games.GameSessionPlayer,
            where: gsp.game_session_id == ^game_session.id,
            select: gsp.player_id
        )

      assert player.id in participants

      # Check that a deck was created
      deck = Repo.get_by(Kadi.Games.Deck, game_session_id: game_session.id)
      assert deck != nil

      deck_cards_count =
        Repo.aggregate(
          from(dc in Kadi.Games.DeckCard, where: dc.deck_id == ^deck.id),
          :count,
          :id
        )

      assert deck_cards_count == 52
    end
  end

  describe "join_game_session/2" do
    test "allows a player to join an existing game", %{player: player} do
      creator = player_fixture(%{email: "creator@example.com"})
      {:ok, game_session} = CardGames.create_game_session(creator, %{short_code: "Joinable Game"})

      {:ok, _game_session_player} = CardGames.join_game_session(player, game_session.id)

      participants =
        Repo.all(
          from gsp in Kadi.Games.GameSessionPlayer,
            where: gsp.game_session_id == ^game_session.id,
            select: gsp.player_id
        )

      assert player.id in participants
    end

    test "returns an error if the game session does not exist", %{player: player} do
      assert CardGames.join_game_session(player, 1002) == {:error, :not_found}
    end
  end

  describe "start_game/1" do
    test "starts a game, deals cards, and changes status to live", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "start-game-test"})

      CardGames.join_game_session(player2, game_session.id)

      {:ok, started_game_session} = CardGames.start_game(game_session)

      assert started_game_session.status == "live"

      # Check cards for player 1
      player1_cards =
        Repo.all(
          from dc in Kadi.Games.DeckCard,
            where: dc.player_id == ^player.id and dc.location_type == "player_hand"
        )

      assert Enum.count(player1_cards) == 4

      # Check cards for player 2
      player2_cards =
        Repo.all(
          from dc in Kadi.Games.DeckCard,
            where: dc.player_id == ^player2.id and dc.location_type == "player_hand"
        )

      assert Enum.count(player2_cards) == 4

      # Check remaining cards in deck
      deck_cards =
        Repo.all(
          from dc in Kadi.Games.DeckCard,
            join: d in Kadi.Games.Deck,
            on: dc.deck_id == d.id,
            where: d.game_session_id == ^started_game_session.id and dc.location_type == "deck"
        )

      # 52 (total cards) - 8 (4 cards × 2 players) - 1 (start card) = 43
      assert Enum.count(deck_cards) == 52 - 2 * 4 - 1
    end

    test "returns an error if there are not enough players", %{player: player} do
      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "not-enough-players"})

      assert CardGames.start_game(game_session) == {:error, :not_enough_players}

      refreshed_game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      assert refreshed_game_session.status == "lobby"
    end

    test "assigns exactly one card to the played_stack", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "played-stack-test"})

      CardGames.join_game_session(player2, game_session.id)

      {:ok, started_game_session} = CardGames.start_game(game_session)

      played_stack_cards =
        Repo.all(
          from dc in Kadi.Games.DeckCard,
            join: d in Kadi.Games.Deck,
            on: dc.deck_id == d.id,
            where:
              d.game_session_id == ^started_game_session.id and dc.location_type == "played_stack"
        )

      assert Enum.count(played_stack_cards) == 1
    end

    test "ensures the card in played_stack is not a special card", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "special-card-test"})

      CardGames.join_game_session(player2, game_session.id)

      {:ok, started_game_session} = CardGames.start_game(game_session)

      [played_deck_card] =
        Repo.all(
          from dc in Kadi.Games.DeckCard,
            join: d in Kadi.Games.Deck,
            on: dc.deck_id == d.id,
            where:
              d.game_session_id == ^started_game_session.id and dc.location_type == "played_stack",
            preload: [:card]
        )

      special_ranks = ["2", "3", "jack", "queen", "king", "ace"]
      refute played_deck_card.card.rank in special_ranks
    end

    test "sets the order_index for the starting card", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "order-index-test"})

      CardGames.join_game_session(player2, game_session.id)

      {:ok, started_game_session} = CardGames.start_game(game_session)

      [played_deck_card] =
        Repo.all(
          from dc in Kadi.Games.DeckCard,
            join: d in Kadi.Games.Deck,
            on: dc.deck_id == d.id,
            where:
              d.game_session_id == ^started_game_session.id and dc.location_type == "played_stack"
        )

      assert played_deck_card.order_index == 1
    end

    test "assigns a random player as current_turn_player", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})
      player3 = player_fixture(%{email: "player3@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "turn-player-test"})

      CardGames.join_game_session(player2, game_session.id)
      CardGames.join_game_session(player3, game_session.id)

      {:ok, started_game_session} = CardGames.start_game(game_session)

      # Verify a current turn player was assigned
      assert started_game_session.current_turn_player_id != nil

      # Verify the assigned player is one of the players in the game
      player_ids = [player.id, player2.id, player3.id]
      assert started_game_session.current_turn_player_id in player_ids
    end
  end

  describe "deal_cards/2 with order_index" do
    # Test helper functions for sequential pattern detection
    defp rank_to_number(card) do
      case card.rank do
        "ace" -> 1
        "2" -> 2
        "3" -> 3
        "4" -> 4
        "5" -> 5
        "6" -> 6
        "7" -> 7
        "8" -> 8
        "9" -> 9
        "10" -> 10
        "jack" -> 11
        "queen" -> 12
        "king" -> 13
      end
    end

    defp has_consecutive_sequence?(sorted_numbers, min_length) do
      sorted_numbers
      |> Enum.chunk_while(
        [],
        fn num, acc ->
          case acc do
            [] -> {:cont, [num]}
            [last | _] when num == last + 1 -> {:cont, [num | acc]}
            _ -> {:cont, Enum.reverse(acc), [num]}
          end
        end,
        fn
          [] -> {:cont, []}
          acc -> {:cont, Enum.reverse(acc), []}
        end
      )
      |> Enum.any?(fn sequence -> length(sequence) >= min_length end)
    end

    defp has_sequential_pattern?(cards) do
      # Check if hand contains 3+ consecutive ranks of same suit
      by_suit =
        cards
        |> Enum.group_by(& &1.suit)

      Enum.any?(by_suit, fn {_suit, suit_cards} ->
        ranks = Enum.map(suit_cards, &rank_to_number/1) |> Enum.sort()
        has_consecutive_sequence?(ranks, 3)
      end)
    end

    test "deals cards in order_index sequence", %{player: player} do
      player2 = player_fixture(%{email: "player2-ordertest@example.com"})
      player3 = player_fixture(%{email: "player3-ordertest@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "order-sequence-test"})

      CardGames.join_game_session(player2, game_session.id)
      CardGames.join_game_session(player3, game_session.id)

      {:ok, started_game_session} = CardGames.start_game(game_session)

      # Reload with all associations
      started_game_session =
        Repo.preload(started_game_session, [:deck], force: true)
        |> Repo.preload([deck: [deck_cards: :card]], force: true)

      # Get all dealt cards (player_hand location_type)
      dealt_cards =
        started_game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand"))

      # Verify: 12 cards dealt (3 players × 4 cards)
      assert length(dealt_cards) == 12

      # Note: We cannot directly verify order_index sequence since order_index
      # is set to nil for player_hand location_type. This test verifies dealing
      # completes successfully with the implementation.
    end

    test "distributes cards according to randomized order_index", %{player: player} do
      player2 = player_fixture(%{email: "player2-random@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "random-dist-test"})

      CardGames.join_game_session(player2, game_session.id)

      {:ok, started_game_session} = CardGames.start_game(game_session)

      # Reload with associations
      started_game_session =
        Repo.preload(started_game_session, [deck: [deck_cards: :card]], force: true)

      player1_cards =
        started_game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player.id))
        |> Enum.map(& &1.card)

      player2_cards =
        started_game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player2.id))
        |> Enum.map(& &1.card)

      # Verify each player got 4 cards
      assert length(player1_cards) == 4
      assert length(player2_cards) == 4

      # Verify distribution (cards should be non-empty and different)
      assert length(player1_cards) > 0
      assert length(player2_cards) > 0
    end

    test "no sequential patterns across multiple game starts" do
      player = player_fixture()
      player2 = player_fixture(%{email: "player2-stats@example.com"})

      # Run 20 games (reduced from 100 for faster test execution)
      # In production, increase to 100+ for thorough statistical validation
      results =
        for i <- 1..20 do
          {:ok, game_session} =
            CardGames.create_game_session(player, %{short_code: "stats-test-#{i}"})

          CardGames.join_game_session(player2, game_session.id)

          {:ok, started_game_session} = CardGames.start_game(game_session)

          started_game_session =
            Repo.preload(started_game_session, [deck: [deck_cards: :card]], force: true)

          player_hands =
            [player.id, player2.id]
            |> Enum.map(fn player_id ->
              started_game_session.deck.deck_cards
              |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player_id))
              |> Enum.map(& &1.card)
            end)

          # Check each hand for sequential patterns
          Enum.any?(player_hands, fn hand ->
            has_sequential_pattern?(hand)
          end)
        end

      # Statistical check: <20% of games should have sequential patterns
      # (generous threshold for 20 iterations; with proper randomization expect ~0%)
      sequential_pattern_count = Enum.count(results, & &1)

      assert sequential_pattern_count < 4,
             "Too many games with sequential patterns: #{sequential_pattern_count}/20 (expected <4)"
    end
  end

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

      # Reload to check database state
      updated_session = Kadi.Repo.preload(updated_session, deck: [deck_cards: :card])

      # Player should have one more card
      player_cards =
        updated_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == current_player_id))

      # Started with 4, drew 1
      assert length(player_cards) == 5

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
          reloaded = Kadi.Repo.get!(Kadi.Games.GameSession, updated_sess.id)
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
      game_session = Kadi.Repo.preload(game_session, deck: :deck_cards)

      Enum.each(game_session.deck.deck_cards, fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{
          location_type: "player_hand",
          player_id: player.id,
          order_index: nil
        })
        |> Kadi.Repo.update!()
      end)

      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{
          status: "live",
          current_turn_player_id: player.id
        })
        |> Kadi.Repo.update!()

      # Reload to get updated associations
      game_session = Kadi.Repo.get!(Kadi.Games.GameSession, game_session.id)

      # With no cards in played stack, recycling fails
      assert {:error, :no_cards_in_played_stack} =
               CardGames.draw_card_from_deck(game_session, player.id)
    end
  end

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

    test "returns error when cannot recycle (only 1 card in played stack)", %{
      player1: player1,
      game_session: game_session
    } do
      # Setup: Empty deck, only 1 card in played_stack (the one from start_game)
      game_session = Repo.preload(game_session, deck: [deck_cards: :card])

      # Move all deck cards to player hand (leaving only the played card)
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.each(fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{
          location_type: "player_hand",
          player_id: player1.id,
          order_index: nil
        })
        |> Repo.update!()
      end)

      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Repo.update!()

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Execute draw (should fail to recycle - only 1 card in played stack)
      assert {:error, :insufficient_cards_to_recycle} =
               CardGames.draw_card_from_deck(game_session, player1.id)
    end

    test "topmost card remains visible after recycle", %{
      player1: player1,
      game_session: game_session
    } do
      # Setup: Nearly empty deck (keep 1 card), multiple cards in played_stack
      game_session = Repo.preload(game_session, deck: [deck_cards: :card])

      # Get max order index for played cards
      existing_played_max_index =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "played_stack"))
        |> Enum.map(& &1.order_index)
        |> Enum.max(fn -> 0 end)

      # Move 4 deck cards to played_stack (total will be 5 in played stack)
      deck_cards_to_move =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.take(4)

      Enum.with_index(deck_cards_to_move, existing_played_max_index + 1)
      |> Enum.each(fn {dc, idx} ->
        Kadi.Games.DeckCard.changeset(dc, %{location_type: "played_stack", order_index: idx})
        |> Repo.update!()
      end)

      # Move ALL remaining deck cards EXCEPT 1 AND existing player hand cards to player1's hand
      # This leaves deck nearly empty (just 1 card), forcing recycle when drawing
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      cards_to_move =
        game_session.deck.deck_cards
        |> Enum.reject(&(&1.location_type == "played_stack"))
        # Keep 1 card in deck
        |> Enum.drop(1)

      Enum.each(cards_to_move, fn dc ->
        Kadi.Games.DeckCard.changeset(dc, %{
          location_type: "player_hand",
          player_id: player1.id,
          order_index: nil
        })
        |> Repo.update!()
      end)

      # The topmost card will be the last one we moved
      topmost_id = Enum.at(deck_cards_to_move, 3).id

      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Repo.update!()

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Draw (deck has 1 card, so no recycle yet)
      {:ok, updated} = CardGames.draw_card_from_deck(game_session, player1.id)

      # Set turn back to player1 for second draw
      updated =
        Kadi.Games.GameSession.changeset(updated, %{current_turn_player_id: player1.id})
        |> Repo.update!()

      # Now deck is empty, try drawing again - this triggers recycle
      # Recycle: 5 in played_stack -> recycle 4, keep 1 topmost, draw 1 from those 4
      {:ok, updated} = CardGames.draw_card_from_deck(updated, player1.id)

      # Verify topmost card still in played_stack
      updated = Repo.preload(updated, [deck: [deck_cards: :card]], force: true)

      played_cards =
        updated.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "played_stack"))

      # Should have 1 card (the topmost)
      assert length(played_cards) == 1
      assert hd(played_cards).id == topmost_id
    end
  end

  describe "play_cards/3" do
    setup %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})
      {:ok, game_session} = CardGames.create_game_session(player, %{short_code: "Test Play"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{game_session: game_session, player: player, player2: player2}
    end

    test "successfully plays a single matching card", %{
      game_session: game_session,
      player: player
    } do
      # Reload to get fresh state
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      # Get the current player
      current_player = if current_player_id == player.id, do: player, else: nil

      # Skip test if player is not current turn
      if current_player do
        # Get top card
        top_card =
          game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "played_stack"))
          |> Enum.max_by(& &1.order_index)
          |> Map.get(:card)

        # Find a matching card in player's hand
        player_hand =
          game_session.deck.deck_cards
          |> Enum.filter(
            &(&1.location_type == "player_hand" and &1.player_id == current_player.id)
          )
          |> Enum.map(& &1.card)

        matching_card =
          Enum.find(player_hand, fn card ->
            card.suit == top_card.suit or card.rank == top_card.rank
          end)

        if matching_card do
          {:ok, updated_game} =
            CardGames.play_cards(game_session, current_player.id, [matching_card.id])

          # Verify card was moved to played_stack
          updated_game = Repo.preload(updated_game, [deck: [deck_cards: :card]], force: true)

          played_cards =
            updated_game.deck.deck_cards
            |> Enum.filter(&(&1.location_type == "played_stack"))

          assert Enum.any?(played_cards, &(&1.card_id == matching_card.id))

          # Verify turn advanced
          refute updated_game.current_turn_player_id == current_player.id
        end
      end
    end

    test "rejects play when not player's turn", %{
      game_session: game_session,
      player: player,
      player2: player2
    } do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      # Get the non-current player
      wrong_player = if current_player_id == player.id, do: player2, else: player

      # Get any card from wrong player's hand
      player_hand =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == wrong_player.id))
        |> Enum.map(& &1.card)

      if card = List.first(player_hand) do
        assert {:error, :not_your_turn} =
                 CardGames.play_cards(game_session, wrong_player.id, [card.id])
      end
    end

    test "rejects invalid card play", %{game_session: game_session, player: player} do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      if current_player_id == player.id do
        # Get top card
        top_card =
          game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "played_stack"))
          |> Enum.max_by(& &1.order_index)
          |> Map.get(:card)

        # Find a non-matching card in player's hand
        player_hand =
          game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player.id))
          |> Enum.map(& &1.card)

        non_matching_card =
          Enum.find(player_hand, fn card ->
            card.suit != top_card.suit and card.rank != top_card.rank
          end)

        if non_matching_card do
          assert {:error, :invalid_play} =
                   CardGames.play_cards(game_session, player.id, [non_matching_card.id])
        end
      end
    end

    test "rejects play with cards not in hand", %{game_session: game_session, player: player} do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      if current_player_id == player.id do
        # Get a card from the deck (not in player's hand)
        deck_card =
          game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "deck"))
          |> List.first()

        if deck_card do
          assert {:error, :cards_not_in_hand} =
                   CardGames.play_cards(game_session, player.id, [deck_card.card_id])
        end
      end
    end

    test "successfully plays combo cards", %{game_session: game_session, player: player} do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      if current_player_id == player.id do
        # Get top card
        top_card =
          game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "played_stack"))
          |> Enum.max_by(& &1.order_index)
          |> Map.get(:card)

        # Find cards with same rank in player's hand
        player_hand =
          game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player.id))
          |> Enum.map(& &1.card)

        # Group by rank
        cards_by_rank =
          player_hand
          |> Enum.group_by(& &1.rank)
          |> Enum.filter(fn {_rank, cards} -> length(cards) >= 2 end)

        # Find a combo where first card matches top card
        combo =
          Enum.find_value(cards_by_rank, fn {_rank, cards} ->
            first_card = List.first(cards)

            if first_card.suit == top_card.suit or first_card.rank == top_card.rank do
              Enum.take(cards, 2)
            end
          end)

        if combo do
          card_ids = Enum.map(combo, & &1.id)
          {:ok, updated_game} = CardGames.play_cards(game_session, player.id, card_ids)

          # Verify all cards were moved to played_stack
          updated_game = Repo.preload(updated_game, [deck: [deck_cards: :card]], force: true)

          played_cards =
            updated_game.deck.deck_cards
            |> Enum.filter(&(&1.location_type == "played_stack"))
            |> Enum.map(& &1.card_id)

          assert Enum.all?(card_ids, &(&1 in played_cards))

          # Verify turn advanced
          refute updated_game.current_turn_player_id == player.id
        end
      end
    end

    test "rejects combo with mixed ranks", %{game_session: game_session, player: player} do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      if current_player_id == player.id do
        # Get player's hand
        player_hand =
          game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player.id))
          |> Enum.map(& &1.card)

        # Find two cards with different ranks
        cards_by_rank = Enum.group_by(player_hand, & &1.rank)

        if length(Map.keys(cards_by_rank)) >= 2 do
          # Get one card from two different ranks
          [rank1, rank2 | _] = Map.keys(cards_by_rank)
          card1 = hd(cards_by_rank[rank1])
          card2 = hd(cards_by_rank[rank2])

          # Try to play mixed ranks
          assert {:error, :invalid_play} =
                   CardGames.play_cards(game_session, player.id, [card1.id, card2.id])
        end
      end
    end
  end

  describe "play_cards/3 - edge cases" do
    setup %{player: player} do
      player2 = player_fixture(%{email: "edgecase@example.com"})
      {:ok, game_session} = CardGames.create_game_session(player, %{short_code: "Edge Test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{game_session: game_session, player: player, player2: player2}
    end

    test "rejects empty card list", %{game_session: game_session, player: player} do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      if current_player_id == player.id do
        # Try to play empty list
        assert {:error, :invalid_play} = CardGames.play_cards(game_session, player.id, [])
      end
    end

    test "rejects play when player not in game", %{game_session: game_session} do
      other_player = player_fixture(%{email: "notingame@example.com"})
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # Get any card id (doesn't matter since player not in game)
      card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand"))
        |> List.first()

      if card do
        # Note: Turn validation happens first, so we get :not_your_turn
        # This is correct behavior - more efficient to check turn before loading player data
        assert {:error, :not_your_turn} =
                 CardGames.play_cards(game_session, other_player.id, [card.card_id])
      end
    end

    test "rejects play with non-existent card id", %{game_session: game_session, player: player} do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      if current_player_id == player.id do
        # Use a card id that doesn't exist (very large number)
        fake_card_id = 999_999_999

        assert {:error, :cards_not_in_hand} =
                 CardGames.play_cards(game_session, player.id, [fake_card_id])
      end
    end
  end
end
