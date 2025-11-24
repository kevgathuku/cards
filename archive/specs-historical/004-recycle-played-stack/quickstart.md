# Quickstart Guide: Recycle Played Stack into Deck

**Feature**: 004-recycle-played-stack  
**Date**: 2025-11-05  
**For**: Developers implementing this feature

---

## Overview

This guide provides a step-by-step implementation approach for the deck recycling feature.

**What it does**: When a player tries to draw from an empty deck, automatically recycle played cards back into the deck (keeping the topmost card visible).

**Key files to modify**:
- `lib/kadi/card_games.ex` - Add `recycle_played_stack/1`, modify `draw_card_from_deck/2`

**No other files need changes** - feature is entirely backend, transparent to UI.

---

## Implementation Steps

### Step 1: Add `recycle_played_stack/1` Function

**Location**: `lib/kadi/card_games.ex` (add after `draw_card_from_deck/2`)

```elixir
@doc """
Recycles cards from the played stack back into the deck.

Takes all cards from played_stack except the topmost card, shuffles them,
assigns new order_index values (1..N), and moves them to deck location.

Minimum 2 cards required in played stack (1 to recycle + 1 topmost to keep).

Returns `{:ok, updated_game_session}` or `{:error, reason}`.

## Examples

    iex> recycle_played_stack(game_session)
    {:ok, %GameSession{}}
    
    iex> recycle_played_stack(one_card_game)
    {:error, :insufficient_cards_to_recycle}
"""
def recycle_played_stack(game_session) do
  # 1. Preload associations
  game_session = Repo.preload(game_session, [deck: [deck_cards: :card]])
  
  # 2. Get played cards
  played_cards = 
    game_session.deck.deck_cards
    |> Enum.filter(&(&1.location_type == "played_stack"))
  
  # 3. Validate minimum cards
  case length(played_cards) do
    0 -> {:error, :no_cards_in_played_stack}
    1 -> {:error, :insufficient_cards_to_recycle}
    _ -> do_recycle(game_session, played_cards)
  end
end

defp do_recycle(game_session, played_cards) do
  # 4. Identify topmost card (keep visible)
  topmost_card = Enum.max_by(played_cards, &(&1.order_index))
  
  # 5. Get recyclable cards (all except topmost)
  recyclable_cards = Enum.reject(played_cards, &(&1.id == topmost_card.id))
  
  # 6. Shuffle and assign indices
  num_cards = length(recyclable_cards)
  shuffled_indices = Enum.shuffle(1..num_cards)
  
  # 7. Create changesets
  changesets =
    Enum.zip(recyclable_cards, shuffled_indices)
    |> Enum.map(fn {card, index} ->
      DeckCard.changeset(card, %{
        location_type: "deck",
        order_index: index,
        player_id: nil
      })
    end)
  
  # 8. Build and execute transaction
  multi =
    changesets
    |> Enum.with_index()
    |> Enum.reduce(Ecto.Multi.new(), fn {changeset, idx}, multi ->
      Ecto.Multi.update(multi, "card_#{idx}", changeset)
    end)
  
  case Repo.transaction(multi) do
    {:ok, _results} ->
      # 9. Reload and return (NO BROADCAST - parent handles it)
      reloaded = Repo.get!(GameSession, game_session.id)
      {:ok, reloaded}
    
    {:error, _op, failed_value, _changes} ->
      {:error, failed_value}
  end
end
```

**Key points**:
- Uses `Enum.max_by` to find topmost card
- Shuffles indices, not cards
- Transaction is atomic (all or nothing)
- Does NOT broadcast (parent function will)

---

### Step 2: Modify `draw_card_from_deck/2`

**Location**: `lib/kadi/card_games.ex` (existing function, line ~218)

**Current code**:
```elixir
case deck_cards do
  [] ->
    {:error, :deck_empty}  # Current behavior
  
  [card_to_draw | _] ->
    # ... existing draw logic ...
end
```

**New code**:
```elixir
case deck_cards do
  [] ->
    # NEW: Try recycling before returning error
    case recycle_played_stack(game_session) do
      {:ok, recycled_game_session} ->
        # Guard: verify deck has cards after recycle
        recycled_game_session = 
          Repo.preload(recycled_game_session, [deck: [deck_cards: :card]], force: true)
        
        recycled_deck_cards = 
          recycled_game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "deck"))
          |> Enum.sort_by(& &1.order_index)
        
        if length(recycled_deck_cards) > 0 do
          # Retry draw (will broadcast after success)
          draw_card_from_deck(recycled_game_session, player_id)
        else
          {:error, :deck_empty_after_recycle}
        end
      
      {:error, reason} ->
        # Cannot recycle - return error
        {:error, reason}
    end
  
  [card_to_draw | _] ->
    # ... existing draw logic (unchanged) ...
end
```

