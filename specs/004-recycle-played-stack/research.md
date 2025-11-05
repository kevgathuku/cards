# Research: Recycle Played Stack into Deck

**Feature**: 004-recycle-played-stack  
**Research Date**: 2025-11-05  
**Status**: ✅ Complete

---

## Research Questions & Findings

### Q1: How is "topmost" card in played stack identified?

**Answer**: By **highest `order_index`** value in played_stack.

**Evidence**:
- UI displays topmost card using `List.last(@played_pile)` (game_live.html.heex:39)
- Played pile is sorted by `order_index`: `Enum.sort_by(& &1.order_index)` (game_live.ex:140)
- `List.last/1` on sorted list gives highest order_index
- Starting card is assigned `order_index: 1` (card_games.ex:331)

**Conclusion**: To keep topmost card visible, filter for `max(order_index)` in played_stack and exclude it from recycling.

---

### Q2: What shuffle algorithm is currently used in `create_game_session`?

**Answer**: `Enum.shuffle/1` on range `1..52`

**Evidence**:
```elixir
# lib/kadi/card_games.ex:105
order_indices = Enum.shuffle(1..52)
```

**Details**:
- Shuffles a list of integers (1-52)
- Each integer is then assigned to a card as `order_index`
- Uses Erlang's `:rand` module (pseudo-random, sufficient for games)
- Same approach should work for recycling

**Conclusion**: Use `Enum.shuffle(1..N)` where N = number of cards to recycle, then zip with cards.

---

### Q3: How should `order_index` be assigned to recycled cards?

**Answer**: Assign sequential indices starting from 1, in shuffled order.

**Evidence**:
- Initial deck creation uses `1..52` (card_games.ex:105)
- Deck cards are sorted by `order_index` ascending (card_games.ex:233)
- Lowest `order_index` is drawn first (card_games.ex:239: `[card_to_draw | _]`)
- Starting played card gets `order_index: 1` (card_games.ex:331)

**Implementation**:
```elixir
# Pseudocode for recycling
recyclable_cards = get_recyclable_cards(played_stack)  # All except topmost
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

**Conclusion**: Use sequential indices `1..N` after shuffling cards (same pattern as initial deck).

---

### Q4: What broadcast message format should be used for recycle events?

**Answer**: Use existing `"game_updated"` event with full `game_session` payload.

**Evidence**:
```elixir
# lib/kadi/card_games.ex:272-276 (from draw_card_from_deck)
KadiWeb.Endpoint.broadcast(
  "game:" <> to_string(reloaded_game_session.id),
  "game_updated",
  %{game_session: reloaded_game_session}
)
```

**Pattern**:
1. Reload game session with preloads: `Repo.get!(GameSession, id) |> Repo.preload(:created_by)`
2. Broadcast to topic: `"game:" <> game_session_id`
3. Event type: `"game_updated"`
4. Payload: `%{game_session: reloaded_game_session}`

**Conclusion**: Recycle function should follow identical broadcast pattern. No new event type needed.

---

### Q5: Should recycle be automatic or require player confirmation?

**Answer**: **Automatic** - triggered when deck is empty and player attempts to draw.

**Evidence**:
- Feature 003 returns `{:error, :deck_empty}` when deck is empty (card_games.ex:237)
- Current UX hides "Draw Card" button when `@deck_size == 0` (game_live.html.heex:22)
- No manual "recycle" action exists in UI or spec
- Game flow should be seamless (avoid interruption)

**Implementation Strategy**:
1. Modify `draw_card_from_deck/2` to detect empty deck
2. Check if recycling is possible (played_stack has 2+ cards)
3. If yes: call `recycle_played_stack/1`, then retry draw
4. If no: return `{:error, :cannot_recycle_insufficient_cards}`

**Conclusion**: Automatic recycling integrated into draw flow. No UI button needed.

---

### Q6: What happens if played stack is empty or has only 1 card?

**Answer**: Cannot recycle - return error.

**Edge Cases**:

| Played Stack Size | Can Recycle? | Action |
|-------------------|--------------|--------|
| 0 cards | ❌ No | Return `{:error, :no_cards_to_recycle}` |
| 1 card (topmost) | ❌ No | Return `{:error, :insufficient_cards_to_recycle}` |
| 2 cards | ✅ Yes | Recycle 1 card (keep topmost) |
| 3+ cards | ✅ Yes | Recycle N-1 cards (keep topmost) |

**Validation Logic**:
```elixir
played_cards = Enum.filter(deck_cards, &(&1.location_type == "played_stack"))

