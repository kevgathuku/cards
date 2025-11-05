# Data Model: Recycle Played Stack into Deck

**Feature**: 004-recycle-played-stack  
**Date**: 2025-11-05  
**Status**: Design Complete

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Player Attempts to Draw Card from Empty Deck                │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ draw_card_from_deck(game_session, player_id)                │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ 1. Validate player's turn                             │   │
│ │ 2. Get deck cards WHERE location_type = 'deck'        │   │
│ │ 3. Check if deck is empty                             │   │
│ └───────────────────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ├── Deck has cards ──────────► Draw card normally
                  │
                  └── Deck is empty
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ recycle_played_stack(game_session)                          │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ 1. Get all played_stack cards                         │   │
│ │ 2. Validate count >= 2                                │   │
│ │ 3. Identify topmost card (max order_index)            │   │
│ │ 4. Filter recyclable cards (all except topmost)       │   │
│ │ 5. Shuffle indices: Enum.shuffle(1..N)                │   │
│ │ 6. Create changesets: location='deck', index=shuffled │   │
│ │ 7. Execute transaction (Ecto.Multi)                   │   │
│ └───────────────────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ├── Error (< 2 cards) ──────► Return error
                  │
                  └── Success
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ Verify Recycled Deck                                        │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ 1. Reload game_session with fresh deck_cards          │   │
│ │ 2. Count cards WHERE location_type = 'deck'           │   │
│ │ 3. Check if count > 0                                 │   │
│ └───────────────────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ├── Deck still empty ────────► Error (shouldn't happen)
                  │
                  └── Deck has cards
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ Retry: draw_card_from_deck(recycled_session, player_id)    │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ 1. Get deck cards (now populated)                     │   │
│ │ 2. Draw lowest order_index card                       │   │
│ │ 3. Update card: location='player_hand'                │   │
│ │ 4. Advance turn to next player                        │   │
│ │ 5. Execute transaction                                │   │
│ │ 6. Broadcast 'game_updated' event                     │   │
│ └───────────────────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ Return Success                                              │
│ Player has drawn card, turn advanced, all players updated   │
└─────────────────────────────────────────────────────────────┘
```

---

## Database State Transitions

### Before Recycle

```
deck_cards table:
┌──────┬─────────┬───────────────┬─────────────┬───────────┐
│ id   │ card_id │ location_type │ order_index │ player_id │
├──────┼─────────┼───────────────┼─────────────┼───────────┤
│ ...  │ ...     │ deck          │ ...         │ NULL      │ ← Empty!
├──────┼─────────┼───────────────┼─────────────┼───────────┤
│ 201  │ 15      │ played_stack  │ 1           │ NULL      │
│ 202  │ 23      │ played_stack  │ 2           │ NULL      │
│ 203  │ 41      │ played_stack  │ 3           │ NULL      │
│ 204  │ 8       │ played_stack  │ 4           │ NULL      │
│ 205  │ 37      │ played_stack  │ 5           │ NULL      │ ← Topmost
├──────┼─────────┼───────────────┼─────────────┼───────────┤
│ 301  │ 5       │ player_hand   │ NULL        │ 1         │
│ 302  │ 12      │ player_hand   │ NULL        │ 1         │
│ ...  │ ...     │ player_hand   │ NULL        │ ...       │
└──────┴─────────┴───────────────┴─────────────┴───────────┘
```

### After Recycle

```
deck_cards table:
┌──────┬─────────┬───────────────┬─────────────┬───────────┐
│ id   │ card_id │ location_type │ order_index │ player_id │
├──────┼─────────┼───────────────┼─────────────┼───────────┤
│ 201  │ 15      │ deck          │ 3           │ NULL      │ ← Shuffled
│ 202  │ 23      │ deck          │ 1           │ NULL      │ ← Shuffled
│ 203  │ 41      │ deck          │ 4           │ NULL      │ ← Shuffled
│ 204  │ 8       │ deck          │ 2           │ NULL      │ ← Shuffled
├──────┼─────────┼───────────────┼─────────────┼───────────┤
│ 205  │ 37      │ played_stack  │ 5           │ NULL      │ ← Kept topmost
├──────┼─────────┼───────────────┼─────────────┼───────────┤
│ 301  │ 5       │ player_hand   │ NULL        │ 1         │
│ 302  │ 12      │ player_hand   │ NULL        │ 1         │
│ ...  │ ...     │ player_hand   │ NULL        │ ...       │
└──────┴─────────┴───────────────┴─────────────┴───────────┘
```

**Key Changes**:
- 4 cards moved from `played_stack` → `deck`
- New `order_index` values: 1, 2, 3, 4 (sequential, shuffled order)
- 1 card remains in `played_stack` (topmost, order_index 5)
- All recycled cards have `player_id = NULL`

---

## Entity Relationships

```
GameSession
    ├── id (PK)
    ├── current_turn_player_id (FK → Player)
    └── deck_id (FK → Deck)
             │
             └── Deck
                  ├── id (PK)
                  ├── game_session_id (FK)
                  └── deck_cards (has_many)
                           │
                           └── DeckCard
                                ├── id (PK)
                                ├── deck_id (FK)
                                ├── card_id (FK → Card)
                                ├── player_id (FK → Player, nullable)
                                ├── location_type (string: "deck"|"played_stack"|"player_hand")
                                └── order_index (integer, nullable)
                                         │
                                         └── Card
                                              ├── id (PK)
                                              ├── suit (string)
                                              └── rank (string)
```

---

## Function Signatures

### Main Function

```elixir
@spec recycle_played_stack(GameSession.t()) :: 
  {:ok, GameSession.t()} | {:error, atom()}

def recycle_played_stack(game_session)
```

**Input**: GameSession struct (preloaded with deck and deck_cards)  
**Output**: 
- `{:ok, updated_game_session}` on success
- `{:error, :no_cards_in_played_stack}` when played stack empty
- `{:error, :insufficient_cards_to_recycle}` when only 1 card in stack

### Helper Functions

```elixir
@spec do_recycle(GameSession.t(), list(DeckCard.t())) :: 
  {:ok, GameSession.t()} | {:error, any()}

defp do_recycle(game_session, played_cards)
```

**Input**: GameSession + list of played_stack cards  
**Output**: Transaction result

---

## Validation Rules

### Recycle Eligibility

```elixir
played_cards_count >= 2
```

**Why**: Need minimum 1 card to recycle + 1 topmost to keep visible

### Topmost Card Selection

```elixir
topmost_card = Enum.max_by(played_cards, &(&1.order_index))
```

**Why**: Highest order_index represents most recently played card (visible on top)

### Recyclable Cards Filter

```elixir
recyclable_cards = Enum.reject(played_cards, &(&1.id == topmost_card.id))
```

**Why**: All played cards except topmost get recycled

### Order Index Assignment

```elixir
num_cards = length(recyclable_cards)
shuffled_indices = Enum.shuffle(1..num_cards)
```

**Why**: Sequential indices starting from 1, assigned in random order

---

## Transaction Structure

```elixir
multi =
  changesets
  |> Enum.with_index()
  |> Enum.reduce(Ecto.Multi.new(), fn {changeset, idx}, multi ->
    Ecto.Multi.update(multi, "card_#{idx}", changeset)
  end)

Repo.transaction(multi)
```

**Atomicity**: All card updates succeed or all fail  
**Isolation**: No partial state visible to other processes  
**Consistency**: Schema validations enforced on each changeset

---

## Changeset Structure

```elixir
DeckCard.changeset(deck_card, %{
  location_type: "deck",       # Move to deck
  order_index: shuffled_index,  # New random position
  player_id: nil                # Clear ownership
})
```

**Validations** (from schema):
- `location_type` must be "deck", "played_stack", or "player_hand"
- `order_index` required for "deck" location
- `order_index` must be > 0
- `player_id` must be nil for "deck" location
- Unique constraint: `[:deck_id, :location_type, :order_index]`

---

## Error Handling

```
recycle_played_stack/1
  │
  ├── No played cards ──────────► {:error, :no_cards_in_played_stack}
  │
  ├── Only 1 played card ───────► {:error, :insufficient_cards_to_recycle}
  │
  ├── Transaction failed ───────► {:error, changeset_errors}
  │
  └── Success ──────────────────► {:ok, game_session}
```

### Error Propagation

```elixir
# In draw_card_from_deck/2
case recycle_played_stack(game_session) do
  {:ok, recycled} -> 
    # Retry draw
    draw_card_from_deck(recycled, player_id)
  
  {:error, :insufficient_cards_to_recycle} ->
    # Propagate to user
    {:error, :insufficient_cards_to_recycle}
  
  {:error, reason} ->
    # Generic error
    {:error, reason}
end
```

---

## Broadcast Strategy

### NO Broadcast in recycle_played_stack/1

**Reason**: Parent function (`draw_card_from_deck/2`) handles broadcast after complete flow

### Single Broadcast After Draw

```elixir
# After successful draw (which may have included recycle)
KadiWeb.Endpoint.broadcast(
  "game:" <> to_string(game_session.id),
  "game_updated",
  %{game_session: reloaded_game_session}
)
```

**Benefits**:
- Single UI update (no flashing)
- Consistent with existing pattern
- Users see final state (card drawn, deck refilled)

---

## Performance Characteristics

### Database Operations

1. **SELECT**: 1 query to preload deck_cards (already done by caller)
2. **UPDATE**: N queries in transaction (where N = recyclable cards)
3. **SELECT**: 1 query to reload after transaction

**Total**: ~2 queries + N updates (N typically 40-50)

### Time Complexity

- Filter played cards: O(C) where C = total cards (~52)
- Find topmost: O(P) where P = played cards (1-50)
- Shuffle indices: O(N) where N = recyclable cards (1-49)
- Create changesets: O(N)
- Transaction: O(N) database round-trips

**Total**: O(C + P + 3N) ≈ O(N) where N is recyclable cards

### Expected Performance

- Typical: 40 cards recycled
- Transaction time: <100ms
- Total time: <200ms (well within 1 second goal)

---

## Concurrency Considerations

### Turn Validation Prevents Races

```elixir
# Only current turn player can draw
if game_session.current_turn_player_id != player_id do
  {:error, :not_your_turn}
end
```

**Protection**: Two players cannot simultaneously trigger recycle

### Database Transaction Isolation

- `Ecto.Multi` ensures atomic updates
- Row-level locks prevent concurrent modifications
- Unique constraints prevent duplicate order_index

---

## Summary

**Key Data Transformations**:
1. Played cards filtered by `location_type = "played_stack"`
2. Topmost identified by `max(order_index)`
3. Recyclable cards = all played cards except topmost
4. Indices shuffled: `Enum.shuffle(1..N)`
5. Cards updated: `location_type → "deck"`, `order_index → shuffled`, `player_id → nil`
6. Transaction committed atomically
7. Game session reloaded
8. Broadcast triggered by parent function

**Validation Chain**:
```
Count >= 2 → Identify topmost → Filter recyclable → 
Shuffle indices → Create changesets → Transaction → Success
```

**Performance Target**: <1 second (expected: <200ms)

**Error Cases**: 3 primary errors (no cards, insufficient cards, transaction failure)

**Broadcast Strategy**: Single broadcast after complete draw flow