**Key changes**:
- Intercept empty deck case
- Call `recycle_played_stack/1`
- Verify deck has cards after recycle (guard against edge cases)
- Recursively call `draw_card_from_deck/2` (will broadcast once after draw)

---

### Step 3: Handle New Error in LiveView (Optional)

**Location**: `lib/kadi_web/live/game_live.ex` (existing `handle_event("draw_card", ...)`)

**Add error handling** for new error types:

```elixir
def handle_event("draw_card", _params, socket) do
  # ... existing code ...
  
  case CardGames.draw_card_from_deck(game_session, current_player.id) do
    {:ok, _updated_game_session} ->
      {:noreply, socket}
    
    {:error, :not_your_turn} ->
      {:noreply, put_flash(socket, :error, "It's not your turn")}
    
    {:error, :deck_empty} ->
      {:noreply, put_flash(socket, :error, "No cards left in deck")}
    
    # NEW: Handle recycle errors
    {:error, :insufficient_cards_to_recycle} ->
      {:noreply, put_flash(socket, :error, "Cannot recycle: not enough cards in play")}
    
    {:error, :no_cards_in_played_stack} ->
      {:noreply, put_flash(socket, :error, "No cards available to draw")}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Error: #{reason}")}
  end
end
```

**Note**: These errors should rarely occur in normal gameplay.

---

## Testing Approach

### Unit Tests

**Location**: `test/kadi/card_games_test.exs`

```elixir
describe "recycle_played_stack/1" do
  test "successfully recycles cards from played stack" do
    # Setup: game with empty deck, 5 cards in played stack
    # Action: recycle_played_stack(game_session)
    # Assert: 4 cards in deck, 1 card in played stack (topmost)
  end
  
  test "keeps topmost card in played stack" do
    # Setup: played stack with order_index 1,2,3,4,5
    # Action: recycle_played_stack
    # Assert: card with order_index 5 still in played_stack
  end
  
  test "assigns sequential shuffled indices to recycled cards" do
    # Setup: 10 cards in played stack
    # Action: recycle
    # Assert: 9 cards in deck with order_index 1..9 (shuffled)
  end
  
  test "returns error when played stack is empty" do
    # Setup: no cards in played stack
    # Assert: {:error, :no_cards_in_played_stack}
  end
  
  test "returns error when only 1 card in played stack" do
    # Setup: 1 card in played stack
    # Assert: {:error, :insufficient_cards_to_recycle}
  end
  
  test "clears player_id on recycled cards" do
    # Setup: some played cards might have player_id (edge case)
    # Assert: all recycled cards have player_id = nil
  end
end
```

### Integration Tests

**Location**: `test/kadi_web/live/game_live_test.exs`

```elixir
describe "draw card with automatic recycle" do
  test "drawing from empty deck triggers recycle and succeeds" do
    # Setup: game with empty deck, 5 cards in played stack
    # Action: click "Draw Card"
    # Assert: player has +1 card, deck rebuilt, topmost card visible
  end
  
  test "multiple players see recycled deck" do
    # Setup: 2 connected players, empty deck
    # Action: player1 draws (triggers recycle)
    # Assert: player2 sees updated deck count
  end
  
  test "game continues normally after recycle" do
    # Setup: empty deck scenario
    # Action: draw card (recycle), next player draws
    # Assert: both draws succeed, turns advance
  end
end
```

---

## Common Pitfalls

### ❌ Pitfall 1: Broadcasting in recycle_played_stack/1

**Wrong**:
```elixir
def recycle_played_stack(game_session) do
  # ... recycle logic ...
  KadiWeb.Endpoint.broadcast(...)  # DON'T DO THIS
  {:ok, game_session}
end
```

**Right**:
```elixir
def recycle_played_stack(game_session) do
  # ... recycle logic ...
  # NO BROADCAST - parent will handle
  {:ok, game_session}
end
```

**Why**: Parent function broadcasts after complete flow (draw + recycle).

---

### ❌ Pitfall 2: Not guarding recursive call

**Wrong**:
```elixir
case recycle_played_stack(game_session) do
  {:ok, recycled} ->
    draw_card_from_deck(recycled, player_id)  # No guard!
end
```

