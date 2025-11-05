# Clarification Results: Recycle Played Stack into Deck

**Feature**: 004-recycle-played-stack  
**Session Date**: 2025-11-05  
**Status**: ✅ Complete

---

## Design Decisions Made

### Decision 1: Flash Message Content ✅

**Question**: What message should players see when deck is recycled?

**Options Considered**:
- A) "Deck rebuilt from played cards"
- B) "Deck refilled - X cards recycled"
- C) No message (silent recycle)

**Decision**: **Option C - Silent recycle**

**Rationale**:
- Keeps UX seamless and non-interruptive
- Consistent with current draw behavior (no success flash)
- Players don't need to know internal mechanics
- Automatic operation should be invisible

---

### Decision 2: Infinite Recursion Guard ✅

**Question**: How to prevent infinite recursion if recycle fails?

**Options Considered**:
- A) Add `attempted_recycle` boolean parameter
- B) Check deck size after recycle before retry
- C) Return error, no retry

**Decision**: **Option B - Check deck size before retry**

**Rationale**:
- Simplest implementation
- Natural guard condition
- No parameter pollution
- Protects against edge cases

**Implementation**:
```elixir
case recycle_played_stack(game_session) do
  {:ok, recycled_session} ->
    # Guard: only retry if deck actually has cards now
    recycled_session = Repo.preload(recycled_session, [deck: :deck_cards])
    deck_size = count_deck_cards(recycled_session)
    
    if deck_size > 0 do
      draw_card_from_deck(recycled_session, player_id)
    else
      {:error, :deck_empty_after_recycle}
    end
  
  {:error, reason} ->
    {:error, reason}
end
```

---

### Decision 3: Order Index Assignment ✅

**Question**: Sequential indices or random gaps?

**Options Considered**:
- A) Sequential 1..N
- B) Random gaps

**Decision**: **Option A - Sequential 1..N**

**Rationale**:
- Matches initial deck creation pattern
- Simpler implementation
- No functional benefit to gaps
- Easier to debug

**Implementation**:
```elixir
num_cards = length(recyclable_cards)
shuffled_indices = Enum.shuffle(1..num_cards)

Enum.zip(recyclable_cards, shuffled_indices)
|> Enum.map(fn {card, index} ->
  DeckCard.changeset(card, %{
    location_type: "deck",
    order_index: index,
    player_id: nil
  })
end)
```

---

### Decision 4: Recycle Trigger Location ✅

**Question**: Where should recycle logic live?

**Options Considered**:
- A) Inside draw_card_from_deck/2
- B) Separate recycle_played_stack/1 function
- C) Called from LiveView

**Decision**: **Option B - Separate recycle_played_stack/1**

**Rationale**:
- Clean separation of concerns
- Independently testable
- Reusable for future features
- Follows SRP (Single Responsibility Principle)

**Function Signature**:
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
def recycle_played_stack(game_session)
```

---

### Decision 5: Topmost Card Identification ✅

**Question**: How to identify topmost card?

**Options Considered**:
- A) `Enum.max_by(&(&1.order_index))`
- B) `Enum.sort_by(...) |> List.last()`
- C) Database query for MAX

**Decision**: **Option A - Enum.max_by**

**Rationale**:
- Clearest intent
- Most efficient (single pass)
- Cards already in memory
- Explicit about what we're finding

**Implementation**:
```elixir
played_cards = Enum.filter(deck_cards, &(&1.location_type == "played_stack"))
topmost_card = Enum.max_by(played_cards, &(&1.order_index))
recyclable_cards = Enum.reject(played_cards, &(&1.id == topmost_card.id))
```

---

### Decision 6: Minimum Cards Validation ✅

**Question**: What error for insufficient cards?

**Options Considered**:
- A) `:insufficient_cards_to_recycle`
- B) `:deck_empty` (reuse)
- C) `:cannot_recycle`

**Decision**: **Option A - :insufficient_cards_to_recycle**

**Rationale**:
- Specific, clear error
- Distinguishable from other errors
- Helps debugging
- Can provide different user message if needed

**Error Cases**:
```elixir
case length(played_cards) do
  0 -> {:error, :no_cards_in_played_stack}
  1 -> {:error, :insufficient_cards_to_recycle}
  _ -> recycle_cards(played_cards)
