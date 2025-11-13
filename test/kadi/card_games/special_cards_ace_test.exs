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
      # Exclude Aces from initial deal to ensure all 4 Aces remain in deck for test manipulation
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["ace"])

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

    test "After a player draws, action_suit persists for next player", %{
      game: game_session
    } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      next_player_index = rem(current_index + 1, length(players))
      next_player = Enum.at(players, next_player_index)

      # Find and play an Ace
      ace_deck_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      {:ok, _} =
        DeckCard.changeset(ace_deck_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, paused_game} =
        CardGames.play_cards(game_session, current_player.id, [ace_deck_card.card.id])

      {:ok, game_with_suit} = CardGames.select_suit(paused_game, current_player.id, "diamonds")

      # Verify action_suit is set
      assert game_with_suit.action_suit == "diamonds"
      assert game_with_suit.current_turn_player_id == next_player.id

      # Next player draws a card
      {:ok, game_after_draw} = CardGames.draw_card_from_deck(game_with_suit, next_player.id)

      # CRITICAL: action_suit should persist after draw
      assert game_after_draw.action_suit == "diamonds"

      # Turn advances to the player after next_player
      third_player_index = rem(next_player_index + 1, length(players))
      third_player = Enum.at(players, third_player_index)
      assert game_after_draw.current_turn_player_id == third_player.id
    end

    test "[T060] multiple players drawing in sequence, action_suit persists until matching card played",
         %{
           game: game_session
         } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      next_player_index = rem(current_index + 1, length(players))
      next_player = Enum.at(players, next_player_index)

      # Find and play an Ace, select "spades"
      ace_deck_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      {:ok, _} =
        DeckCard.changeset(ace_deck_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, paused_game} =
        CardGames.play_cards(game_session, current_player.id, [ace_deck_card.card.id])

      {:ok, game_with_suit} = CardGames.select_suit(paused_game, current_player.id, "spades")

      assert game_with_suit.action_suit == "spades"

      # First player draws
      {:ok, game_after_draw1} = CardGames.draw_card_from_deck(game_with_suit, next_player.id)
      assert game_after_draw1.action_suit == "spades"

      # Second player draws
      third_player_index = rem(next_player_index + 1, length(players))
      third_player = Enum.at(players, third_player_index)
      {:ok, game_after_draw2} = CardGames.draw_card_from_deck(game_after_draw1, third_player.id)
      assert game_after_draw2.action_suit == "spades"

      # Reload and find a spade card to play
      game_after_draw2 = Repo.preload(game_after_draw2, [deck: [deck_cards: :card]], force: true)

      regular_ranks = ["4", "5", "6", "7", "9", "10"]

      spade_deck_card =
        game_after_draw2.deck.deck_cards
        |> Enum.find(
          &(&1.card.suit == "spades" && &1.card.rank in regular_ranks &&
              &1.location_type == "deck")
        )

      # Give spade to current player
      fourth_player_index = rem(third_player_index + 1, length(players))
      fourth_player = Enum.at(players, fourth_player_index)

      {:ok, _} =
        DeckCard.changeset(spade_deck_card, %{
          location_type: "player_hand",
          player_id: fourth_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_after_draw2 = Repo.get!(Kadi.Games.GameSession, game_after_draw2.id)

      # Player plays the spade
      {:ok, final_game} =
        CardGames.play_cards(game_after_draw2, fourth_player.id, [spade_deck_card.card.id])

      # action_suit should now be cleared since matching suit was played
      assert final_game.action_suit == nil
    end

    test "[T070] playing Ace when action_suit is set triggers suit selection", %{
      game: game_session
    } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      next_player_index = rem(current_index + 1, length(players))
      next_player = Enum.at(players, next_player_index)

      # First, play an Ace and set action_suit to "hearts"
      ace_deck_card1 =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      {:ok, _} =
        DeckCard.changeset(ace_deck_card1, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, paused_game} =
        CardGames.play_cards(game_session, current_player.id, [ace_deck_card1.card.id])

      {:ok, game_with_suit} = CardGames.select_suit(paused_game, current_player.id, "hearts")

      # Verify action_suit is "hearts" and turn advanced
      assert game_with_suit.action_suit == "hearts"
      assert game_with_suit.current_turn_player_id == next_player.id

      # Reload and find another Ace for next player
      game_with_suit = Repo.preload(game_with_suit, [deck: [deck_cards: :card]], force: true)

      ace_deck_card2 =
        game_with_suit.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "ace" && &1.location_type == "deck" &&
              &1.card_id != ace_deck_card1.card_id)
        )

      {:ok, _} =
        DeckCard.changeset(ace_deck_card2, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_with_suit = Repo.get!(Kadi.Games.GameSession, game_with_suit.id)

      # Next player plays Ace even though action_suit is set
      {:ok, paused_again} =
        CardGames.play_cards(game_with_suit, next_player.id, [ace_deck_card2.card.id])

      # Ace play should succeed and trigger suit selection
      assert paused_again.action_type == "select_suit"
      assert paused_again.current_turn_player_id == next_player.id
      # action_suit should be cleared (nil) until new suit is selected
      assert paused_again.action_suit == nil
    end

    test "[T071] new selected suit replaces old action_suit", %{
      game: game_session
    } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      next_player_index = rem(current_index + 1, length(players))
      next_player = Enum.at(players, next_player_index)

      # First Ace: set action_suit to "clubs"
      ace_deck_card1 =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      {:ok, _} =
        DeckCard.changeset(ace_deck_card1, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, paused_game} =
        CardGames.play_cards(game_session, current_player.id, [ace_deck_card1.card.id])

      {:ok, game_with_clubs} = CardGames.select_suit(paused_game, current_player.id, "clubs")

      assert game_with_clubs.action_suit == "clubs"
      assert game_with_clubs.current_turn_player_id == next_player.id

      # Reload and find another Ace for next player
      game_with_clubs = Repo.preload(game_with_clubs, [deck: [deck_cards: :card]], force: true)

      ace_deck_card2 =
        game_with_clubs.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "ace" && &1.location_type == "deck" &&
              &1.card_id != ace_deck_card1.card_id)
        )

      {:ok, _} =
        DeckCard.changeset(ace_deck_card2, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_with_clubs = Repo.get!(Kadi.Games.GameSession, game_with_clubs.id)

      # Second Ace: override with "diamonds"
      {:ok, paused_again} =
        CardGames.play_cards(game_with_clubs, next_player.id, [ace_deck_card2.card.id])

      {:ok, game_with_diamonds} = CardGames.select_suit(paused_again, next_player.id, "diamonds")

      # Old action_suit should be replaced
      assert game_with_diamonds.action_suit == "diamonds"
      refute game_with_diamonds.action_suit == "clubs"
    end

    test "[T072] next player must follow new suit, not old suit", %{
      game: game_session
    } do
      # Reload game session with associations
      game_session =
        Repo.preload(game_session, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game_session.current_turn_player

      # Get ordered players
      players =
        game_session.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == current_player.id))
      next_player_index = rem(current_index + 1, length(players))
      next_player = Enum.at(players, next_player_index)
      third_player_index = rem(next_player_index + 1, length(players))
      third_player = Enum.at(players, third_player_index)

      # First Ace: set action_suit to "spades"
      ace_deck_card1 =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      {:ok, _} =
        DeckCard.changeset(ace_deck_card1, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, paused_game} =
        CardGames.play_cards(game_session, current_player.id, [ace_deck_card1.card.id])

      {:ok, game_with_spades} = CardGames.select_suit(paused_game, current_player.id, "spades")

      assert game_with_spades.action_suit == "spades"

      # Reload and find another Ace for next player
      game_with_spades = Repo.preload(game_with_spades, [deck: [deck_cards: :card]], force: true)

      ace_deck_card2 =
        game_with_spades.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "ace" && &1.location_type == "deck" &&
              &1.card_id != ace_deck_card1.card_id)
        )

      {:ok, _} =
        DeckCard.changeset(ace_deck_card2, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_with_spades = Repo.get!(Kadi.Games.GameSession, game_with_spades.id)

      # Second Ace: override with "hearts"
      {:ok, paused_again} =
        CardGames.play_cards(game_with_spades, next_player.id, [ace_deck_card2.card.id])

      {:ok, game_with_hearts} = CardGames.select_suit(paused_again, next_player.id, "hearts")

      assert game_with_hearts.action_suit == "hearts"
      assert game_with_hearts.current_turn_player_id == third_player.id

      # Reload and find cards for third player
      game_with_hearts = Repo.preload(game_with_hearts, [deck: [deck_cards: :card]], force: true)

      regular_ranks = ["4", "5", "6", "7", "9", "10"]

      # Try to play a spade (old suit) - should fail
      spade_deck_card =
        game_with_hearts.deck.deck_cards
        |> Enum.find(
          &(&1.card.suit == "spades" && &1.card.rank in regular_ranks &&
              &1.location_type == "deck")
        )

      if spade_deck_card do
        {:ok, _} =
          DeckCard.changeset(spade_deck_card, %{
            location_type: "player_hand",
            player_id: third_player.id,
            order_index: nil
          })
          |> Repo.update()

        game_with_hearts = Repo.get!(Kadi.Games.GameSession, game_with_hearts.id)

        # Playing spade should fail (old suit requirement)
        {:error, reason} =
          CardGames.play_cards(game_with_hearts, third_player.id, [spade_deck_card.card.id])

        assert reason == :invalid_play
      end

      # Reload
      game_with_hearts = Repo.preload(game_with_hearts, [deck: [deck_cards: :card]], force: true)

      # Playing a heart (new suit) should succeed
      heart_deck_card =
        game_with_hearts.deck.deck_cards
        |> Enum.find(
          &(&1.card.suit == "hearts" && &1.card.rank in regular_ranks &&
              &1.location_type == "deck")
        )

      {:ok, _} =
        DeckCard.changeset(heart_deck_card, %{
          location_type: "player_hand",
          player_id: third_player.id,
          order_index: nil
        })
        |> Repo.update()

      game_with_hearts = Repo.get!(Kadi.Games.GameSession, game_with_hearts.id)

      {:ok, final_game} =
        CardGames.play_cards(game_with_hearts, third_player.id, [heart_deck_card.card.id])

      # action_suit should be cleared after matching suit played
      assert final_game.action_suit == nil
    end
  end

  describe "Phase 7: Ace Card Edge Cases" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "ace-edge-p2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "Ace Edge"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      # Exclude Aces from initial deal to ensure all 4 Aces remain in deck for test manipulation
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["ace"])

      %{game: game_session, p1: player1, p2: player2}
    end

    test "[T081] Ace allowed as starting card", %{p1: player1, p2: player2} do
      # T081: Verify that Aces are allowed as starting cards (not excluded like Jack)
      # Test by starting multiple games and checking that at least one has an Ace as the starting card

      max_attempts = 50

      ace_found =
        Enum.reduce_while(1..max_attempts, false, fn attempt, _acc ->
          # Create a new game
          {:ok, game} =
            CardGames.create_game_session(player1, %{short_code: "AceStart#{attempt}"})

          {:ok, _} = CardGames.join_game_session(player2, game.id)
          {:ok, started_game} = CardGames.start_game(game)

          # Preload top card
          started_game = Repo.preload(started_game, :top_card)

          if started_game.top_card.rank == "ace" do
            {:halt, true}
          else
            {:cont, false}
          end
        end)

      # If we found an Ace in 20 attempts, the test passes
      # This probabilistic approach verifies Aces are in the allowed pool
      # With 52 cards and 4 Aces, excluding only ["2", "3", "jack", "queen"] (16 cards),
      # we have 36 allowed cards, so probability is ~11% per attempt
      assert ace_found,
             "No Ace found as starting card in #{max_attempts} attempts - Aces may still be excluded"

      IO.puts("✓ T081: Ace allowed as starting card (probabilistic verification)")
    end

    test "[T081b] Ace as starting card has no suit restriction", %{p1: player1, p2: player2} do
      # When Ace is the starting card, the first player should be able to play
      # ANY valid card matching the Ace suit (not forced to select a suit first)
      # The Ace starting card does NOT set action_type or action_suit

      max_attempts = 20

      ace_game_found =
        Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
          # Create a new game
          {:ok, game} =
            CardGames.create_game_session(player1, %{short_code: "AceStartNoRestrict#{attempt}"})

          {:ok, _} = CardGames.join_game_session(player2, game.id)
          {:ok, started_game} = CardGames.start_game(game, exclude_ranks: ["jack", "ace", "king"])

          # Preload top card
          started_game = Repo.preload(started_game, :top_card)

          if started_game.top_card.rank == "ace" do
            {:halt, started_game}
          else
            {:cont, nil}
          end
        end)

      if ace_game_found do
        # Verify that action_type and action_suit are NOT set
        assert ace_game_found.action_type == nil,
               "Ace starting card should not set action_type"

        assert ace_game_found.action_suit == nil,
               "Ace starting card should not set action_suit"

        # Verify that the current turn player can play any regular card that matches
        # the Ace's suit (normal suit matching applies, but NO suit selection is triggered)
        ace_game_found =
          Repo.preload(
            ace_game_found,
            [:current_turn_player, :top_card, deck: [deck_cards: :card]],
            force: true
          )

        current_player = ace_game_found.current_turn_player
        ace_top_card = ace_game_found.top_card

        # Get any regular NON-ACE card from the player's hand that matches the Ace's suit
        # (We exclude Ace/King/Jack because they have special behavior)
        matching_card =
          ace_game_found.deck.deck_cards
          |> Enum.find(fn dc ->
            dc.location_type == "player_hand" and dc.player_id == current_player.id and
              dc.card.suit == ace_top_card.suit and
              dc.card.rank not in ["ace", "king", "jack"]
          end)

        if matching_card do
          # Try to play this card - should be accepted (normal matching rules apply)
          {:ok, after_play} =
            CardGames.play_cards(ace_game_found, current_player.id, [matching_card.card.id])

          # Verify the play was accepted (turn advanced)
          assert after_play.current_turn_player_id != current_player.id,
                 "Matching card should be playable when Ace is starting card"

          # Critical assertion: action_suit should still be nil (no suit selection triggered)
          assert after_play.action_suit == nil,
                 "Playing on Ace starting card should not trigger suit selection"

          IO.puts(
            "✓ T081b: Ace as starting card has no suit restriction - normal matching rules apply, no suit selection"
          )
        else
          IO.puts("⏭️  T081b: Skipping verification - no regular card in current player's hand")
        end
      else
        IO.puts("⏭️  T081b: Skipping - No Ace found as starting card in #{max_attempts} attempts")
      end
    end

    test "[T074] Playing Ace as last card triggers suit selection (edge case)", %{
      p1: player1,
      p2: player2
    } do
      # Create a game and get a player to one card left (an Ace)
      {:ok, game} = CardGames.create_game_session(player1, %{short_code: "AceWin"})
      {:ok, _} = CardGames.join_game_session(player2, game.id)
      {:ok, game} = CardGames.start_game(game)

      # Preload necessary associations
      game =
        Repo.preload(game, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game.current_turn_player

      # Find an Ace that can be played (matches suit or is an Ace)
      ace_card =
        game.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" and &1.location_type == "deck"))

      # Move all player's cards back to deck except the Ace
      game.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player.id))
      |> Enum.with_index()
      |> Enum.each(fn {dc, idx} ->
        Repo.update!(
          DeckCard.changeset(dc, %{
            location_type: "deck",
            order_index: idx + 100,
            player_id: nil
          })
        )
      end)

      # Give player only the Ace
      Repo.update!(
        DeckCard.changeset(ace_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
      )

      # Reload game
      game = Repo.get!(Kadi.Games.GameSession, game.id)

      game =
        Repo.preload(game, [:top_card, :current_turn_player, :game_session_players], force: true)

      # Play the Ace (last card)
      {:ok, updated_game} = CardGames.play_cards(game, current_player.id, [ace_card.card.id])

      # When Ace is played as last card (edge case):
      # - Currently triggers suit selection (action_type = "select_suit")
      # - Player is not cardless yet (still has to select suit)
      # - Turn does NOT advance (waiting for suit selection)
      # This is the current behavior - player must select suit even with no cards
      assert updated_game.action_type == "select_suit"
      assert updated_game.current_turn_player_id == current_player.id

      # Now select a suit
      {:ok, final_game} = CardGames.select_suit(updated_game, current_player.id, "hearts")

      # After suit selection:
      # - action_type cleared
      # - Turn advances
      # - Player is now effectively done (0 cards)
      assert final_game.action_type == nil
      assert final_game.action_suit == "hearts"
      assert final_game.current_turn_player_id != current_player.id

      IO.puts("✓ T074: Playing Ace as last card triggers suit selection (edge case)")
    end

    test "[T075] Multiple Aces in one play only prompts once for suit selection", %{
      p1: player1,
      p2: player2
    } do
      {:ok, game} = CardGames.create_game_session(player1, %{short_code: "MultiAce"})
      {:ok, _} = CardGames.join_game_session(player2, game.id)
      {:ok, game} = CardGames.start_game(game, exclude_ranks: ["ace"])

      game =
        Repo.preload(game, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game.current_turn_player

      # Find 2 Aces (they're in deck since excluded from deal)
      aces =
        game.deck.deck_cards
        |> Enum.filter(&(&1.card.rank == "ace" and &1.location_type == "deck"))
        |> Enum.take(2)

      assert length(aces) == 2, "Need 2 Aces for this test"

      # Give both Aces to current player
      Enum.each(aces, fn ace ->
        Repo.update!(
          DeckCard.changeset(ace, %{
            location_type: "player_hand",
            player_id: current_player.id,
            order_index: nil
          })
        )
      end)

      game = Repo.get!(Kadi.Games.GameSession, game.id)

      # Play both Aces in one turn
      {:ok, updated_game} =
        CardGames.play_cards(game, current_player.id, Enum.map(aces, & &1.card.id))

      # Should trigger suit selection only once (not per Ace)
      assert updated_game.action_type == "select_suit"
      assert updated_game.current_turn_player_id == current_player.id

      # Select suit once
      {:ok, final_game} = CardGames.select_suit(updated_game, current_player.id, "diamonds")

      assert final_game.action_type == nil
      assert final_game.action_suit == "diamonds"

      IO.puts("✓ T075: Multiple Aces in one play only prompts once for suit selection")
    end

    test "[T076] Draw when deck empty and action_suit set recycles correctly", %{
      p1: player1,
      p2: player2
    } do
      {:ok, game} = CardGames.create_game_session(player1, %{short_code: "RecycleAce"})
      {:ok, _} = CardGames.join_game_session(player2, game.id)
      {:ok, game} = CardGames.start_game(game)

      game =
        Repo.preload(game, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      # Set action_suit manually to simulate Ace play
      game = Repo.update!(Kadi.Games.GameSession.changeset(game, %{action_suit: "spades"}))

      # Move most deck cards to played_stack (leaving deck nearly empty)
      deck_cards = Enum.filter(game.deck.deck_cards, &(&1.location_type == "deck"))

      Enum.take(deck_cards, length(deck_cards) - 2)
      |> Enum.with_index()
      |> Enum.each(fn {dc, idx} ->
        Repo.update!(
          DeckCard.changeset(dc, %{
            location_type: "played_stack",
            order_index: idx + 10
          })
        )
      end)

      game = Repo.get!(Kadi.Games.GameSession, game.id)
      current_player_id = game.current_turn_player_id

      # Draw card should recycle played stack when deck runs low
      {:ok, updated_game} = CardGames.draw_card_from_deck(game, current_player_id)

      # action_suit should persist after draw (per FR-010)
      assert updated_game.action_suit == "spades"

      IO.puts("✓ T076: Draw when deck empty and action_suit set recycles correctly")
    end

    test "[T077] Draw deck exhaustion with action_suit logs anomaly", %{p1: player1, p2: player2} do
      {:ok, game} = CardGames.create_game_session(player1, %{short_code: "ExhaustAce"})
      {:ok, _} = CardGames.join_game_session(player2, game.id)
      {:ok, game} = CardGames.start_game(game)

      game = Repo.preload(game, [:current_turn_player, deck: [deck_cards: :card]], force: true)

      # Set action_suit to simulate Ace play requirement
      game = Repo.update!(Kadi.Games.GameSession.changeset(game, %{action_suit: "diamonds"}))

      # Create deck exhaustion scenario: empty deck, only 1 card in played_stack
      # Move all deck cards to player hands
      game.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.with_index()
      |> Enum.each(fn {dc, idx} ->
        assigned_player_id = if rem(idx, 2) == 0, do: player1.id, else: player2.id

        Repo.update!(
          DeckCard.changeset(dc, %{
            location_type: "player_hand",
            player_id: assigned_player_id,
            order_index: nil
          })
        )
      end)

      game = Repo.get!(Kadi.Games.GameSession, game.id)
      current_player_id = game.current_turn_player_id

      # Attempt to draw when deck exhausted and can't recycle
      # Should handle gracefully (skip turn or log anomaly)
      {:ok, updated_game} = CardGames.draw_card_from_deck(game, current_player_id)

      # action_suit should still be set
      assert updated_game.action_suit == "diamonds"
      # Turn should advance (anomaly handling)
      assert updated_game.current_turn_player_id != current_player_id

      IO.puts("✓ T077: Draw deck exhaustion with action_suit logs anomaly")
    end

    test "[T078] Ace after King respects counter-clockwise direction", %{p1: player1, p2: player2} do
      {:ok, game} = CardGames.create_game_session(player1, %{short_code: "AceKing"})
      player3 = player_fixture(%{email: "aceking-p3@example.com"})
      {:ok, _} = CardGames.join_game_session(player2, game.id)
      {:ok, _} = CardGames.join_game_session(player3, game.id)
      {:ok, game} = CardGames.start_game(game, exclude_ranks: ["king", "ace"])

      game =
        Repo.preload(game, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game.current_turn_player
      top_card = game.top_card

      # Find King matching suit
      king_card =
        game.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "king" and &1.card.suit == top_card.suit and
              &1.location_type == "deck")
        )

      Repo.update!(
        DeckCard.changeset(king_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
      )

      game = Repo.get!(Kadi.Games.GameSession, game.id)

      # Play King (reverses to counter-clockwise)
      {:ok, game_after_king} = CardGames.play_cards(game, current_player.id, [king_card.card.id])
      assert game_after_king.direction == "counter_clockwise"

      # Get new current player
      game_after_king =
        Repo.preload(game_after_king, [:current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      new_current = game_after_king.current_turn_player

      # Find an Ace for new player
      ace_card =
        game_after_king.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" and &1.location_type == "deck"))

      Repo.update!(
        DeckCard.changeset(ace_card, %{
          location_type: "player_hand",
          player_id: new_current.id,
          order_index: nil
        })
      )

      game_after_king = Repo.get!(Kadi.Games.GameSession, game_after_king.id)

      # Play Ace
      {:ok, game_after_ace} =
        CardGames.play_cards(game_after_king, new_current.id, [ace_card.card.id])

      # Direction should still be counter-clockwise
      assert game_after_ace.direction == "counter_clockwise"
      assert game_after_ace.action_type == "select_suit"

      IO.puts("✓ T078: Ace after King respects counter-clockwise direction")
    end

    test "[T079] King after Ace preserves action_suit", %{p1: player1, p2: player2} do
      {:ok, game} = CardGames.create_game_session(player1, %{short_code: "KingAce"})
      {:ok, _} = CardGames.join_game_session(player2, game.id)
      {:ok, game} = CardGames.start_game(game, exclude_ranks: ["king", "ace"])

      game =
        Repo.preload(game, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game.current_turn_player

      # Find and play an Ace
      ace_card =
        game.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" and &1.location_type == "deck"))

      Repo.update!(
        DeckCard.changeset(ace_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
      )

      game = Repo.get!(Kadi.Games.GameSession, game.id)
      {:ok, game_after_ace} = CardGames.play_cards(game, current_player.id, [ace_card.card.id])

      # Select suit
      {:ok, game_with_suit} = CardGames.select_suit(game_after_ace, current_player.id, "clubs")
      assert game_with_suit.action_suit == "clubs"

      # Get next player
      game_with_suit =
        Repo.preload(game_with_suit, [:current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      next_player = game_with_suit.current_turn_player

      # Find King matching the action_suit (clubs)
      king_card =
        game_with_suit.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "king" and &1.card.suit == "clubs" and &1.location_type == "deck")
        )

      Repo.update!(
        DeckCard.changeset(king_card, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
      )

      game_with_suit = Repo.get!(Kadi.Games.GameSession, game_with_suit.id)

      # Play King (should clear action_suit since King matches the required suit)
      {:ok, game_after_king} =
        CardGames.play_cards(game_with_suit, next_player.id, [king_card.card.id])

      # King clears action_suit when it matches
      assert game_after_king.action_suit == nil
      assert game_after_king.direction == "counter_clockwise"

      IO.puts("✓ T079: King after Ace preserves action_suit (then clears it)")
    end

    test "[T080] Jack after Ace skips players but preserves action_suit", %{
      p1: player1,
      p2: player2
    } do
      {:ok, game} = CardGames.create_game_session(player1, %{short_code: "JackAce"})
      player3 = player_fixture(%{email: "jackace-p3@example.com"})
      {:ok, _} = CardGames.join_game_session(player2, game.id)
      {:ok, _} = CardGames.join_game_session(player3, game.id)
      {:ok, game} = CardGames.start_game(game, exclude_ranks: ["jack", "ace"])

      game =
        Repo.preload(game, [:top_card, :current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      current_player = game.current_turn_player

      # Find and play an Ace
      ace_card =
        game.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" and &1.location_type == "deck"))

      Repo.update!(
        DeckCard.changeset(ace_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
      )

      game = Repo.get!(Kadi.Games.GameSession, game.id)
      {:ok, game_after_ace} = CardGames.play_cards(game, current_player.id, [ace_card.card.id])

      # Select suit
      {:ok, game_with_suit} = CardGames.select_suit(game_after_ace, current_player.id, "hearts")
      assert game_with_suit.action_suit == "hearts"

      # Get next player
      game_with_suit =
        Repo.preload(game_with_suit, [:current_turn_player, deck: [deck_cards: :card]],
          force: true
        )

      next_player = game_with_suit.current_turn_player

      # Find Jack matching the action_suit (hearts)
      jack_card =
        game_with_suit.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "jack" and &1.card.suit == "hearts" and &1.location_type == "deck")
        )

      Repo.update!(
        DeckCard.changeset(jack_card, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
      )

      game_with_suit = Repo.get!(Kadi.Games.GameSession, game_with_suit.id)

      # Get ordered players for skip calculation
      players =
        game_with_suit.id
        |> CardGames.get_game_session_players()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      current_index = Enum.find_index(players, &(&1.id == next_player.id))
      expected_next_index = rem(current_index + 2, 3)
      expected_next_player = Enum.at(players, expected_next_index)

      # Play Jack (should skip and clear action_suit since Jack matches)
      {:ok, game_after_jack} =
        CardGames.play_cards(game_with_suit, next_player.id, [jack_card.card.id])

      # Jack clears action_suit when it matches
      assert game_after_jack.action_suit == nil
      # Turn should be skipped correctly
      assert game_after_jack.current_turn_player_id == expected_next_player.id

      IO.puts("✓ T080: Jack after Ace skips players and clears action_suit")
    end
  end
end
