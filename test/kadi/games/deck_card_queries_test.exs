defmodule Kadi.Games.DeckCardQueriesTest do
  use Kadi.DataCase, async: true

  alias Kadi.{CardGames, Repo}
  alias Kadi.Games.{DeckCard, Deck}
  import Kadi.AccountsFixtures
  import Ecto.Query

  describe "DeckCard query functions" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture()

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "QUERY"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{game_session: game_session, player1: player1, player2: player2}
    end

    test "in_hand() filters cards in player hands", %{game_session: game_session} do
      # Query cards in hands
      cards_in_hands =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.in_hand()
        |> Repo.all()

      # Should have cards dealt to players (4 each = 8 total)
      assert length(cards_in_hands) == 8
      assert Enum.all?(cards_in_hands, &(&1.location_type == "player_hand"))
    end

    test "in_deck() filters cards in deck pile", %{game_session: game_session} do
      # Query cards in deck
      cards_in_deck =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.in_deck()
        |> Repo.all()

      # Should have remaining cards in deck (52 - 8 dealt - 1 top card = 43)
      assert length(cards_in_deck) == 43
      assert Enum.all?(cards_in_deck, &(&1.location_type == "deck"))
    end

    test "played() filters cards in played stack", %{game_session: game_session} do
      # Query cards in played stack
      played_cards =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.played()
        |> Repo.all()

      # Should have 1 card (the top card from start_game)
      assert length(played_cards) == 1
      assert Enum.all?(played_cards, &(&1.location_type == "played_stack"))
    end

    test "for_player() filters cards for specific player", %{
      game_session: game_session,
      player1: player1
    } do
      # Query player1's cards
      player1_cards =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.in_hand()
        |> DeckCard.for_player(player1.id)
        |> Repo.all()

      # Player should have 4 cards
      assert length(player1_cards) == 4
      assert Enum.all?(player1_cards, &(&1.player_id == player1.id))
    end

    test "of_rank() filters cards by rank", %{game_session: game_session} do
      # Query all aces in the deck
      ace_cards =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.of_rank("ace")
        |> DeckCard.with_card()
        |> Repo.all()

      # Should have 4 aces total in game
      assert length(ace_cards) == 4
      assert Enum.all?(ace_cards, &(&1.card.rank == "ace"))
    end

    test "of_suit() filters cards by suit", %{game_session: game_session} do
      # Query all hearts
      heart_cards =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.of_suit("hearts")
        |> DeckCard.with_card()
        |> Repo.all()

      # Should have 13 hearts
      assert length(heart_cards) == 13
      assert Enum.all?(heart_cards, &(&1.card.suit == "hearts"))
    end

    test "with_card() preloads card association", %{game_session: game_session} do
      # Query with card preloaded
      cards_with_details =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.in_hand()
        |> DeckCard.with_card()
        |> limit(1)
        |> Repo.all()

      card = List.first(cards_with_details)
      assert %Ecto.Association.NotLoaded{} != card.card
      assert card.card.rank != nil
      assert card.card.suit != nil
    end

    test "ordered() orders by order_index ascending", %{game_session: game_session} do
      # Query deck cards ordered
      deck_cards =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.in_deck()
        |> DeckCard.ordered()
        |> Repo.all()

      # Verify ascending order
      order_indices = Enum.map(deck_cards, & &1.order_index)
      assert order_indices == Enum.sort(order_indices)
    end

    test "ordered_desc() orders by order_index descending", %{game_session: game_session} do
      # Query deck cards ordered descending
      deck_cards =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.in_deck()
        |> DeckCard.ordered_desc()
        |> Repo.all()

      # Verify descending order
      order_indices = Enum.map(deck_cards, & &1.order_index)
      assert order_indices == Enum.sort(order_indices, :desc)
    end

    test "query functions can be chained", %{game_session: game_session, player1: player1} do
      # Chain multiple query functions
      player_hearts =
        from(dc in DeckCard,
          join: d in Deck,
          on: dc.deck_id == d.id,
          where: d.game_session_id == ^game_session.id
        )
        |> DeckCard.in_hand()
        |> DeckCard.for_player(player1.id)
        |> DeckCard.of_suit("hearts")
        |> DeckCard.with_card()
        |> Repo.all()

      # All should be hearts in player1's hand
      assert Enum.all?(player_hearts, fn dc ->
               dc.player_id == player1.id and
                 dc.location_type == "player_hand" and
                 dc.card.suit == "hearts"
             end)
    end
  end

  describe "CardGames context helper functions" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture()

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "HELP"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{game_session: game_session, player1: player1, player2: player2}
    end

    test "get_player_hand/2 returns player's cards", %{
      game_session: game_session,
      player1: player1
    } do
      hand = CardGames.get_player_hand(game_session, player1.id)

      assert length(hand) == 4
      assert Enum.all?(hand, &(&1.player_id == player1.id))
      # Card should be preloaded
      assert Enum.all?(hand, &(%Ecto.Association.NotLoaded{} != &1.card))
    end

    test "count_player_cards/2 returns card count", %{
      game_session: game_session,
      player1: player1
    } do
      count = CardGames.count_player_cards(game_session, player1.id)
      assert count == 4
    end

    test "get_player_cards_by_rank/3 filters by rank", %{
      game_session: game_session,
      player1: player1
    } do
      # Get all player1's cards first
      all_cards = CardGames.get_player_hand(game_session, player1.id)
      # Pick a rank that exists
      rank = List.first(all_cards).card.rank

      cards = CardGames.get_player_cards_by_rank(game_session, player1.id, rank)

      assert length(cards) >= 1
      assert Enum.all?(cards, &(&1.card.rank == rank))
      assert Enum.all?(cards, &(&1.player_id == player1.id))
    end

    test "get_top_played_card/1 returns top card or error", %{game_session: game_session} do
      # Should have a top card after start_game
      assert {:ok, top_card} = CardGames.get_top_played_card(game_session)
      assert top_card.location_type == "played_stack"
      assert %Ecto.Association.NotLoaded{} != top_card.card
    end

    test "count_deck_cards/1 returns deck pile count", %{game_session: game_session} do
      count = CardGames.count_deck_cards(game_session)
      # 52 - 8 dealt to players - 1 top card = 43
      assert count == 43
    end

    test "count_played_cards/1 returns played stack count", %{game_session: game_session} do
      count = CardGames.count_played_cards(game_session)
      # 1 card (the top card from start_game)
      assert count == 1
    end
  end
end
