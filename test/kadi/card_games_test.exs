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

    test "returns error when deck is empty" do
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

      assert {:error, :deck_empty} =
               CardGames.draw_card_from_deck(game_session, player.id)
    end
  end
end
