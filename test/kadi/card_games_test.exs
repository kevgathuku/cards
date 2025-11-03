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
      assert Enum.count(deck_cards) == 52 - (2 * 4) - 1
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
end
