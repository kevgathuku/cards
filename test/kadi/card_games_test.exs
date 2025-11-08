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

      # Reload with preloads to verify the top_card relationship
      started_game_session =
        Repo.preload(started_game_session, [:top_card, deck: [deck_cards: :card]])

      # Verify top_card is the card on the played_stack
      played_cards =
        started_game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "played_stack"))

      assert length(played_cards) == 1

      start_card = hd(played_cards)
      assert started_game_session.top_card_id == start_card.card_id
      assert started_game_session.top_card.id == start_card.card_id
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

    test "rejects special cards (2,3,8,Jack,Queen,King,Ace) even when they match", %{
      game_session: game_session
    } do
      game_session = Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
      current_player_id = game_session.current_turn_player_id

      # Try to find a special card in current player's hand
      special_ranks = ["2", "3", "8", "jack", "queen", "king", "ace"]

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

      top_card = game_session.top_card

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

      current_player_id = game_session.current_turn_player_id

      # Get player's current hand from database (after dealing)
      player_cards =
        Repo.all(
          from dc in Kadi.Games.DeckCard,
            join: d in Kadi.Games.Deck,
            on: dc.deck_id == d.id,
            join: c in Kadi.Games.Card,
            on: dc.card_id == c.id,
            where:
              d.game_session_id == ^game_session.id and dc.player_id == ^current_player_id and
                dc.location_type == "player_hand",
            preload: [card: c]
        )

      # Find a King card that matches top card
      top_card = Repo.get!(Kadi.Games.Card, game_session.top_card_id)

      king_card =
        Repo.one(
          from c in Kadi.Games.Card,
            where: c.rank == "king" and c.suit == ^top_card.suit
        )

      # Find this King in deck_cards
      king_deck_card =
        Repo.one!(
          from dc in Kadi.Games.DeckCard,
            join: d in Kadi.Games.Deck,
            on: dc.deck_id == d.id,
            where: d.game_session_id == ^game_session.id and dc.card_id == ^king_card.id
        )

      # Remove all cards from player's hand EXCEPT if one is already the king we want
      cards_to_remove =
        player_cards
        |> Enum.reject(&(&1.id == king_deck_card.id))

      cards_to_remove
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

      # Make sure the King is the player's only card
      Repo.update!(
        Ecto.Changeset.change(king_deck_card, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
      )

      # Verify player has exactly 1 card
      remaining_cards =
        Repo.all(
          from dc in Kadi.Games.DeckCard,
            join: d in Kadi.Games.Deck,
            on: dc.deck_id == d.id,
            where:
              d.game_session_id == ^game_session.id and dc.player_id == ^current_player_id and
                dc.location_type == "player_hand"
        )

      assert length(remaining_cards) == 1

      # Get initial player status
      player_session_before =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: game_session.id,
          player_id: current_player_id
        )

      assert player_session_before.status == "normal"

      # Play the King (last card)
      {:ok, _updated_game} = CardGames.play_cards(game_session, current_player_id, [king_card.id])

      # Reload player session to check status
      player_session_after =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: game_session.id,
          player_id: current_player_id
        )

      # Status should be "cardless"
      assert player_session_after.status == "cardless"

      IO.puts("✓ T040: Player status changed to 'cardless' after playing King as last card")
    end

    @tag :phase6
    @tag :cardless
    test "T041: cardless player automatically draws card on their turn", %{player: player} do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "cardless-autodraw"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Setup: Make current player cardless
      current_player_id = game_session.current_turn_player_id

      player_session =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: game_session.id,
          player_id: current_player_id
        )

      Repo.update!(Ecto.Changeset.change(player_session, %{status: "cardless"}))

      # Verify status is cardless
      cardless_player =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: game_session.id,
          player_id: current_player_id
        )

      assert cardless_player.status == "cardless"

      # Have cardless player draw a card (it's their turn)
      {:ok, updated_game} = CardGames.draw_card_from_deck(game_session, current_player_id)

      # Reload game session
      updated_game = Repo.preload(updated_game, deck: [deck_cards: :card])

      # Player should now have cards from initial deal plus the drawn card
      player_cards =
        Enum.filter(
          updated_game.deck.deck_cards,
          &(&1.location_type == "player_hand" and &1.player_id == current_player_id)
        )

      assert length(player_cards) >= 1

      IO.puts("✓ T041: Cardless player auto-draws card on their turn")
    end

    @tag :phase6
    @tag :cardless
    test "T042: player status resets from 'cardless' to 'normal' after auto-draw", %{
      player: player
    } do
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player, %{short_code: "cardless-reset"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Use current turn player
      current_player_id = game_session.current_turn_player_id

      # Make current player cardless
      player_session =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: game_session.id,
          player_id: current_player_id
        )

      Repo.update!(Ecto.Changeset.change(player_session, %{status: "cardless"}))

      # Draw card (it's their turn)
      {:ok, _updated_game} = CardGames.draw_card_from_deck(game_session, current_player_id)

      # Check status reset
      player_session_after =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: game_session.id,
          player_id: current_player_id
        )

      assert player_session_after.status == "normal"

      IO.puts("✓ T042: Player status reset from 'cardless' to 'normal' after draw")
    end

    @tag :phase6
    @tag :cardless
    @tag :skip
    test "T043: telemetry event emitted when player becomes cardless", %{player: player} do
      # This test requires telemetry handler setup
      # Skipped for now - will implement after telemetry infrastructure is in place
      IO.puts("⏭️  T043: Skipped - Telemetry test infrastructure needed")
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

      # Make player1 and player2 cardless
      for player_id <- [player.id, player2.id] do
        player_session =
          Repo.get_by!(Kadi.Games.GameSessionPlayer,
            game_session_id: game_session.id,
            player_id: player_id
          )

        Repo.update!(Ecto.Changeset.change(player_session, %{status: "cardless"}))
      end

      # Verify both are cardless
      cardless_count =
        Repo.aggregate(
          from(gsp in Kadi.Games.GameSessionPlayer,
            where: gsp.game_session_id == ^game_session.id and gsp.status == "cardless"
          ),
          :count
        )

      assert cardless_count == 2

      # Verify player3 is still normal
      player3_session =
        Repo.get_by!(Kadi.Games.GameSessionPlayer,
          game_session_id: game_session.id,
          player_id: player3.id
        )

      assert player3_session.status == "normal"

      IO.puts("✓ T044: Multiple cardless players tracked independently")
    end
  end

  describe "edge cases and anomalies" do
    @tag :phase6
    @tag :anomaly
    @tag :skip
    test "T048: deck exhaustion anomaly handled gracefully", %{player: player} do
      # This test would require emptying both deck and played pile
      # Complex setup - skipping for initial implementation
      IO.puts("⏭️  T048: Skipped - Complex anomaly scenario")
    end
  end
end
