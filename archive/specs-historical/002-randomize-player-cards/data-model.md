# Data Model: Randomize Player Card Distribution

**Date**: 2025-11-03
**Feature**: 002-randomize-player-cards

## Overview

This feature does **not introduce new data models or schema changes**. It modifies the behavior of how existing data is read and processed during card dealing. This document describes the existing data model and how `order_index` is used.

## Existing Entities

### DeckCard (Primary Entity)

**Schema**: `deck_cards` table
**Module**: `Kadi.Games.DeckCard` (`lib/kadi/games/deck_card.ex`)

**Relevant Fields**:
```elixir
schema "deck_cards" do
  field :location_type, :string     # "deck" | "player_hand" | "played_stack"
  field :order_index, :integer      # Randomized 1..52 for "deck", sequential for "played_stack", nil for "player_hand"
  field :player_id, :id             # Foreign key when location_type = "player_hand"

  belongs_to :deck, Kadi.Games.Deck
  belongs_to :card, Kadi.Games.Card

  timestamps()
end
```

**Constraints**:
- `unique_constraint([:deck_id, :location_type, :order_index])` - Ensures no duplicate positions within a location
- `order_index` is **required** for `location_type = "deck"` and `"played_stack"`
- `order_index` must be **nil** for `location_type = "player_hand"` (hands are unordered)
- `order_index` must be **> 0** when present

**Lifecycle States**:

| location_type | order_index | player_id | Meaning |
|---------------|-------------|-----------|---------|
| `"deck"` | 1..52 (randomized) | nil | Card in draw pile, position determines dealing order |
| `"player_hand"` | nil | player_id | Card in player's hand (unordered) |
| `"played_stack"` | 1, 2, 3, ... (sequential) | nil | Card in played pile, order_index indicates play sequence |

### Card

**Schema**: `cards` table
**Module**: `Kadi.Games.Card`

**Fields**:
```elixir
schema "cards" do
  field :suit, :string   # "hearts", "diamonds", "clubs", "spades"
  field :rank, :string   # "2".."10", "jack", "queen", "king", "ace"

  has_many :deck_cards, Kadi.Games.DeckCard

  timestamps()
end
```

**Note**: 52 shared cards across all games. Cards are **immutable**; only their `deck_cards` associations change.

### Deck

**Schema**: `decks` table
**Module**: `Kadi.Games.Deck`

**Fields**:
```elixir
schema "decks" do
  belongs_to :game_session, Kadi.Games.GameSession
  has_many :deck_cards, Kadi.Games.DeckCard

  timestamps()
end
```

**Relationship**: Each `game_session` has exactly one `deck`, which has 52 `deck_cards` (one for each of the 52 shared cards).

### GameSession

**Schema**: `game_sessions` table
**Module**: `Kadi.Games.GameSession`

**Relevant Fields**:
```elixir
schema "game_sessions" do
  field :status, :string  # "lobby" | "live" | "finished"
  field :current_turn_player_id, :id

  has_one :deck, Kadi.Games.Deck
  many_to_many :players, Kadi.Accounts.Player, join_through: Kadi.Games.GameSessionPlayer

  timestamps()
end
```

## Data Flow: Card Dealing

### Phase 1: Deck Creation (Existing, Unchanged)

**Trigger**: `create_game_session/1`
**Location**: `lib/kadi/card_games.ex:102-131`

```
Input: game_session (status = "lobby")
  ↓
Generate 52 card attributes (suits × ranks)
  ↓
Shuffle indices: [1..52] → [23, 5, 41, 18, ...]  ← RANDOMIZATION HAPPENS HERE
  ↓
For each (card, order_index) pair:
  Create deck_card:
    deck_id: <deck.id>
    card_id: <card.id>
    location_type: "deck"
    order_index: <randomized_value>  ← Stored in database
    player_id: nil
  ↓
Output: Deck with 52 deck_cards, each with unique randomized order_index
```

### Phase 2: Card Dealing (Modified by This Feature)

**Trigger**: `start_game/1`
**Location**: `lib/kadi/card_games.ex:194-221`

**BEFORE (Current Buggy Behavior)**:
```
Input: deck_cards (preloaded)
  ↓
Filter: location_type = "deck"  → List of 52 cards (UNSORTED!)
  ↓
Split: Take first N cards → [card1, card2, card3, ..., cardN]  ← WRONG ORDER!
  ↓
Distribute to players:
  Player 1: [card1, card2, card3, card4]       ← May be sequential!
  Player 2: [card5, card6, card7, card8]       ← May be sequential!
  ...
```

