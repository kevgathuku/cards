defmodule Kadi.CardGames.SpecialCardsAceTest do
  use Kadi.DataCase

  import Ecto.Query, warn: false
  alias Kadi.CardGames
  alias Kadi.Games.DeckCard

  import Kadi.AccountsFixtures

  describe "Ace Card Gameplay" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "ace-p2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "Ace Test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{game: game_session, p1: player1, p2: player2}
    end

    test "[T033] playing an Ace pauses the turn and sets action_type to 'select_suit'", %{
      game: game_session
    } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      # Use whoever has the current turn (set by start_game)
      current_player = game_session.current_turn_player

      # Find an Ace that's actually in the deck (not already dealt)
      ace_deck_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      ace_card = ace_deck_card.card

      # Move Ace to current player's hand
      {:ok, _} =
        DeckCard.changeset(ace_deck_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Act: Current player plays the Ace
      {:ok, updated_game} = CardGames.play_cards(game_session, current_player.id, [ace_card.id])

      # Assert: Turn did not advance, and action_type is set
      assert updated_game.current_turn_player_id == current_player.id
      assert updated_game.action_type == "select_suit"
      assert updated_game.action_suit == nil
    end

    test "[T034] select_suit/3 advances turn and sets action_suit", %{
      game: game_session
    } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      # Use whoever has the current turn (set by start_game)
      current_player = game_session.current_turn_player

      # Find an Ace that's actually in the deck (not already dealt)
      ace_deck_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      ace_card = ace_deck_card.card

      # Move Ace to current player's hand
      {:ok, _} =
        DeckCard.changeset(ace_deck_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Arrange: Current player plays an Ace, pausing the turn
      {:ok, paused_game} = CardGames.play_cards(game_session, current_player.id, [ace_card.id])
      assert paused_game.current_turn_player_id == current_player.id
      assert paused_game.action_type == "select_suit"

      # Get ordered players to calculate next player
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      expected_next_index = rem(current_index + 1, length(players))
      expected_next_player = Enum.at(players, expected_next_index)

      # Act: Current player selects a suit
      {:ok, updated_game} = CardGames.select_suit(paused_game, current_player.id, "hearts")

      # Assert: Game state is updated correctly
      assert updated_game.action_type == nil
      assert updated_game.action_suit == "hearts"
      assert updated_game.current_turn_player_id == expected_next_player.id
    end

    test "[T035] select_suit/3 returns error if not player's turn", %{
      game: game_session
    } do
      # Reload game session with associations
      game_session =
        Repo.preload(
          game_session,
          [
            :top_card,
            :current_turn_player,
            deck: [deck_cards: :card],
            game_session_players: :player
          ],
          force: true
        )

      # Use whoever has the current turn
      current_player = game_session.current_turn_player

      # Find another player (not the current turn player)
      other_player =
        game_session.game_session_players
        |> Enum.map(& &1.player)
        |> Enum.find(&(&1.id != current_player.id))

      # Find an Ace that's actually in the deck (not already dealt)
      ace_deck_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      ace_card = ace_deck_card.card

      # Move Ace to current player's hand
      {:ok, _} =
        DeckCard.changeset(ace_deck_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Arrange: Current player plays an Ace
      {:ok, paused_game} = CardGames.play_cards(game_session, current_player.id, [ace_card.id])

      # Act & Assert: Other player (not their turn) tries to select a suit
      assert {:error, :not_your_turn} ==
               CardGames.select_suit(paused_game, other_player.id, "clubs")
    end

    test "[T036] select_suit/3 returns error if game is not in 'select_suit' state", %{
      game: game_session
    } do
      # Reload game session with current turn player
      game_session = Repo.preload(game_session, [:current_turn_player], force: true)

      # Use whoever has the current turn
      current_player = game_session.current_turn_player

      # Arrange: Game is in a normal state
      assert game_session.action_type == nil

      # Act & Assert: Current player tries to select a suit without playing an Ace first
      assert {:error, :invalid_game_state} ==
               CardGames.select_suit(game_session, current_player.id, "spades")
    end

    test "[T037] select_suit/3 returns error for invalid suit", %{
      game: game_session
    } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      # Use whoever has the current turn
      current_player = game_session.current_turn_player

      # Find an Ace that's actually in the deck (not already dealt)
      ace_deck_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      ace_card = ace_deck_card.card

      # Move Ace to current player's hand
      {:ok, _} =
        DeckCard.changeset(ace_deck_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Arrange: Current player plays an Ace
      {:ok, paused_game} = CardGames.play_cards(game_session, current_player.id, [ace_card.id])

      # Act & Assert: Current player tries to select an invalid suit
      assert {:error, :invalid_suit} ==
               CardGames.select_suit(paused_game, current_player.id, "invalid_suit")
    end

    test "[T038] playing a card after an Ace has been played and suit selected works correctly",
         %{
           game: game_session
         } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      # Use whoever has the current turn
      current_player = game_session.current_turn_player

      # Get ordered players to calculate next player
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      next_player_index = rem(current_index + 1, length(players))
      next_player = Enum.at(players, next_player_index)

      # Find an Ace that's actually in the deck (not already dealt)
      ace_deck_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      ace_card = ace_deck_card.card

      # Move Ace to current player's hand
      {:ok, _} =
        DeckCard.changeset(ace_deck_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # Arrange: Current player plays an Ace and selects "clubs"
      {:ok, paused_game} = CardGames.play_cards(game_session, current_player.id, [ace_card.id])

      {:ok, game_after_suit_selection} =
        CardGames.select_suit(paused_game, current_player.id, "clubs")

      # Reload with associations
      game_after_suit_selection =
        Repo.preload(game_after_suit_selection, [:top_card, deck: [deck_cards: :card]],
          force: true
        )

      # Find a valid card (clubs, regular rank) and an invalid card (not clubs) that are in the deck
      regular_ranks = ["4", "5", "6", "7", "9", "10", "king"]

      valid_deck_card =
        game_after_suit_selection.deck.deck_cards
        |> Enum.find(
          &(&1.card.suit == "clubs" && &1.card.rank in regular_ranks && &1.location_type == "deck")
        )

      invalid_deck_card =
        game_after_suit_selection.deck.deck_cards
        |> Enum.find(
          &(&1.card.suit == "hearts" && &1.card.rank in regular_ranks &&
              &1.location_type == "deck")
        )

      valid_card = valid_deck_card.card
      invalid_card = invalid_deck_card.card

      # Move both to next player's hand
      {:ok, _} =
        DeckCard.changeset(valid_deck_card, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
        |> Repo.update()

      {:ok, _} =
        DeckCard.changeset(invalid_deck_card, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
        |> Repo.update()

      # Reload game session
      game_after_suit_selection = Repo.get!(Kadi.Games.GameSession, game_after_suit_selection.id)

      assert game_after_suit_selection.current_turn_player_id == next_player.id
      assert game_after_suit_selection.action_suit == "clubs"

      # Act & Assert: Next player cannot play the invalid card
      assert {:error, :invalid_play} ==
               CardGames.play_cards(game_after_suit_selection, next_player.id, [invalid_card.id])

      # Act & Assert: Next player can play the valid card
      {:ok, final_game_state} =
        CardGames.play_cards(game_after_suit_selection, next_player.id, [valid_card.id])

      assert final_game_state.top_card_id == valid_card.id
      # action_suit is reset after the next play
      assert final_game_state.action_suit == nil
      assert final_game_state.current_turn_player_id == current_player.id
    end
  end
end
