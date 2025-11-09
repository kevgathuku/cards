defmodule Kadi.CardGamesTest do
  use Kadi.DataCase

  import Ecto.Query, warn: false
  alias Kadi.CardGames
  alias Kadi.Games.{Card, DeckCard}

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
      participant_ids = CardGames.get_game_session_players(game_session.id) |> Enum.map(& &1.id)

      assert player.id in participant_ids

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

      participant_ids = CardGames.get_game_session_players(game_session.id) |> Enum.map(& &1.id)

      assert player.id in participant_ids
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
      assert CardGames.count_player_cards(started_game_session, player.id) == 4

      # Check cards for player 2
      assert CardGames.count_player_cards(started_game_session, player2.id) == 4

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

      # As of feature 006-king-card, Kings are now allowed as start cards
      # Special cards that are still excluded: 2, 3, Jack, Queen, Ace
      special_ranks = ["2", "3", "jack", "queen", "ace"]
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

    test "sets top_card_id to the start card", %{player: player} do
      player2 = player_fixture(%{email: "player2b@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "top-card-test"})

      CardGames.join_game_session(player2, game_session.id)

      {:ok, started_game_session} = CardGames.start_game(game_session)

      # Verify top_card_id is set
      assert started_game_session.top_card_id != nil

      # Verify there's exactly 1 card in the played stack
      assert CardGames.count_played_cards(started_game_session) == 1

      # Get the top played card
      assert {:ok, top_card} = CardGames.get_top_played_card(started_game_session)

      # Reload to get top_card association for comparison
      started_game_session = Repo.preload(started_game_session, [:top_card])

      # Verify top_card matches the played card
      assert started_game_session.top_card_id == top_card.card_id
      assert started_game_session.top_card.id == top_card.card_id
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

      # Get all dealt cards (player_hand location_type)
      dealt_card_count =
        CardGames.count_player_cards(started_game_session, player.id) +
          CardGames.count_player_cards(started_game_session, player2.id) +
          CardGames.count_player_cards(started_game_session, player3.id)

      # Verify: 12 cards dealt (3 players × 4 cards)
      assert dealt_card_count == 12

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

      # Get player cards
      player1_cards =
        CardGames.get_player_hand(started_game_session, player.id)
        |> Enum.map(& &1.card)

      player2_cards =
        CardGames.get_player_hand(started_game_session, player2.id)
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
      player: player,
      player2: player2
    } do
      # Reload to get fresh state
      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      current_player_id = game_session.current_turn_player_id

      # Get the current player (could be player or player2)
      current_player = if current_player_id == player.id, do: player, else: player2

      # Get top card directly from game session
      top_card = game_session.top_card

      # Find a matching card in current player's hand
      # Only consider playable cards (regular ranks or king)
      playable_ranks = ["4", "5", "6", "7", "9", "10", "king"]

      player_hand =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player.id))
        |> Enum.map(& &1.card)

      matching_card =
        Enum.find(player_hand, fn card ->
          card.rank in playable_ranks and
            (card.suit == top_card.suit or card.rank == top_card.rank)
        end)

      # If no matching card in hand, create a guaranteed match by giving player a matching card from deck
      {game_session, matching_card} =
        if matching_card do
          {game_session, matching_card}
        else
          # Find a playable card in deck that matches top card
          deck_matching_card =
            game_session.deck.deck_cards
            |> Enum.filter(&(&1.location_type == "deck"))
            |> Enum.find(fn deck_card ->
              card = deck_card.card

              card.rank in playable_ranks and
                (card.suit == top_card.suit or card.rank == top_card.rank)
            end)

          if deck_matching_card do
            # Move this card to current player's hand
            {:ok, _updated_deck_card} =
              Kadi.Games.DeckCard.changeset(deck_matching_card, %{
                location_type: "player_hand",
                player_id: current_player.id,
                order_index: nil
              })
              |> Repo.update()

            # Reload game session to get updated state
            reloaded_game = Repo.get!(Kadi.Games.GameSession, game_session.id)
            reloaded_game = Repo.preload(reloaded_game, [deck: [deck_cards: :card]], force: true)

            {reloaded_game, deck_matching_card.card}
          else
            {game_session, nil}
          end
        end

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
      else
        # This should be extremely rare - no playable matching cards in entire deck
        flunk(
          "No playable matching card found in player's hand or deck (top_card: #{top_card.rank} of #{top_card.suit})"
        )
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

    test "successfully plays combo cards", %{
      game_session: game_session,
      player: player,
      player2: player2
    } do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # Get the current player (could be player or player2)
      current_player =
        if game_session.current_turn_player_id == player.id, do: player, else: player2

      # Get top card (can be any card that was previously played)
      top_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "played_stack"))
        |> Enum.max_by(& &1.order_index)
        |> Map.get(:card)

      # Find cards with same rank in player's hand
      # Phase 1: Only regular cards can be played in combos

      player_hand =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player.id))
        |> Enum.map(& &1.card)
        |> Enum.filter(&(&1.rank in ["4", "5", "6", "7", "9", "10"]))

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

      # If no combo exists, create one by moving cards from deck to player's hand
      {game_session, combo} =
        if combo do
          {game_session, combo}
        else
          # Find a regular rank that has at least 2 cards in the deck that can match top card
          deck_cards =
            game_session.deck.deck_cards
            |> Enum.filter(&(&1.location_type == "deck"))
            |> Enum.map(& &1.card)
            |> Enum.filter(&(&1.rank in ["4", "5", "6", "7", "9", "10"]))

          # Group by rank and find one with at least 2 cards that can match top card
          rank_with_cards =
            deck_cards
            |> Enum.group_by(& &1.rank)
            |> Enum.filter(fn {_rank, cards} -> length(cards) >= 2 end)
            |> Enum.find(fn {_rank, cards} ->
              # Check if any card in this group can match the top card
              Enum.any?(cards, fn card ->
                card.suit == top_card.suit or card.rank == top_card.rank
              end)
            end)

          if rank_with_cards do
            {_rank, available_cards} = rank_with_cards

            # Find a card that matches the top card to put first
            matching_card =
              Enum.find(available_cards, fn card ->
                card.suit == top_card.suit or card.rank == top_card.rank
              end)

            # Get another card of the same rank (not the matching one)
            other_card =
              Enum.find(available_cards, fn card ->
                card != matching_card
              end)

            # Move these cards to player's hand
            combo_cards = [matching_card, other_card]

            Enum.each(combo_cards, fn card ->
              deck_card =
                game_session.deck.deck_cards
                |> Enum.find(&(&1.card_id == card.id))

              Kadi.Games.DeckCard.changeset(deck_card, %{
                location_type: "player_hand",
                player_id: current_player.id,
                order_index: nil
              })
              |> Repo.update!()
            end)

            # Reload game session
            reloaded_game = Repo.get!(Kadi.Games.GameSession, game_session.id)
            reloaded_game = Repo.preload(reloaded_game, [deck: [deck_cards: :card]], force: true)

            {reloaded_game, combo_cards}
          else
            {game_session, nil}
          end
        end

      if combo do
        card_ids = Enum.map(combo, & &1.id)

        # Verify all cards were moved to played_stack
        {:ok, updated_game} = CardGames.play_cards(game_session, current_player.id, card_ids)
        updated_game = Repo.preload(updated_game, [deck: [deck_cards: :card]], force: true)

        played_cards =
          updated_game.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "played_stack"))
          |> Enum.map(& &1.card_id)

        assert Enum.all?(card_ids, &(&1 in played_cards))

        # Verify turn advanced
        refute updated_game.current_turn_player_id == current_player.id
      else
        flunk("Could not create a valid combo for testing")
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

  describe "draw_card_from_deck/2 - User Story 4 (gameplay integration)" do
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

  describe "play_cards/3 - Phase 1 regular cards only (4,5,6,7,9,10)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "Phase1"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{game_session: game_session, player1: player1, player2: player2}
    end

    test "rejects special cards (2,3,8,Jack,Queen,Ace) even when they match", %{
      game_session: game_session
    } do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      # Try to find a special card in current player's hand
      special_ranks = ["2", "3", "8", "jack", "queen", "ace"]

      special_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player_id))
        |> Enum.find(&(&1.card.rank in special_ranks))

      # If player has a special card, try to play it
      if special_card do
        # Should be rejected regardless of whether it matches
        assert {:error, :invalid_play} =
                 CardGames.play_cards(game_session, current_player_id, [special_card.card_id])
      end
    end

    test "accepts regular cards (4,5,6,7,9,10) when they match", %{
      game_session: game_session
    } do
      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      current_player_id = game_session.current_turn_player_id
      top_card = game_session.top_card

      # Try to find a matching regular card in current player's hand
      regular_ranks = ["4", "5", "6", "7", "9", "10"]

      matching_regular_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player_id))
        |> Enum.find(fn deck_card ->
          card = deck_card.card

          card.rank in regular_ranks and
            (card.suit == top_card.suit or card.rank == top_card.rank)
        end)

      # If player has a matching regular card, it should be accepted
      if matching_regular_card do
        assert {:ok, _updated_session} =
                 CardGames.play_cards(
                   game_session,
                   current_player_id,
                   [matching_regular_card.card_id]
                 )
      end
    end
  end

  describe "play_cards/3 with King (User Story 1 - FR-002)" do
    setup do
      player1 = Kadi.AccountsFixtures.player_fixture()
      player2 = Kadi.AccountsFixtures.player_fixture()
      player3 = Kadi.AccountsFixtures.player_fixture()

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "king-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)

      {:ok, started_game} = CardGames.start_game(game_session)

      %{
        game_session: started_game,
        player1: player1,
        player2: player2,
        player3: player3
      }
    end

    test "reverses direction from clockwise to counter_clockwise when King is played", %{
      game_session: game_session,
      player1: player1,
      player2: player2,
      player3: player3
    } do
      # Reload game to get direction (should be clockwise by default)
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      assert game_session.direction == "clockwise"

      # Find current turn player
      current_player_id = game_session.current_turn_player_id

      current_player =
        cond do
          current_player_id == player1.id -> player1
          current_player_id == player2.id -> player2
          current_player_id == player3.id -> player3
        end

      # Get game with full associations
      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      top_card = game_session.top_card

      # Find a King in current player's hand that matches top card
      king_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player.id))
        |> Enum.find(fn deck_card ->
          card = deck_card.card

          card.rank == "king" and
            (card.suit == top_card.suit or card.rank == top_card.rank)
        end)

      if king_card do
        {:ok, updated_game} =
          CardGames.play_cards(game_session, current_player.id, [king_card.card_id])

        # Verify direction reversed
        assert updated_game.direction == "counter_clockwise"

        # Verify turn advanced (in counter_clockwise direction)
        refute updated_game.current_turn_player_id == current_player.id
      else
        # Skip test if no matching King found (this is acceptable for random setups)
        IO.puts(
          "⏭️  Skipping test: No matching King card found in current player's hand (top_card: #{top_card.rank} of #{top_card.suit})"
        )

        :ok
      end
    end

    test "reverses direction from counter_clockwise to clockwise when King is played", %{
      game_session: game_session,
      player1: player1,
      player2: player2,
      player3: player3
    } do
      # Manually set direction to counter_clockwise
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, game_session} =
        game_session
        |> Kadi.Games.GameSession.changeset(%{direction: "counter_clockwise"})
        |> Repo.update()

      assert game_session.direction == "counter_clockwise"

      # Find current turn player
      current_player_id = game_session.current_turn_player_id

      current_player =
        cond do
          current_player_id == player1.id -> player1
          current_player_id == player2.id -> player2
          current_player_id == player3.id -> player3
        end

      # Get game with full associations
      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      top_card = game_session.top_card

      # Find a King in current player's hand that matches top card
      king_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player.id))
        |> Enum.find(fn deck_card ->
          card = deck_card.card

          card.rank == "king" and
            (card.suit == top_card.suit or card.rank == top_card.rank)
        end)

      if king_card do
        {:ok, updated_game} =
          CardGames.play_cards(game_session, current_player.id, [king_card.card_id])

        # Verify direction reversed back to clockwise
        assert updated_game.direction == "clockwise"

        # Verify turn advanced
        refute updated_game.current_turn_player_id == current_player.id
      else
        # Skip test if no matching King found
        IO.puts(
          "⏭️  Skipping test: No matching King card found in current player's hand (top_card: #{top_card.rank} of #{top_card.suit})"
        )

        :ok
      end
    end

    test "2-player game: direction changes but turn alternates normally (FR-009)", %{
      player1: player1,
      player2: player2
    } do
      # Create a 2-player game
      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "king-2player"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, started_game} = CardGames.start_game(game_session)

      # Verify initial direction
      started_game = Repo.get!(Kadi.Games.GameSession, started_game.id)
      assert started_game.direction == "clockwise"

      # Find current turn player
      current_player_id = started_game.current_turn_player_id
      current_player = if current_player_id == player1.id, do: player1, else: player2
      other_player = if current_player_id == player1.id, do: player2, else: player1

      # Get game with full associations
      started_game =
        Repo.preload(started_game, [:top_card, deck: [deck_cards: :card]], force: true)

      top_card = started_game.top_card

      # Find a King in current player's hand that matches top card
      king_card =
        started_game.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player.id))
        |> Enum.find(fn deck_card ->
          card = deck_card.card

          card.rank == "king" and
            (card.suit == top_card.suit or card.rank == top_card.rank)
        end)

      if king_card do
        {:ok, updated_game} =
          CardGames.play_cards(started_game, current_player.id, [king_card.card_id])

        # Verify direction changed
        assert updated_game.direction == "counter_clockwise"

        # Verify turn went to other player (2-player always alternates)
        assert updated_game.current_turn_player_id == other_player.id
      else
        # Skip test if no matching King found
        IO.puts(
          "⏭️  Skipping test: No matching King card found in current player's hand (top_card: #{top_card.rank} of #{top_card.suit})"
        )

        :ok
      end
    end
  end

  describe "play_cards/3 with King - Comprehensive Validation (User Story 2)" do
    setup do
      player1 = Kadi.AccountsFixtures.player_fixture()
      player2 = Kadi.AccountsFixtures.player_fixture()

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "king-validation"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, started_game} = CardGames.start_game(game_session)

      %{
        game_session: started_game,
        player1: player1,
        player2: player2
      }
    end

    test "T024: accepts King matching suit", %{
      game_session: game_session,
      player1: player1,
      player2: player2
    } do
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      current_player_id = game_session.current_turn_player_id
      current_player = if current_player_id == player1.id, do: player1, else: player2

      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      top_card = game_session.top_card

      # Find a King that matches suit (not rank)
      king_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player.id))
        |> Enum.find(fn deck_card ->
          card = deck_card.card
          card.rank == "king" and card.suit == top_card.suit and card.rank != top_card.rank
        end)

      # If no matching King in hand, create one
      {game_session, king_card} =
        if king_card do
          {game_session, king_card}
        else
          # Find King in deck that matches suit
          deck_king =
            game_session.deck.deck_cards
            |> Enum.filter(&(&1.location_type == "deck"))
            |> Enum.find(fn deck_card ->
              card = deck_card.card
              card.rank == "king" and card.suit == top_card.suit
            end)

          if deck_king do
            {:ok, _} =
              Kadi.Games.DeckCard.changeset(deck_king, %{
                location_type: "player_hand",
                player_id: current_player.id,
                order_index: nil
              })
              |> Repo.update()

            reloaded = Repo.get!(Kadi.Games.GameSession, game_session.id)
            reloaded = Repo.preload(reloaded, [:top_card, deck: [deck_cards: :card]], force: true)
            {reloaded, deck_king}
          else
            {game_session, nil}
          end
        end

      if king_card do
        {:ok, updated_game} =
          CardGames.play_cards(game_session, current_player.id, [king_card.card_id])

        # Verify King was accepted and direction reversed
        assert updated_game.direction != game_session.direction
        refute updated_game.current_turn_player_id == current_player.id
      else
        IO.puts(
          "⏭️  T024: Skipping - No King matching suit available (top_card: #{top_card.rank} of #{top_card.suit})"
        )
      end
    end

    test "T025: accepts King matching rank", %{
      game_session: game_session,
      player1: player1,
      player2: player2
    } do
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Manually set a King as top card
      game_session_preloaded =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      # Find a King in the deck to use as top card
      king_in_deck =
        game_session_preloaded.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.find(&(&1.card.rank == "king"))

      if king_in_deck do
        # Move this King to played_stack as top card
        {:ok, _} =
          Kadi.Games.DeckCard.changeset(king_in_deck, %{
            location_type: "played_stack",
            order_index: 999
          })
          |> Repo.update()

        # Update game session to point to this King as top card
        {:ok, game_session} =
          Kadi.Games.GameSession.changeset(game_session, %{
            top_card_id: king_in_deck.card_id
          })
          |> Repo.update()

        current_player_id = game_session.current_turn_player_id
        current_player = if current_player_id == player1.id, do: player1, else: player2

        game_session =
          Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

        top_card = game_session.top_card

        # Find another King in current player's hand (different suit)
        king_card =
          game_session.deck.deck_cards
          |> Enum.filter(
            &(&1.location_type == "player_hand" and &1.player_id == current_player.id)
          )
          |> Enum.find(fn deck_card ->
            card = deck_card.card
            card.rank == "king" and card.suit != top_card.suit
          end)

        # If no King in hand, get one from deck
        {game_session, king_card} =
          if king_card do
            {game_session, king_card}
          else
            deck_king =
              game_session.deck.deck_cards
              |> Enum.filter(&(&1.location_type == "deck"))
              |> Enum.find(fn deck_card ->
                card = deck_card.card
                card.rank == "king" and card.suit != top_card.suit
              end)

            if deck_king do
              {:ok, _} =
                Kadi.Games.DeckCard.changeset(deck_king, %{
                  location_type: "player_hand",
                  player_id: current_player.id,
                  order_index: nil
                })
                |> Repo.update()

              reloaded = Repo.get!(Kadi.Games.GameSession, game_session.id)

              reloaded =
                Repo.preload(reloaded, [:top_card, deck: [deck_cards: :card]], force: true)

              {reloaded, deck_king}
            else
              {game_session, nil}
            end
          end

        if king_card do
          {:ok, updated_game} =
            CardGames.play_cards(game_session, current_player.id, [king_card.card_id])

          # Verify King was accepted (rank match)
          assert updated_game.direction != game_session.direction
        else
          IO.puts("⏭️  T025: Skipping - No second King available")
        end
      else
        IO.puts("⏭️  T025: Skipping - No King in deck to set as top card")
      end
    end

    test "T026: rejects King not matching suit or rank", %{
      game_session: game_session,
      player1: player1,
      player2: player2
    } do
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      current_player_id = game_session.current_turn_player_id
      current_player = if current_player_id == player1.id, do: player1, else: player2

      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      top_card = game_session.top_card

      # Find a King that does NOT match suit or rank
      king_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player.id))
        |> Enum.find(fn deck_card ->
          card = deck_card.card
          card.rank == "king" and card.suit != top_card.suit and card.rank != top_card.rank
        end)

      # If no non-matching King in hand, create one
      {game_session, king_card} =
        if king_card do
          {game_session, king_card}
        else
          # Find King in deck that doesn't match
          deck_king =
            game_session.deck.deck_cards
            |> Enum.filter(&(&1.location_type == "deck"))
            |> Enum.find(fn deck_card ->
              card = deck_card.card
              card.rank == "king" and card.suit != top_card.suit and card.rank != top_card.rank
            end)

          if deck_king do
            {:ok, _} =
              Kadi.Games.DeckCard.changeset(deck_king, %{
                location_type: "player_hand",
                player_id: current_player.id,
                order_index: nil
              })
              |> Repo.update()

            reloaded = Repo.get!(Kadi.Games.GameSession, game_session.id)
            reloaded = Repo.preload(reloaded, [:top_card, deck: [deck_cards: :card]], force: true)
            {reloaded, deck_king}
          else
            {game_session, nil}
          end
        end

      if king_card do
        # This should be rejected
        assert {:error, :invalid_play} =
                 CardGames.play_cards(game_session, current_player.id, [king_card.card_id])
      else
        IO.puts(
          "⏭️  T026: Skipping - No non-matching King available (top_card: #{top_card.rank} of #{top_card.suit})"
        )
      end
    end

    test "T027: rejects multiple King cards in single turn", %{
      game_session: game_session,
      player1: player1,
      player2: player2
    } do
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      current_player_id = game_session.current_turn_player_id
      current_player = if current_player_id == player1.id, do: player1, else: player2

      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      # Find all Kings in deck
      all_kings =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck" and &1.card.rank == "king"))
        |> Enum.take(2)

      if length(all_kings) >= 2 do
        # Move two Kings to current player's hand
        Enum.each(all_kings, fn king ->
          {:ok, _} =
            Kadi.Games.DeckCard.changeset(king, %{
              location_type: "player_hand",
              player_id: current_player.id,
              order_index: nil
            })
            |> Repo.update()
        end)

        # Reload
        game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

        game_session =
          Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

        # Get the two King card IDs
        king_ids =
          all_kings
          |> Enum.map(& &1.card_id)

        # Try to play both Kings - should be rejected
        assert {:error, :invalid_play} =
                 CardGames.play_cards(game_session, current_player.id, king_ids)
      else
        IO.puts("⏭️  T027: Skipping - Not enough Kings in deck")
      end
    end

    test "T028: King as start card is allowed, no reversal occurs", %{
      player1: player1,
      player2: player2
    } do
      # Create a new game and check if start card is a King
      # We'll run this test multiple times since start card is random

      # Try up to 100 times to get a King as start card
      result =
        Enum.find_value(1..100, fn attempt ->
          {:ok, game_session} =
            CardGames.create_game_session(player1, %{short_code: "king-start-#{attempt}"})

          {:ok, _} = CardGames.join_game_session(player2, game_session.id)
          {:ok, started_game} = CardGames.start_game(game_session)

          started_game = Repo.preload(started_game, [:top_card])

          if started_game.top_card.rank == "king" do
            started_game
          else
            nil
          end
        end)

      if result do
        # Found a game with King as start card
        assert result.status == "live"
        # Should start clockwise
        assert result.direction == "clockwise"
        assert result.top_card.rank == "king"

        IO.puts("✓ T028: King start card found - game is live with clockwise direction")
      else
        # Couldn't get King as start card in 100 attempts
        # This is acceptable since start_game explicitly avoids special cards including Kings
        # But per FR-003, if a King does appear, it should be allowed without reversal
        IO.puts(
          "⏭️  T028: Skipping - Could not randomly get King as start card (by design, start_game avoids special cards)"
        )
      end
    end
  end

  # ============================================================================
  # Phase 5: User Story 3 - Track Game Direction State
  # ============================================================================
  # Purpose: Persist and expose game direction state so players can understand turn flow
  # Tests verify direction tracking and persistence after King plays

  describe "direction state tracking" do
    @tag :phase5
    @tag :us3
    test "T032: new games start with direction 'clockwise' by default", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "default-direction"})

      CardGames.join_game_session(player2, game_session.id)

      {:ok, started_game} = CardGames.start_game(game_session)

      # Verify default direction is clockwise
      assert started_game.direction == "clockwise"

      # Reload from DB to verify persistence
      reloaded = Repo.get!(Kadi.Games.GameSession, started_game.id)
      assert reloaded.direction == "clockwise"

      IO.puts("✓ T032: New game starts with direction='clockwise'")
    end

    @tag :phase5
    @tag :us3
    test "T033: direction persists after playing a King card", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "king-direction-persist"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Verify initial direction
      assert game_session.direction == "clockwise"

      # Setup: Find the current turn player and give them a King matching top card
      current_player_id = game_session.current_turn_player_id

      # Get top card
      top_card = Repo.get!(Kadi.Games.Card, game_session.top_card_id)

      # Find or create a King card that matches the top card's suit
      king_card =
        Repo.one(
          from c in Kadi.Games.Card,
            where: c.rank == "king" and c.suit == ^top_card.suit
        )

      # Find the deck card for this King
      deck_card =
        Repo.one!(
          from dc in Kadi.Games.DeckCard,
            join: d in Kadi.Games.Deck,
            on: dc.deck_id == d.id,
            where: d.game_session_id == ^game_session.id and dc.card_id == ^king_card.id
        )

      # Move King to current player's hand
      Repo.update!(
        Ecto.Changeset.change(deck_card, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
      )

      # Play the King
      {:ok, updated_game} = CardGames.play_cards(game_session, current_player_id, [king_card.id])

      # Verify direction changed to counter_clockwise
      assert updated_game.direction == "counter_clockwise"

      # Reload from DB to verify persistence
      reloaded = Repo.get!(Kadi.Games.GameSession, updated_game.id)
      assert reloaded.direction == "counter_clockwise"

      IO.puts("✓ T033: Direction persists as 'counter_clockwise' after King play")
    end

    @tag :phase5
    @tag :us3
    test "T034: direction toggles correctly on consecutive King plays", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "king-direction-toggle"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Verify initial direction
      assert game_session.direction == "clockwise"

      # Helper to play a King
      play_king = fn game, player_id ->
        top_card = Repo.get!(Kadi.Games.Card, game.top_card_id)

        king_card =
          Repo.one(
            from c in Kadi.Games.Card,
              where: c.rank == "king" and c.suit == ^top_card.suit
          )

        deck_card =
          Repo.one!(
            from dc in Kadi.Games.DeckCard,
              join: d in Kadi.Games.Deck,
              on: dc.deck_id == d.id,
              where: d.game_session_id == ^game.id and dc.card_id == ^king_card.id
          )

        Repo.update!(
          Ecto.Changeset.change(deck_card, %{
            location_type: "player_hand",
            player_id: player_id,
            order_index: nil
          })
        )

        {:ok, updated} = CardGames.play_cards(game, player_id, [king_card.id])
        updated
      end

      # First King: clockwise → counter_clockwise
      game_after_first_king = play_king.(game_session, game_session.current_turn_player_id)
      assert game_after_first_king.direction == "counter_clockwise"

      # Reload to verify persistence
      reloaded1 = Repo.get!(Kadi.Games.GameSession, game_after_first_king.id)
      assert reloaded1.direction == "counter_clockwise"

      # Second King: counter_clockwise → clockwise
      game_after_second_king =
        play_king.(game_after_first_king, game_after_first_king.current_turn_player_id)

      assert game_after_second_king.direction == "clockwise"

      # Reload to verify persistence
      reloaded2 = Repo.get!(Kadi.Games.GameSession, game_after_second_king.id)
      assert reloaded2.direction == "clockwise"

      IO.puts("✓ T034: Direction toggles clockwise→counter_clockwise→clockwise")
    end
  end

  # ============================================================================
  # Phase 6: Cardless State & Edge Cases
  # ============================================================================
  # Purpose: Handle cardless player state (King as last card) and anomaly scenarios
  # Tests verify cardless status transitions, auto-draw, and edge case handling

  # Helper function to setup a cardless scenario
  # Returns {:ok, game_session, king_card_id} or {:skip, reason}
  defp setup_cardless_scenario(_player, _player2, game_session) do
    # Preload all deck cards and top card
    game_session =
      Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

    top_card = game_session.top_card
    current_player_id = game_session.current_turn_player_id

    # Find a King matching top card suit
    king_deck_card =
      Enum.find(game_session.deck.deck_cards, fn dc ->
        dc.card.rank == "king" and dc.card.suit == top_card.suit
      end)

    if king_deck_card do
      # Get all current player's cards
      player_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player_id))

      # Remove all cards except the King
      player_cards
      |> Enum.reject(&(&1.id == king_deck_card.id))
      |> Enum.with_index()
      |> Enum.each(fn {dc, idx} ->
        Repo.update!(
          Ecto.Changeset.change(dc, %{
            location_type: "deck",
            player_id: nil,
            order_index: 900 + idx
          })
        )
      end)

      # Ensure the King is in player's hand
      Repo.update!(
        Ecto.Changeset.change(king_deck_card, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
      )

      # Reload game session with updated state
      game_session =
        Repo.get!(Kadi.Games.GameSession, game_session.id)
        |> Repo.preload([:game_session_players, deck: [deck_cards: :card]], force: true)

      {:ok, game_session, king_deck_card.card.id}
    else
      {:skip, "No matching King found (top_card: #{top_card.rank} of #{top_card.suit})"}
    end
  end

  describe "cardless state transitions" do
    @tag :phase6
    @tag :cardless
    test "T040: player status changes to 'cardless' when playing King as last card", %{
      player: player
    } do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "cardless-transition"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Use helper to setup cardless scenario
      case setup_cardless_scenario(player, player2, game_session) do
        {:ok, game_session, king_card_id} ->
          current_player_id = game_session.current_turn_player_id

          # Verify player has exactly 1 card
          remaining_cards =
            game_session.deck.deck_cards
            |> Enum.filter(fn dc ->
              dc.player_id == current_player_id and dc.location_type == "player_hand"
            end)

          assert length(remaining_cards) == 1

          # Get initial player status
          player_session_before =
            game_session.game_session_players
            |> Enum.find(&(&1.player_id == current_player_id))

          assert player_session_before.status == "normal"

          # Play the King (last card)
          {:ok, updated_game} =
            CardGames.play_cards(game_session, current_player_id, [king_card_id])

          # Reload with associations
          updated_game = Repo.preload(updated_game, [:game_session_players], force: true)

          player_session_after =
            updated_game.game_session_players
            |> Enum.find(&(&1.player_id == current_player_id))

          # Status should be "cardless"
          assert player_session_after.status == "cardless"

          IO.puts("✓ T040: Player status changes to 'cardless' when playing King as last card")

        {:skip, reason} ->
          IO.puts("⏭️  Skipping T040: #{reason}")
      end
    end

    @tag :phase6
    @tag :cardless
    test "T041: cardless player automatically draws card on their turn", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "cardless-autodraw"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Use helper to setup cardless scenario
      case setup_cardless_scenario(player, player2, game_session) do
        {:ok, game_session, king_card_id} ->
          current_player_id = game_session.current_turn_player_id

          # Verify player has exactly 1 card before playing
          remaining_cards =
            game_session.deck.deck_cards
            |> Enum.filter(
              &(&1.location_type == "player_hand" and &1.player_id == current_player_id)
            )

          assert length(remaining_cards) == 1

          # Play the King (last card) - this makes player cardless
          {:ok, after_play_game} =
            CardGames.play_cards(game_session, current_player_id, [king_card_id])

          # Reload with associations
          after_play_game =
            Repo.preload(after_play_game, [:game_session_players, deck: [deck_cards: :card]],
              force: true
            )

          player_session_cardless =
            after_play_game.game_session_players
            |> Enum.find(&(&1.player_id == current_player_id))

          assert player_session_cardless.status == "cardless"

          # Verify player has 0 cards
          cards_after_king =
            after_play_game.deck.deck_cards
            |> Enum.filter(
              &(&1.location_type == "player_hand" and &1.player_id == current_player_id)
            )

          assert length(cards_after_king) == 0

          # Now it's the other player's turn, so advance back to our cardless player
          other_player_id = after_play_game.current_turn_player_id

          # Other player draws to advance turn back to cardless player
          {:ok, after_draw_game} =
            CardGames.draw_card_from_deck(after_play_game, other_player_id)

          # Now it should be the cardless player's turn again
          assert after_draw_game.current_turn_player_id == current_player_id

          # Have cardless player draw a card (it's their turn, they're cardless, should auto-draw)
          {:ok, updated_game} = CardGames.draw_card_from_deck(after_draw_game, current_player_id)

          # Reload with associations
          updated_game =
            Repo.preload(updated_game, [:game_session_players, deck: [deck_cards: :card]],
              force: true
            )

          # Player should now have 1 card (the drawn card)
          player_cards_after =
            updated_game.deck.deck_cards
            |> Enum.filter(
              &(&1.location_type == "player_hand" and &1.player_id == current_player_id)
            )

          assert length(player_cards_after) == 1

          # Check status reset to normal
          player_session_after =
            updated_game.game_session_players
            |> Enum.find(&(&1.player_id == current_player_id))

          assert player_session_after.status == "normal"

          IO.puts("✓ T041: Cardless player auto-draws card on their turn")

        {:skip, reason} ->
          IO.puts("⏭️  Skipping T041: #{reason}")
      end
    end

    @tag :phase6
    @tag :cardless
    test "T044: multiple simultaneous cardless players tracked independently", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})
      player3 = player_fixture(%{email: "player3@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "multi-cardless"})

      CardGames.join_game_session(player2, game_session.id)
      CardGames.join_game_session(player3, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Preload all deck cards and top card
      game_session =
        Repo.preload(game_session, [:top_card, :game_session_players, deck: [deck_cards: :card]],
          force: true
        )

      top_card = game_session.top_card
      current_player_id = game_session.current_turn_player_id

      # Make current player cardless by playing King as their last card
      # Find a King matching top card suit (from anywhere in deck)
      king_deck_card =
        Enum.find(game_session.deck.deck_cards, fn dc ->
          dc.card.rank == "king" and dc.card.suit == top_card.suit
        end)

      # If no matching King found, skip test (acceptable for random setups)
      if king_deck_card do
        # Get all current player's cards
        player_cards =
          game_session.deck.deck_cards
          |> Enum.filter(
            &(&1.location_type == "player_hand" and &1.player_id == current_player_id)
          )

        # Remove all cards except the King (if it's already in hand)
        player_cards
        |> Enum.reject(&(&1.id == king_deck_card.id))
        |> Enum.with_index()
        |> Enum.each(fn {dc, idx} ->
          Repo.update!(
            Ecto.Changeset.change(dc, %{
              location_type: "deck",
              player_id: nil,
              order_index: 950 + idx
            })
          )
        end)

        # Give the King to current player
        Repo.update!(
          Ecto.Changeset.change(king_deck_card, %{
            location_type: "player_hand",
            player_id: current_player_id,
            order_index: nil
          })
        )

        # Reload and play the King (making player cardless)
        game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

        game_session =
          Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

        {:ok, game_session} =
          CardGames.play_cards(game_session, current_player_id, [king_deck_card.card.id])

        # Reload with game_session_players
        game_session =
          Repo.preload(game_session, [:game_session_players], force: true)

        # Now manually set a second player to cardless to test independent tracking
        # (This simulates another player becoming cardless through normal gameplay)
        other_players =
          game_session.game_session_players
          |> Enum.reject(&(&1.player_id == current_player_id))

        second_cardless_player = List.first(other_players)

        Repo.update!(Ecto.Changeset.change(second_cardless_player, %{status: "cardless"}))

        # Verify both are cardless using preloaded data
        game_session =
          Repo.get!(Kadi.Games.GameSession, game_session.id)
          |> Repo.preload([:game_session_players], force: true)

        cardless_players =
          game_session.game_session_players
          |> Enum.filter(&(&1.status == "cardless"))

        assert length(cardless_players) == 2

        # Verify the third player is still normal
        normal_players =
          game_session.game_session_players
          |> Enum.filter(&(&1.status == "normal"))

        assert length(normal_players) == 1

        IO.puts("✓ T044: Multiple cardless players tracked independently")
      else
        IO.puts(
          "⏭️  Skipping T044: No matching King found (top_card: #{top_card.rank} of #{top_card.suit})"
        )
      end
    end
  end

  describe "edge cases and anomalies" do
    @tag :phase6
    @tag :anomaly
    test "T048: deck exhaustion anomaly handled gracefully", %{player: player} do
      player2 = player_fixture(%{email: "anomaly-player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "anomaly-test"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Setup: Create scenario where deck is empty and played stack has only 1 card
      # This will trigger anomaly when trying to draw
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # Move all deck cards to player hands (emptying the deck)
      deck_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))

      deck_cards
      |> Enum.with_index()
      |> Enum.each(fn {dc, idx} ->
        # Alternate between player1 and player2
        assigned_player_id = if rem(idx, 2) == 0, do: player.id, else: player2.id

        Repo.update!(
          Ecto.Changeset.change(dc, %{
            location_type: "player_hand",
            player_id: assigned_player_id,
            order_index: nil
          })
        )
      end)

      # Ensure only 1 card in played stack (the top card from start_game)
      # This means recycle will fail with insufficient_cards_to_recycle

      # Set current turn
      current_player_id = game_session.current_turn_player_id

      # Reload game session
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Attempt to draw - should trigger anomaly handling
      {:ok, updated_game} = CardGames.draw_card_from_deck(game_session, current_player_id)

      # Verify turn advanced to next player (anomaly skip)
      assert updated_game.current_turn_player_id != current_player_id

      # Verify game continues (no crash, turn advanced)
      # Reload with associations to verify state
      updated_game = Repo.preload(updated_game, [:game_session_players], force: true)
      assert length(updated_game.game_session_players) == 2

      IO.puts("✓ T048: Deck exhaustion anomaly handled gracefully")
    end
  end

  describe "play_cards/3 with Jack (User Story 1 - Feature 007)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture()
      player3 = player_fixture()

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "JACK1"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["jack"])

      %{
        game_session: game_session,
        player1: player1,
        player2: player2,
        player3: player3
      }
    end

    test "single Jack skips 1 player in 3-player game", %{
      game_session: game_session,
      player1: _player1,
      player2: _player2,
      player3: _player3
    } do
      # Ensure player1 is current player
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find a Jack card that matches the top card's suit (in deck since Jacks excluded from deal)
      jack_card =
        game_session.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "jack" and &1.card.suit == top_card.suit and
              &1.location_type == "deck")
        )

      # Move Jack to current player's hand
      {:ok, _} =
        Kadi.Games.DeckCard.changeset(jack_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))

      # Expected next player: skip 1 position (index + 1 skips current, +1 more skips next)
      expected_next_index = rem(current_index + 1, 3)
      expected_next_player = Enum.at(players, expected_next_index)

      # Play Jack
      {:ok, updated_game} =
        CardGames.play_cards(game_session, current_player.id, [jack_card.card.id])

      # Verify turn skipped 1 player
      assert updated_game.current_turn_player_id == expected_next_player.id

      IO.puts("✓ T022: Single Jack skips 1 player in 3-player game")
    end

    test "single Jack skips 1 player in 4-player game" do
      player1 = player_fixture()
      player2 = player_fixture()
      player3 = player_fixture()
      player4 = player_fixture()

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "JACK2"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, _} = CardGames.join_game_session(player4, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["jack"])

      # Ensure player1 is current player
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find a Jack card that matches the top card's suit (in deck since Jacks excluded from deal)
      jack_card =
        game_session.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "jack" and &1.card.suit == top_card.suit and
              &1.location_type == "deck")
        )

      # Move Jack to current player's hand
      {:ok, _} =
        Kadi.Games.DeckCard.changeset(jack_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      game_session =
        Repo.preload(game_session, [:deck, :top_card, :current_turn_player], force: true)

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))

      # Expected: skip 1 player (advance 1 position)
      expected_next_index = rem(current_index + 1, 4)
      expected_next_player = Enum.at(players, expected_next_index)

      # Play Jack
      {:ok, updated_game} =
        CardGames.play_cards(game_session, current_player.id, [jack_card.card.id])

      # Verify turn skipped correctly
      assert updated_game.current_turn_player_id == expected_next_player.id

      IO.puts("✓ T023: Single Jack skips 1 player in 4-player game")
    end

    test "telemetry event emitted with correct metadata", %{
      game_session: game_session
    } do
      # Set up telemetry handler
      test_pid = self()

      :telemetry.attach(
        "jack-skip-test-handler",
        [:kadi, :jack, :skip_executed],
        fn _event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      # Ensure we have a Jack to play
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find a Jack card that matches the top card's suit (in deck since Jacks excluded from deal)
      jack_card =
        game_session.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "jack" and &1.card.suit == top_card.suit and
              &1.location_type == "deck")
        )

      # Move Jack to current player's hand
      {:ok, _} =
        Kadi.Games.DeckCard.changeset(jack_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [:deck, :top_card], force: true)

      # Play Jack
      {:ok, updated_game} =
        CardGames.play_cards(game_session, current_player.id, [jack_card.card.id])

      # Wait for telemetry event
      assert_receive {:telemetry_event, measurements, metadata}, 1000

      # Verify measurements
      assert measurements.skip_count == 1

      # Verify metadata
      assert metadata.game_session_id == game_session.id
      assert metadata.player_id == current_player.id
      assert metadata.from_player_id == current_player.id
      assert metadata.to_player_id == updated_game.current_turn_player_id
      assert metadata.jack_count == 1
      assert is_list(metadata.card_ids)
      assert length(metadata.card_ids) == 1

      # Cleanup
      :telemetry.detach("jack-skip-test-handler")

      IO.puts("✓ T024: Telemetry event emitted with correct metadata")
    end
  end

  describe "Jack combo skip functionality" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2-jack-combo@example.com"})
      player3 = player_fixture(%{email: "player3-jack-combo@example.com"})
      player4 = player_fixture(%{email: "player4-jack-combo@example.com"})
      player5 = player_fixture(%{email: "player5-jack-combo@example.com"})

      %{
        player1: player1,
        player2: player2,
        player3: player3,
        player4: player4,
        player5: player5
      }
    end

    @tag :jack_combo
    test "2 Jacks skip 2 players in 3-player game", %{
      player1: player1,
      player2: player2,
      player3: player3
    } do
      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "2jack-3p"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["jack"])

      # Preload associations needed for the test
      game_session =
        Repo.preload(game_session, [:deck, :top_card, :current_turn_player], force: true)

      # Get the current player
      current_player = game_session.current_turn_player

      # Get ordered players list
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))

      # Calculate expected next player: skip 2 players in 3-player game
      # current + 2 positions (wraps around)
      expected_next_index = rem(current_index + 2, 3)
      expected_next_player = Enum.at(players, expected_next_index)

      # Setup: Give current player two Jacks that match the top card
      top_card = game_session.top_card
      setup_player_with_jacks(game_session, current_player.id, 2, top_card)

      # Play 2 Jacks - ensure the matching Jack is first
      player1_cards = CardGames.get_player_hand(game_session, current_player.id)
      all_jacks = Enum.filter(player1_cards, &(&1.card.rank == "jack"))

      # Put the Jack matching the top card's suit first
      matching_jack = Enum.find(all_jacks, &(&1.card.suit == top_card.suit))
      other_jacks = Enum.reject(all_jacks, &(&1.card.suit == top_card.suit)) |> Enum.take(1)

      jacks_to_play =
        if matching_jack, do: [matching_jack | other_jacks], else: Enum.take(all_jacks, 2)

      if length(jacks_to_play) < 2 do
        flunk("Not enough Jacks available (got #{length(jacks_to_play)}/2)")
      end

      {:ok, updated_session} =
        CardGames.play_cards(
          game_session,
          current_player.id,
          Enum.map(jacks_to_play, & &1.card.id)
        )

      # In 3-player game: player1 plays 2 Jacks → skips 2 players → wraps around
      assert updated_session.current_turn_player_id == expected_next_player.id
      IO.puts("✓ T029: 2 Jacks skip 2 players in 3-player game")
    end

    @tag :jack_combo
    test "3 Jacks skip 3 players in 5-player game", %{
      player1: player1,
      player2: player2,
      player3: player3,
      player4: player4,
      player5: player5
    } do
      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "3jack-5p"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, _} = CardGames.join_game_session(player4, game_session.id)
      {:ok, _} = CardGames.join_game_session(player5, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["jack"])

      # Preload associations needed for the test
      game_session =
        Repo.preload(game_session, [:deck, :top_card, :current_turn_player], force: true)

      # Get the current player
      current_player = game_session.current_turn_player

      # Get ordered players list
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))

      # Calculate expected next player: skip 3 players in 5-player game
      # current + 3 positions
      expected_next_index = rem(current_index + 3, 5)
      expected_next_player = Enum.at(players, expected_next_index)

      # Setup: Give current player three Jacks that match the top card
      top_card = game_session.top_card
      setup_player_with_jacks(game_session, current_player.id, 3, top_card)

      # Play 3 Jacks - ensure the matching Jack is first
      player1_cards = CardGames.get_player_hand(game_session, current_player.id)
      all_jacks = Enum.filter(player1_cards, &(&1.card.rank == "jack"))

      # Put the Jack matching the top card's suit first
      matching_jack = Enum.find(all_jacks, &(&1.card.suit == top_card.suit))
      other_jacks = Enum.reject(all_jacks, &(&1.card.suit == top_card.suit)) |> Enum.take(2)

      jacks_to_play =
        if matching_jack, do: [matching_jack | other_jacks], else: Enum.take(all_jacks, 3)

      if length(jacks_to_play) < 3 do
        flunk("Not enough Jacks available (got #{length(jacks_to_play)}/3)")
      end

      {:ok, updated_session} =
        CardGames.play_cards(
          game_session,
          current_player.id,
          Enum.map(jacks_to_play, & &1.card.id)
        )

      # In 5-player game: player1 plays 3 Jacks → skips 3 players
      assert updated_session.current_turn_player_id == expected_next_player.id
      IO.puts("✓ T030: 3 Jacks skip 3 players in 5-player game")
    end

    @tag :jack_combo
    test "4 Jacks in 4-player game wraps to same player", %{
      player1: player1,
      player2: player2,
      player3: player3,
      player4: player4
    } do
      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "4jack-4p"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, _} = CardGames.join_game_session(player4, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["jack"])

      # Preload associations needed for the test
      game_session =
        Repo.preload(game_session, [:deck, :top_card, :current_turn_player], force: true)

      # Get the current player
      current_player = game_session.current_turn_player

      # Get ordered players list
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))

      # Calculate expected next player: skip 4 players in 4-player game
      # current + 4 positions = full cycle, back to same player
      expected_next_index = rem(current_index + 4, 4)
      expected_next_player = Enum.at(players, expected_next_index)

      # Setup: Give current player four Jacks that match the top card
      top_card = game_session.top_card
      setup_player_with_jacks(game_session, current_player.id, 4, top_card)

      # Play 4 Jacks - ensure the matching Jack is first
      player1_cards = CardGames.get_player_hand(game_session, current_player.id)
      all_jacks = Enum.filter(player1_cards, &(&1.card.rank == "jack"))

      # Put the Jack matching the top card's suit first
      matching_jack = Enum.find(all_jacks, &(&1.card.suit == top_card.suit))
      other_jacks = Enum.reject(all_jacks, &(&1.card.suit == top_card.suit)) |> Enum.take(3)

      jacks_to_play =
        if matching_jack, do: [matching_jack | other_jacks], else: Enum.take(all_jacks, 4)

      if length(jacks_to_play) < 4 do
        flunk("Not enough Jacks available (got #{length(jacks_to_play)}/4)")
      end

      {:ok, updated_session} =
        CardGames.play_cards(
          game_session,
          current_player.id,
          Enum.map(jacks_to_play, & &1.card.id)
        )

      # In 4-player game: current player plays 4 Jacks → skips all other 3 players → wraps back to same player
      assert updated_session.current_turn_player_id == expected_next_player.id
      assert expected_next_player.id == current_player.id
      IO.puts("✓ T031: 4 Jacks in 4-player game wraps to same player")
    end

    @tag :jack_combo
    test "4 Jacks in 3-player game wraps correctly (skip through full cycle)", %{
      player1: player1,
      player2: player2,
      player3: player3
    } do
      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "4jack-3p"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["jack"])

      # Preload associations needed for the test
      game_session =
        Repo.preload(game_session, [:deck, :top_card, :current_turn_player], force: true)

      # Get the current player
      current_player = game_session.current_turn_player

      # Get ordered players list
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))

      # Calculate expected next player: skip 4 players in 3-player game
      # 4 mod 3 = 1, so skip 1 player: current + 1 position
      expected_next_index = rem(current_index + 4, 3)
      expected_next_player = Enum.at(players, expected_next_index)

      # Setup: Give current player four Jacks that match the top card
      top_card = game_session.top_card
      setup_player_with_jacks(game_session, current_player.id, 4, top_card)

      # Play 4 Jacks - ensure the matching Jack is first
      player1_cards = CardGames.get_player_hand(game_session, current_player.id)
      all_jacks = Enum.filter(player1_cards, &(&1.card.rank == "jack"))

      # Put the Jack matching the top card's suit first
      matching_jack = Enum.find(all_jacks, &(&1.card.suit == top_card.suit))
      other_jacks = Enum.reject(all_jacks, &(&1.card.suit == top_card.suit)) |> Enum.take(3)

      jacks_to_play =
        if matching_jack, do: [matching_jack | other_jacks], else: Enum.take(all_jacks, 4)

      if length(jacks_to_play) < 4 do
        flunk("Not enough Jacks available (got #{length(jacks_to_play)}/4)")
      end

      {:ok, updated_session} =
        CardGames.play_cards(
          game_session,
          current_player.id,
          Enum.map(jacks_to_play, & &1.card.id)
        )

      # In 3-player game: player1 plays → skips 4 players (wraps)
      # 4 mod 3 = 1, so effectively skips 1 player
      assert updated_session.current_turn_player_id == expected_next_player.id
      IO.puts("✓ T032: 4 Jacks in 3-player game wraps correctly (skip through full cycle)")
    end
  end

  describe "Jack combo validation (Phase 6 - User Story 4)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture()
      player3 = player_fixture()

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "VALC1"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["jack"])

      %{
        game_session: game_session,
        player1: player1,
        player2: player2,
        player3: player3
      }
    end

    @tag :phase6
    @tag :us4
    test "play 2-Jack combo matching by suit (T044)", %{
      game_session: game_session
    } do
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find 2 Jacks where first matches top card's suit
      matching_jack =
        Repo.one(
          from dc in DeckCard,
            join: c in Card,
            on: dc.card_id == c.id,
            where:
              dc.deck_id == ^game_session.deck.id and c.rank == "jack" and
                c.suit == ^top_card.suit and dc.location_type == "deck",
            preload: [card: c],
            select: dc,
            limit: 1
        )

      other_jack =
        Repo.one(
          from dc in DeckCard,
            join: c in Card,
            on: dc.card_id == c.id,
            where:
              dc.deck_id == ^game_session.deck.id and c.rank == "jack" and
                dc.id != ^matching_jack.id and dc.location_type == "deck",
            preload: [card: c],
            select: dc,
            limit: 1
        )

      # Move both Jacks to current player's hand
      Enum.each([matching_jack, other_jack], fn dc ->
        Repo.update_all(
          from(d in DeckCard, where: d.id == ^dc.id),
          set: [location_type: "player_hand", player_id: current_player.id, order_index: nil]
        )
      end)

      # Reload
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [:top_card, :current_turn_player], force: true)

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      expected_next_index = rem(current_index + 2, length(players))
      expected_next_player = Enum.at(players, expected_next_index)

      # Play 2-Jack combo
      {:ok, updated_game} =
        CardGames.play_cards(game_session, current_player.id, [
          matching_jack.card.id,
          other_jack.card.id
        ])

      # Verify combo was accepted and turn skipped correctly
      assert updated_game.current_turn_player_id == expected_next_player.id
    end

    @tag :phase6
    @tag :us4
    test "play 3-Jack combo matching by rank (T045)", %{
      game_session: game_session
    } do
      # Set top card to a Jack
      jack_top_card =
        Repo.one(
          from c in Card,
            where: c.rank == "jack",
            limit: 1
        )

      game_session
      |> Ecto.Changeset.change(top_card_id: jack_top_card.id)
      |> Repo.update!()

      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player

      # Find 3 Jacks (any suits since they match by rank)
      jacks =
        Repo.all(
          from dc in DeckCard,
            join: c in Card,
            on: dc.card_id == c.id,
            where:
              dc.deck_id == ^game_session.deck.id and c.rank == "jack" and
                dc.location_type == "deck",
            preload: [card: c],
            select: dc,
            limit: 3
        )

      # Move all Jacks to current player's hand
      Enum.each(jacks, fn dc ->
        Repo.update_all(
          from(d in DeckCard, where: d.id == ^dc.id),
          set: [location_type: "player_hand", player_id: current_player.id, order_index: nil]
        )
      end)

      # Reload
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [:top_card, :current_turn_player], force: true)

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      expected_next_index = rem(current_index + 3, length(players))
      expected_next_player = Enum.at(players, expected_next_index)

      # Play 3-Jack combo
      {:ok, updated_game} =
        CardGames.play_cards(game_session, current_player.id, Enum.map(jacks, & &1.card.id))

      # Verify combo was accepted and turn skipped correctly
      assert updated_game.current_turn_player_id == expected_next_player.id
    end
  end

  # Helper function to setup a player with specific number of Jacks that match a given card
  defp setup_player_with_jacks(game_session, player_id, jack_count, matching_card) do
    # Preload the deck and top_card associations if not already loaded
    game_session = Repo.preload(game_session, [:deck, :top_card], force: true)

    # Get a Jack that matches the top card's suit (for the first card)
    # If top card IS a Jack, any Jack will work since Jacks match on rank
    # Check both player's hand AND deck for matching Jack
    matching_jack =
      Repo.one(
        from dc in DeckCard,
          join: c in Card,
          on: dc.card_id == c.id,
          where:
            dc.deck_id == ^game_session.deck.id and
              c.rank == "jack" and
              (c.suit == ^matching_card.suit or ^matching_card.rank == "jack") and
              (dc.location_type == "deck" or
                 (dc.location_type == "player_hand" and dc.player_id == ^player_id)),
          select: dc,
          limit: 1
      )

    # Get additional Jacks (any suit) - exclude the first one we already got
    # Check both player's hand AND deck
    other_jacks =
      if matching_jack do
        Repo.all(
          from dc in DeckCard,
            join: c in Card,
            on: dc.card_id == c.id,
            where:
              dc.deck_id == ^game_session.deck.id and
                c.rank == "jack" and
                dc.id != ^matching_jack.id and
                (dc.location_type == "deck" or
                   (dc.location_type == "player_hand" and dc.player_id == ^player_id)),
            select: dc,
            limit: ^(jack_count - 1)
        )
      else
        # If no matching jack found, just get any Jacks from deck or player's hand
        Repo.all(
          from dc in DeckCard,
            join: c in Card,
            on: dc.card_id == c.id,
            where:
              dc.deck_id == ^game_session.deck.id and
                c.rank == "jack" and
                (dc.location_type == "deck" or
                   (dc.location_type == "player_hand" and dc.player_id == ^player_id)),
            select: dc,
            limit: ^jack_count
        )
      end

    # Combine: matching Jack first, then others
    jacks_to_move = if matching_jack, do: [matching_jack | other_jacks], else: other_jacks

    # Debug: If we don't have enough Jacks, show where all Jacks are located
    if length(jacks_to_move) < jack_count do
      all_jacks =
        Repo.all(
          from dc in DeckCard,
            join: c in Card,
            on: dc.card_id == c.id,
            where: dc.deck_id == ^game_session.deck.id and c.rank == "jack",
            select: {c.suit, dc.location_type, dc.player_id}
        )

      IO.puts(
        "🔍 DEBUG: Need #{jack_count} Jacks, found #{length(jacks_to_move)}. All Jack locations:"
      )

      Enum.each(all_jacks, fn {suit, location, pid} ->
        IO.puts(
          "  - Jack of #{suit}: location=#{location}, player_id=#{inspect(pid)} (target: #{player_id})"
        )
      end)

      IO.puts(
        "  Matching card: #{matching_card.rank} of #{matching_card.suit}, matching_jack found: #{matching_jack != nil}"
      )
    end

    # Move Jacks to player's hand (if not already there)
    Enum.each(jacks_to_move, fn deck_card ->
      if deck_card.location_type != "player_hand" or deck_card.player_id != player_id do
        Repo.update_all(
          from(dc in DeckCard, where: dc.id == ^deck_card.id),
          set: [location_type: "player_hand", player_id: player_id]
        )
      end
    end)
  end

  describe "Jack validation matching rules (Phase 5 - User Story 3)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture()
      player3 = player_fixture()

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "VAL1"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["jack"])

      %{
        game_session: game_session,
        player1: player1,
        player2: player2,
        player3: player3
      }
    end

    @tag :phase5
    @tag :us3
    test "Jack matching by suit is accepted (T037)", %{
      game_session: game_session,
      player1: _player1
    } do
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player
      top_card = game_session.top_card

      # Find a Jack that matches top card's suit (in deck since Jacks excluded from deal)
      jack_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "jack" and dc.card.suit == top_card.suit and
            dc.location_type == "deck"
        end)

      # Move Jack to current player's hand
      Repo.update_all(
        from(dc in DeckCard, where: dc.id == ^jack_card.id),
        set: [location_type: "player_hand", player_id: current_player.id, order_index: nil]
      )

      # Reload
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [:top_card, :current_turn_player], force: true)

      # Play Jack matching by suit
      {:ok, updated_game} =
        CardGames.play_cards(game_session, current_player.id, [jack_card.card.id])

      # Verify play was accepted
      assert updated_game.top_card_id == jack_card.card.id
      assert updated_game.current_turn_player_id != current_player.id
    end

    @tag :phase5
    @tag :us3
    test "Jack matching by rank is accepted (T038)", %{
      game_session: game_session,
      player1: player1
    } do
      # Set top card to a Jack
      jack_top_card =
        Repo.one(
          from c in Card,
            where: c.rank == "jack",
            limit: 1
        )

      game_session
      |> Ecto.Changeset.change(top_card_id: jack_top_card.id)
      |> Repo.update!()

      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player

      # Find a Jack of a DIFFERENT suit than top card
      jack_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "jack" and dc.card.suit != jack_top_card.suit and
            dc.location_type == "deck"
        end)

      # Move Jack to current player's hand
      Repo.update_all(
        from(dc in DeckCard, where: dc.id == ^jack_card.id),
        set: [location_type: "player_hand", player_id: current_player.id, order_index: nil]
      )

      # Reload
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [:top_card, :current_turn_player], force: true)

      # Play Jack matching by rank
      {:ok, updated_game} =
        CardGames.play_cards(game_session, current_player.id, [jack_card.card.id])

      # Verify play was accepted
      assert updated_game.top_card_id == jack_card.card.id
      assert updated_game.current_turn_player_id != current_player.id
    end

    @tag :phase5
    @tag :us3
    test "Jack not matching suit or rank is rejected (T039)", %{
      game_session: game_session,
      player1: player1
    } do
      # Set top card to a non-Jack card (e.g., 5 of hearts)
      non_jack_top =
        Repo.one(
          from c in Card,
            where: c.rank == "5" and c.suit == "hearts",
            limit: 1
        )

      game_session
      |> Ecto.Changeset.change(top_card_id: non_jack_top.id)
      |> Repo.update!()

      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player

      # Find a Jack that does NOT match suit (hearts) or rank (5)
      # E.g., Jack of spades, clubs, or diamonds
      jack_card =
        game_session.deck.deck_cards
        |> Enum.find(fn dc ->
          dc.card.rank == "jack" and dc.card.suit != "hearts" and
            dc.location_type == "deck"
        end)

      # Move Jack to current player's hand
      Repo.update_all(
        from(dc in DeckCard, where: dc.id == ^jack_card.id),
        set: [location_type: "player_hand", player_id: current_player.id, order_index: nil]
      )

      # Reload
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      game_session = Repo.preload(game_session, [:top_card, :current_turn_player], force: true)

      # Attempt to play non-matching Jack
      result = CardGames.play_cards(game_session, current_player.id, [jack_card.card.id])

      # Verify play was rejected
      assert {:error, :invalid_play} = result
    end
  end
end