**AFTER (Fixed Behavior with This Feature)**:
```
Input: deck_cards (preloaded)
  ↓
Filter: location_type = "deck"  → List of 52 cards
  ↓
Sort by order_index: [23, 5, 41, 18, ...] → [5, 18, 23, 41, ...]  ← NEW STEP!
  ↓
Split: Take first N cards by sorted order_index → [card_5, card_18, card_23, ...]
  ↓
Distribute to players:
  Player 1: [card with order_index=5, =18, =23, =41]  ← Randomized sequence!
  Player 2: [next 4 by order_index]
  ...
  ↓
Update each dealt card:
  location_type: "deck" → "player_hand"
  order_index: <value> → nil
  player_id: nil → <player.id>
```

## Key Invariants

### Before This Feature

❌ **VIOLATED**: Cards dealt to players follow insertion/preload order (may be sequential by suit/rank)

### After This Feature

✅ **ENSURED**:
1. Cards are dealt in ascending `order_index` order
2. `order_index` values are randomized during deck creation (`Enum.shuffle`)
3. Distribution is deterministic based on `order_index` (enables replay/debugging)
4. Sequential card patterns (e.g., 4,5,6,7 of hearts) are statistically unlikely within a single player's hand

## Schema Changes Required

**None**. The `order_index` field already exists with appropriate constraints:
- Unique constraint: `[:deck_id, :location_type, :order_index]`
- Migration: `20250922205611_alter_deck_cards_add_location_position.exs`

## Query Patterns

### Current Query (in `do_start_game/1`)

```elixir
game_session
|> Repo.preload(deck: [deck_cards: :card])
```

**Loads**:
- `game_session`
  - `deck`
    - `deck_cards` (52 records)
      - `card` (associated card with suit/rank)

**Order**: Undefined (depends on database query planner)

### Processing After Query (Modified by This Feature)

**Before**:
```elixir
deck_cards
|> Enum.filter(&(&1.location_type == "deck"))
|> Enum.split(cards_to_deal_count)
```

**After**:
```elixir
deck_cards
|> Enum.filter(&(&1.location_type == "deck"))
|> Enum.sort_by(& &1.order_index)  # ← NEW
|> Enum.split(cards_to_deal_count)
```

## Performance Implications

### Database
- **Queries**: No change (same preload)
- **Indexes**: Existing unique index on `[:deck_id, :location_type, :order_index]` supports efficient constraint validation

### In-Memory Processing
- **Filter**: O(52) = O(1) for practical purposes
- **Sort**: O(52 log 52) ≈ 312 comparisons = <1ms
- **Split**: O(n) where n ≤ 52 = <1ms

**Total impact**: Sub-millisecond, negligible within 2-second game initialization budget.

## Testing Implications

### Data Setup for Tests

**Factory Pattern** (recommended):
```elixir
def deck_card_factory(attrs \\ %{}) do
  %DeckCard{
    deck_id: attrs[:deck_id] || insert(:deck).id,
    card_id: attrs[:card_id] || insert(:card).id,
    location_type: attrs[:location_type] || "deck",
    order_index: attrs[:order_index] || Enum.random(1..52),
    player_id: attrs[:player_id]
  }
end

def deck_with_known_order(order_indices) do
  deck = insert(:deck)
  cards = insert_list(52, :card)

  Enum.zip(cards, order_indices)
  |> Enum.map(fn {card, order_index} ->
    insert(:deck_card, deck_id: deck.id, card_id: card.id, order_index: order_index)
  end)

  deck
end
```

### Test Scenarios

1. **Known Order Test**: Create deck with specific `order_index` sequence, verify dealing follows that sequence
2. **Randomization Test**: Create 100 decks with randomized `order_index`, verify no consistent sequential patterns
3. **Edge Case Test**: Deck with all low `order_index` values assigned to special cards (2, 3, J, Q, K, A)

## Migration History

No migrations required for this feature. Relevant existing migration:

**File**: `priv/repo/migrations/20250922205611_alter_deck_cards_add_location_position.exs`

```elixir
def change do
  alter table(:deck_cards) do
    add :order_index, :integer
  end

  create unique_index(:deck_cards, [:deck_id, :location_type, :order_index])
end
```

**Note**: This migration was added for feature 001-deal-start-card and is already applied.

## Summary

This feature is a **behavioral change**, not a data model change. It corrects the card dealing algorithm to respect the existing, already-randomized `order_index` field. No schema modifications, new tables, or migrations are required.

**Key Points**:
- ✅ `order_index` already exists and is randomized
- ✅ Constraints already enforce uniqueness and valid ranges
- ✅ Modification is purely in-memory sorting logic
- ✅ No breaking changes to existing data or API contracts
