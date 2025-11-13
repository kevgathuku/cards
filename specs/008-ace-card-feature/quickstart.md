# Quickstart Guide: Ace Card Feature

**Date**: 2025-11-10
**Feature**: Ace Card Special Action

This guide provides a quick way for developers to manually test the core logic of the Ace card feature using `iex`.

## Setup

1.  Start an interactive Elixir session with the application loaded:
    ```sh
    iex -S mix
    ```

2.  Create two players and a game session.
    ```elixir
    alias Kadi.CardGames
    alias Kadi.Accounts

    {:ok, p1} = Accounts.register_player(%{email: "player1@example.com", password: "password123"})
    {:ok, p2} = Accounts.register_player(%{email: "player2@example.com", password: "password123"})

    {:ok, game} = CardGames.create_game_session(p1, %{short_code: "ACE-TEST"})
    CardGames.join_game_session(p2, game.id)
    ```

3.  Start the game.
    ```elixir
    {:ok, game} = CardGames.start_game(game)
    ```

## Testing the Ace Card Flow

### 1. Manually Give a Player an Ace

For testing purposes, we'll find an Ace in the deck and move it to the current player's hand.

```elixir
# Find the current player
current_player_id = game.current_turn_player_id
current_player = if p1.id == current_player_id, do: p1, else: p2

# Find an Ace card in the deck
game = Kadi.Repo.preload(game, deck: [deck_cards: :card])
ace_deck_card = Enum.find(game.deck.deck_cards, fn dc -> dc.location_type == "deck" and dc.card.rank == "ace" end)

# Move the Ace to the player's hand
Ecto.Multi.new()
|> Ecto.Multi.update(:ace, Kadi.Games.DeckCard.changeset(ace_deck_card, %{location_type: "player_hand", player_id: current_player.id, order_index: nil}))
|> Kadi.Repo.transaction()

# Reload the game state
{:ok, game} = CardGames.get_game_session(game.id)
```

### 2. Play the Ace Card

The current player plays the Ace.

```elixir
# Get the card_id of the Ace we just moved
ace_card_id = ace_deck_card.card_id

# Play the card
{:ok, game} = CardGames.play_cards(game, current_player.id, [ace_card_id])

# Verify the game is awaiting suit selection
# game.action_type == "select_suit"
# game.current_turn_player_id is still the same player
IO.inspect(game)
```

### 3. Select a Suit

The player selects a suit.

```elixir
# This is the new function to be created
{:ok, game} = CardGames.select_suit(game, current_player.id, "diamonds")

# Verify the game state has been updated
# game.action_type == nil
# game.action_suit == "diamonds"
# game.current_turn_player_id has advanced to the next player
IO.inspect(game)
```

### 4. Test the Next Play

The next player must now play a "diamonds" card.

```elixir
# Find the next player
next_player_id = game.current_turn_player_id
next_player = if p1.id == next_player_id, do: p1, else: p2

# Find a diamond card in their hand (or give them one for the test)
# ... (manual setup similar to step 1) ...

# Attempt to play a non-diamond card (should fail)
# ...

# Attempt to play a diamond card (should succeed)
# ...

# Verify the game state after the successful play
# game.action_suit should be nil again
```