end
```

---

### Decision 7: Broadcast Timing ✅

**Question**: When to broadcast game_updated?

**Options Considered**:
- A) After recycle only
- B) After complete draw flow
- C) Both times

**Decision**: **Option B - After complete draw flow**

**Rationale**:
- Single UI update (no flashing)
- Users care about final state
- Consistent with current pattern
- More efficient

**Implementation**:
```elixir
# In draw_card_from_deck/2
case deck_cards do
  [] ->
    case recycle_played_stack(game_session) do
      {:ok, recycled} ->
        # DON'T broadcast here
        draw_card_from_deck(recycled, player_id)  # Will broadcast after draw
      {:error, reason} ->
        {:error, reason}
    end
  
  [card | _] ->
    # ... draw logic ...
    # Broadcast ONCE here (after transaction)
end
```

**Note**: `recycle_played_stack/1` will NOT broadcast - only update database.

---

### Decision 8: Player ID Clearing ✅

**Question**: How to clear player_id on recycled cards?

**Options Considered**:
- A) Explicitly set player_id: nil
- B) Rely on validation
- C) Database trigger

**Decision**: **Option A - Explicit player_id: nil**

**Rationale**:
- Explicit is better than implicit
- Safer than relying on validation
- Clear intent in code
- No triggers needed

**Implementation**:
```elixir
DeckCard.changeset(card, %{
  location_type: "deck",
  order_index: shuffled_index,
  player_id: nil  # Explicitly clear
})
```

---

## Updated Implementation Strategy

Based on these decisions, here's the refined approach:

### Function: `recycle_played_stack/1`

```elixir
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
      # 9. Reload (NO BROADCAST - parent will handle)
      reloaded = Repo.get!(GameSession, game_session.id)
      {:ok, reloaded}
    
    {:error, _op, failed_value, _changes} ->
      {:error, failed_value}
  end
end
```

### Modified: `draw_card_from_deck/2`

```elixir
def draw_card_from_deck(game_session, player_id) do
  # ... existing validation ...
  
  deck_cards =
    game_session.deck.deck_cards
    |> Enum.filter(&(&1.location_type == "deck"))
    |> Enum.sort_by(& &1.order_index)
  
  case deck_cards do
    [] ->
      # NEW: Try recycling
      case recycle_played_stack(game_session) do
        {:ok, recycled_game_session} ->
          # Guard: verify deck has cards after recycle
          recycled_game_session = 
            Repo.preload(recycled_game_session, [deck: [deck_cards: :card]], force: true)
          
          recycled_deck_cards = 
            recycled_game_session.deck.deck_cards
            |> Enum.filter(&(&1.location_type == "deck"))
          
          if length(recycled_deck_cards) > 0 do
            # Retry draw (will broadcast after success)
            draw_card_from_deck(recycled_game_session, player_id)
          else
            {:error, :deck_empty_after_recycle}
          end
        
        {:error, reason} ->
          {:error, reason}
      end
    
    [card_to_draw | _] ->
      # ... existing draw logic with broadcast ...
  end
end
```

---

## Summary of Decisions

| # | Decision Area | Choice | Rationale |
|---|---------------|--------|-----------|
| 1 | Flash message | Silent (no message) | Seamless UX |
| 2 | Recursion guard | Check deck size | Simple, natural |
| 3 | Order indices | Sequential 1..N | Matches pattern |
| 4 | Function location | Separate function | Testable, modular |
| 5 | Topmost card | Enum.max_by | Clear, efficient |
| 6 | Error code | :insufficient_cards_to_recycle | Specific |
| 7 | Broadcast timing | After full flow | Single update |
| 8 | Player ID | Explicit nil | Safe, clear |

---

## Impact on Requirements

All original requirements remain satisfied:
- ✅ Take all played cards except topmost
- ✅ Shuffle cards randomly
- ✅ Assign new order_index values
- ✅ Move to deck location
- ✅ Keep topmost card visible
- ✅ Atomic transaction
- ✅ Broadcast update (after draw completes)

**Additional clarifications**:
- Minimum 2 cards required in played stack
- Silent operation (no flash message)
- Single broadcast after complete flow
- Recursion protected by deck size check

---

## Next Steps

1. ✅ Decisions made and documented
2. ⏳ Create data-model.md (data flow)
3. ⏳ Create quickstart.md (implementation guide)
4. ⏳ Run /speckit.tasks to generate task breakdown
5. ⏳ Begin implementation

---

**Session Status**: ✅ **COMPLETE** - All design decisions made, ready for task breakdown