case length(played_cards) do
  0 -> {:error, :no_cards_to_recycle}
  1 -> {:error, :insufficient_cards_to_recycle}
  _ -> recycle_cards(played_cards)
end
```

**Conclusion**: Require minimum 2 cards in played stack. Keep topmost (highest order_index), recycle rest.

---

## Current Code Patterns

### Played Stack Management

**Schema** (`lib/kadi/games/deck_card.ex`):
- `location_type`: `"deck"`, `"played_stack"`, or `"player_hand"`
- `order_index`: Required for deck/played_stack, `nil` for player_hand
- Validation ensures `order_index > 0` for played_stack

**Creating Played Stack** (`lib/kadi/card_games.ex:331`):
```elixir
DeckCard.changeset(start_card, %{
  location_type: "played_stack", 
  order_index: 1
})
```

**Retrieving Played Pile** (`lib/kadi_web/live/game_live.ex:137-140`):
```elixir
played_pile =
  all_deck_cards
  |> Enum.filter(&(&1.location_type == "played_stack"))
  |> Enum.sort_by(& &1.order_index)
```

**UI Display** (`lib/kadi_web/live/game_live.html.heex:39`):
```heex
<%= if top_card = List.last(@played_pile) do %>
  <span>{top_card.card.rank} of {top_card.card.suit}</span>
<% end %>
```

---

### Shuffle Pattern

**Current Implementation** (`lib/kadi/card_games.ex:105-110`):
```elixir
order_indices = Enum.shuffle(1..52)
cards = generate_cards_attrs()

Enum.zip([cards, order_indices])
|> Enum.each(fn {card_attrs, order_index} ->
  # ... create deck_cards with order_index
end)
```

**Key Points**:
- Shuffle indices, not cards
- Zip cards with shuffled indices
- Assign `order_index` during insertion

---

### Transaction Pattern

**draw_card_from_deck Example** (`lib/kadi/card_games.ex:245-265`):
```elixir
multi =
  Ecto.Multi.new()
  |> Ecto.Multi.update(:deck_card, card_changeset)
  |> Ecto.Multi.update(:game_session, session_changeset)

case Repo.transaction(multi) do
  {:ok, %{game_session: updated_session}} ->
    reloaded = Repo.get!(GameSession, updated_session.id) |> Repo.preload(:created_by)
    KadiWeb.Endpoint.broadcast(...)
    {:ok, reloaded}
  
  {:error, _op, failed_value, _changes} ->
    {:error, failed_value}
end
```

**Recycle will use similar pattern**:
1. Build `Ecto.Multi` with multiple card updates
2. Execute transaction
3. Reload game session with preloads
4. Broadcast update
5. Return result

---

### Broadcast Pattern

**Topic Format**: `"game:" <> to_string(game_session_id)`  
**Event Type**: `"game_updated"`  
**Payload**: `%{game_session: reloaded_game_session}`

**Preload Requirements**:
- `:created_by` (minimum)
- Optionally: `[deck: [deck_cards: :card]]` if needed in response

---

## Database Schema Constraints

From `lib/kadi/games/deck_card.ex`:

**Validations**:
- `location_type` must be one of: `"deck"`, `"played_stack"`, `"player_hand"`
- `order_index` required for `"deck"` and `"played_stack"`
- `order_index` must be `nil` for `"player_hand"`
- `player_id` must be `nil` for `"deck"` and `"played_stack"`
- `player_id` required for `"player_hand"`
- `order_index` must be `> 0` when present

**Unique Constraints**:
- `[:deck_id, :card_id]` - each card appears once per deck
- `[:deck_id, :location_type, :order_index]` - no duplicate order within location

**Implication for Recycling**:
- Must clear `player_id` when moving to deck
- Must assign valid `order_index` (> 0)
- Must ensure no duplicate order_index values in deck

---

## Implementation Strategy

### Proposed Function: `recycle_played_stack/1`

**Signature**:
```elixir
def recycle_played_stack(game_session) do
  # Returns {:ok, updated_game_session} | {:error, reason}
end
```

**Algorithm**:
```elixir
1. Preload game_session with deck and deck_cards
2. Get all played_stack cards, sorted by order_index
3. Validate minimum 2 cards exist
4. Identify topmost card (highest order_index)
5. Filter recyclable cards (all except topmost)
6. Shuffle indices: Enum.shuffle(1..num_recyclable)
7. Create changesets for each card:
   - location_type: "deck"
   - order_index: shuffled_index
   - player_id: nil