**Right**:
```elixir
case recycle_played_stack(game_session) do
  {:ok, recycled} ->
    # Verify deck actually has cards
    if count_deck_cards(recycled) > 0 do
      draw_card_from_deck(recycled, player_id)
    else
      {:error, :deck_empty_after_recycle}
    end
end
```

**Why**: Prevents infinite recursion if recycle somehow produces empty deck.

---

### ❌ Pitfall 3: Sorting instead of max_by

**Wrong**:
```elixir
topmost = played_cards |> Enum.sort_by(&(&1.order_index)) |> List.last()
```

**Right**:
```elixir
topmost = Enum.max_by(played_cards, &(&1.order_index))
```

**Why**: More efficient (O(n) vs O(n log n)), clearer intent.

---

### ❌ Pitfall 4: Forgetting to clear player_id

**Wrong**:
```elixir
DeckCard.changeset(card, %{
  location_type: "deck",
  order_index: index
  # Missing player_id: nil
})
```

**Right**:
```elixir
DeckCard.changeset(card, %{
  location_type: "deck",
  order_index: index,
  player_id: nil  # Explicit!
})
```

**Why**: Schema validation requires player_id = nil for deck cards.

---

## Debugging Tips

### Check played stack before recycle

```elixir
played_cards = get_played_cards(game_session)
IO.inspect(length(played_cards), label: "Played cards count")
IO.inspect(Enum.map(played_cards, & &1.order_index), label: "Order indices")
```

### Verify deck after recycle

```elixir
{:ok, recycled} = recycle_played_stack(game_session)
deck_cards = get_deck_cards(recycled)
IO.inspect(length(deck_cards), label: "Deck size after recycle")
```

### Trace transaction

```elixir
case Repo.transaction(multi) do
  {:ok, results} ->
    IO.inspect(Map.keys(results), label: "Transaction results")
    {:ok, game_session}
  
  {:error, op, failed_value, _} ->
    IO.inspect({op, failed_value}, label: "Transaction failed")
    {:error, failed_value}
end
```

---

## Performance Optimization

### Avoid redundant preloads

```elixir
# BAD: Multiple preloads
game_session = Repo.preload(game_session, :deck)
game_session = Repo.preload(game_session, [deck: :deck_cards])
game_session = Repo.preload(game_session, [deck: [deck_cards: :card]])

# GOOD: Single preload
game_session = Repo.preload(game_session, [deck: [deck_cards: :card]])
```

### Batch updates in transaction

Already optimized - all card updates happen in single transaction via `Ecto.Multi`.

### Use force reload when needed

```elixir
# After recycle, force reload to get fresh data
Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)
```

---

## Rollout Checklist

- [ ] Implement `recycle_played_stack/1` function
- [ ] Modify `draw_card_from_deck/2` with recycle logic
- [ ] Add recursion guard (deck size check)
- [ ] Add error handling in LiveView
- [ ] Write unit tests (6+ test cases)
- [ ] Write integration tests (3+ test cases)
- [ ] Run full test suite (`mix test`)
- [ ] Manual testing: empty deck scenario
- [ ] Manual testing: 1 card in played stack
- [ ] Manual testing: 50 card recycle
- [ ] Performance test: verify <1 second
- [ ] Code review
- [ ] Merge to main

---

## Quick Reference

**Function signature**:
```elixir
def recycle_played_stack(game_session) :: {:ok, GameSession.t()} | {:error, atom()}
```

**Error codes**:
- `:no_cards_in_played_stack` - played stack is empty
- `:insufficient_cards_to_recycle` - only 1 card in played stack
- `:deck_empty_after_recycle` - recycle succeeded but deck still empty (edge case)

**Key pattern**:
```elixir
Enum.shuffle(1..N)  # Shuffle indices
|> Enum.zip(cards)  # Zip with cards
|> Enum.map(fn {card, idx} -> changeset(card, idx) end)
|> build_multi()
|> Repo.transaction()
```

**Topmost card**:
```elixir
Enum.max_by(played_cards, &(&1.order_index))
```

**No broadcast** in recycle function - parent handles it!

---

## Summary

1. Add `recycle_played_stack/1` - no broadcast
2. Modify `draw_card_from_deck/2` - add recycle call with guard
3. Optional: add error handling in LiveView
4. Test: unit + integration
5. Verify: performance <1 second

**Total implementation time**: ~4 hours (including tests)

**Files changed**: 1 (card_games.ex), optionally 2 (game_live.ex for error messages)

**Lines added**: ~80 lines (main function + helper + modification to draw)