8. Build Ecto.Multi with all updates
9. Execute transaction
10. Reload game_session with preloads
11. Broadcast "game_updated" event
12. Return {:ok, game_session}
```

**Error Cases**:
- `{:error, :no_cards_to_recycle}` - played stack is empty
- `{:error, :insufficient_cards_to_recycle}` - only 1 card in played stack

---

### Integration with `draw_card_from_deck/2`

**Modified Flow**:
```elixir
def draw_card_from_deck(game_session, player_id) do
  # ... existing validation ...
  
  deck_cards = get_deck_cards(game_session)
  
  case deck_cards do
    [] ->
      # NEW: Try to recycle before returning error
      case recycle_played_stack(game_session) do
        {:ok, recycled_game_session} ->
          # Retry draw with recycled deck
          draw_card_from_deck(recycled_game_session, player_id)
        
        {:error, reason} ->
          # Cannot recycle - return error
          {:error, reason}
      end
    
    [card_to_draw | _] ->
      # ... existing draw logic ...
  end
end
```

**Benefits**:
- Seamless user experience
- No UI changes needed
- Automatic recovery from empty deck
- Recursive call ensures draw completes after recycle

---

## Testing Strategy

### Unit Tests for `recycle_played_stack/1`

**Test Cases**:
1. ✅ Successfully recycles 10 cards (keep topmost)
2. ✅ Successfully recycles 2 cards (minimum: 1 recyclable + 1 topmost)
3. ✅ Shuffles cards randomly (check order_index distribution)
4. ✅ Keeps topmost card in played_stack
5. ✅ Returns error when played stack has 1 card
6. ✅ Returns error when played stack is empty
7. ✅ Clears player_id on recycled cards
8. ✅ Assigns valid order_index (1..N)
9. ✅ Broadcasts game_updated event
10. ✅ Transaction rollback on error

### Integration Tests

**Test Cases**:
1. ✅ Draw card from empty deck triggers recycle
2. ✅ After recycle, player can draw card successfully
3. ✅ Multiple players see recycled deck
4. ✅ UI shows updated deck count after recycle
5. ✅ Topmost card remains visible after recycle
6. ✅ Game continues normally after recycle

---

## Performance Considerations

**Expected Load**:
- Typical recycle: 40-50 cards
- Single batch UPDATE for all cards
- Transaction should complete in <100ms

**Optimization**:
- Use `Ecto.Multi.update_all` for batch updates if needed
- Ensure indices on `deck_id`, `location_type`
- Preload associations in single query

**Benchmarking**:
- Add performance test: ensure <1 second total time
- Measure transaction time with `:timer.tc`

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Infinite recursion if recycle fails | Add guard to prevent retry after recycle attempt |
| Topmost card identification error | Use `Enum.max_by(&(&1.order_index))` for clarity |
| Duplicate order_index values | Ensure sequential assignment `1..N` |
| Performance with 50+ cards | Batch update, measure with benchmark |
| Race condition (multiple players) | Existing turn validation prevents simultaneous draws |

---

## Open Questions for Design Phase

1. **Flash message content**: What should users see when deck is recycled?
   - Option A: "Deck rebuilt from played cards"
   - Option B: "Deck refilled - X cards recycled"
   - Option C: No message (silent recycle)

2. **Visual feedback**: Should recycling have UI indication?
   - Option A: Flash message only
   - Option B: Brief animation (deck icon spin)
   - Option C: Counter showing "X cards recycled"

3. **Guard against infinite recursion**: How to prevent retry loop?
   - Option A: Add `attempted_recycle` flag to function params
   - Option B: Check deck size after recycle before retry
   - Option C: Return specific error after recycle attempt

4. **Order index gaps**: Should recycled deck use 1..N or have gaps?
   - Current: Sequential 1..N (recommended for simplicity)
   - Alternative: Random gaps (unnecessary complexity)

---

## Next Steps

1. ✅ Research complete
2. ⏳ Design phase: Define function signatures and error handling
3. ⏳ Task breakdown: Create detailed implementation tasks
4. ⏳ Implementation: Build and test feature
5. ⏳ Integration: Merge with draw_card_from_deck

---

## Summary

**Key Findings**:
- Topmost card = highest `order_index` in played_stack
- Shuffle using `Enum.shuffle(1..N)` (existing pattern)
- Automatic recycle on empty deck (no UI button)
- Minimum 2 cards required (1 recyclable + 1 topmost)
- Use existing broadcast pattern (`"game_updated"`)
- Integrate with `draw_card_from_deck/2` via retry logic

**No Blockers**: All necessary infrastructure exists. Ready to proceed to design phase.

**Recommendation**: Proceed with automatic recycling, silent operation (flash message optional), sequential order_index assignment.
