# Research: Randomize Player Card Distribution

**Date**: 2025-11-03
**Feature**: 002-randomize-player-cards

## Overview

This document consolidates research findings for implementing randomized card distribution to players using the existing `order_index` mechanism.

## Current Implementation Analysis

### Deck Creation (`create_deck_for_session/1`)

**Location**: `lib/kadi/card_games.ex:102-131`

**Current Behavior**:
```elixir
order_indices = Enum.shuffle(1..52)  # Line 105 - GOOD: Already randomizing!
cards = generate_cards_attrs()

Enum.zip([cards, order_indices])
|> Enum.each(fn {card_attrs, order_index} ->
  # Assigns randomized order_index to each deck_card
  deck_card_attrs = %{
    deck_id: deck.id,
    card_id: card.id,
    location_type: "deck",
    order_index: order_index  # Line 122 - Randomized value
  }
  {:ok, _deck_card} = Repo.insert(DeckCard.changeset(%DeckCard{}, deck_card_attrs))
end)
```

**Finding**: `order_index` is **already randomized** during deck creation using `Enum.shuffle(1..52)`.

### Card Dealing (`deal_cards/2`)

**Location**: `lib/kadi/card_games.ex:194-221`

**Current Behavior**:
```elixir
defp deal_cards(players, deck_cards) do
  cards_in_deck = Enum.filter(deck_cards, &(&1.location_type == "deck"))  # Line 195
  # ... validation ...
  {cards_to_deal, remaining_cards} = Enum.split(cards_in_deck, cards_to_deal_count)  # Line 201

  changesets = Enum.with_index(players)
    |> Enum.flat_map(fn {player, i} ->
      start_index = i * 4
      end_index = start_index + 3
      player_cards = Enum.slice(cards_to_deal, start_index..end_index)  # Line 208
      # ... create changesets ...
    end)
end
```

**Problem Identified**:
- Line 195 filters cards but **does not sort by `order_index`**
- Line 201 splits based on the **unsorted list order** (likely database insertion order or preload order)
- This means the randomized `order_index` values are **ignored during dealing**

**Impact**: Cards are dealt in whatever order they happen to be loaded from the database, which may be sequential by suit/rank if the database returns them in `card_id` order.

## Solution Design

### Decision: Sort by `order_index` Before Dealing

**Rationale**:
1. **Minimal change**: Add single line `|> Enum.sort_by(& &1.order_index)` after line 195
2. **Preserves existing randomization**: Uses the already-randomized `order_index` values from deck creation
3. **Deterministic replay**: Order based on database field, not runtime randomness
4. **Performance**: Sorting 52 integers is O(n log n) ≈ negligible (<1ms)

### Implementation Location

**File**: `lib/kadi/card_games.ex`
**Function**: `deal_cards/2` (private function, lines 194-221)
**Modification**:
```elixir
# BEFORE (Line 195):
cards_in_deck = Enum.filter(deck_cards, &(&1.location_type == "deck"))

# AFTER (Line 195-196):
cards_in_deck =
  deck_cards
  |> Enum.filter(&(&1.location_type == "deck"))
  |> Enum.sort_by(& &1.order_index)  # NEW: Sort by randomized order_index
```

### Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| Re-shuffle in `deal_cards/2` | Simple | Destroys determinism, ignores pre-randomized `order_index` | ❌ Rejected |
| Query with ORDER BY | Sorts at DB level | Adds query overhead, unnecessary (already preloaded) | ❌ Rejected |
| **Sort by `order_index`** | Minimal, deterministic, uses existing field | None | ✅ **Selected** |
| Validate randomization | Detects bad shuffles | Doesn't fix dealing order | ⚠️ Add as supplementary test |

## Validation Strategy

### Test Case 1: Order Preservation
- **Given**: A deck with known `order_index` sequence [5, 12, 3, 47, ...]
- **When**: Cards are dealt to 3 players (12 cards total)
- **Then**: Players receive cards in ascending `order_index` order
  - Player 1 gets cards with `order_index` values [3, 5, 12, 47]
  - Player 2 gets next 4 in `order_index` sequence
  - Player 3 gets next 4 in `order_index` sequence

### Test Case 2: No Sequential Patterns
- **Given**: 1000 game starts with different random seeds
- **When**: Analyzing all player hands
- **Then**: <1% of hands contain 3+ consecutive ranks of same suit (statistical threshold)

### Test Case 3: Edge Case - 2 Players
- **Given**: Game with only 2 players
- **When**: Cards are dealt
- **Then**: Each player receives 4 cards in `order_index` order (even if sequential by chance)

### Test Case 4: Edge Case - All Special Cards at Start
- **Given**: Deck where first 20 cards (by `order_index`) are all special (2, 3, J, Q, K, A)
- **When**: Dealing to 4 players (16 cards) then selecting start card
- **Then**: Players receive first 16 cards by `order_index`, start card selection skips to non-special card

## Ecto/Phoenix Best Practices

### Pattern: Sort After Preload

**Standard Pattern**:
```elixir
game_session
|> Repo.preload(deck: [deck_cards: :card])  # Preload associations
|> then(fn gs ->
  sorted_cards = Enum.sort_by(gs.deck.deck_cards, & &1.order_index)
  # Use sorted_cards
end)
```

**Rationale**: Sorting in-memory after preload is more efficient than:
- Multiple queries
- Database-level ORDER BY on associations (Ecto doesn't easily support this for nested preloads)

### Pattern: Immutable Transformations

**Elixir Idiom**:
```elixir
cards_in_deck
|> Enum.filter(&(&1.location_type == "deck"))
|> Enum.sort_by(& &1.order_index)
|> Enum.split(cards_to_deal_count)
```

Creates new list at each step; original `deck_cards` unchanged.

## Performance Analysis

### Current Performance
- **Preload**: ~10-20ms (existing, unchanged)
- **Filter**: O(n) where n=52 → <1ms
- **Split**: O(n) → <1ms
- **Total dealing**: ~1-2ms + preload time

### With Sorting
- **Preload**: ~10-20ms (unchanged)
- **Filter**: O(n) → <1ms
- **Sort**: O(n log n) where n≤52 → <1ms (52 * log₂(52) ≈ 52 * 6 = 312 comparisons)
- **Split**: O(n) → <1ms
- **Total dealing**: ~1-2ms + preload time (effectively unchanged)

**Conclusion**: Performance impact is negligible (sub-millisecond). Well within 2-second game initialization budget.

## Dependencies and Constraints

### Dependencies
- **Existing**: `order_index` field on `deck_cards` table (already present)
- **Existing**: Randomization in `create_deck_for_session/1` (already implemented)
- **No new dependencies**: Uses standard library `Enum.sort_by/2`

### Constraints
- **Database schema**: No changes required
- **API contracts**: No changes (internal implementation detail)
- **Backwards compatibility**: Existing games in "live" status unaffected (only applies to new game starts)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `order_index` NULL values | Low (DB constraint exists) | High (crash) | Validate in test; add default value if needed |
| Duplicate `order_index` values | Very Low (unique constraint) | Medium (unpredictable order) | Test with constraint validation |
| Performance degradation | Very Low (sub-ms overhead) | Low | Load test with 100+ concurrent games |
| Breaking existing games | None (only affects new starts) | N/A | N/A |

## Conclusion

**Recommendation**: Proceed with sorting by `order_index` in `deal_cards/2`.

**Justification**:
1. ✅ Minimal code change (1-2 lines)
2. ✅ Uses existing, already-randomized `order_index` field
3. ✅ Maintains deterministic replay capability
4. ✅ Negligible performance impact
5. ✅ No breaking changes
6. ✅ Aligns with Elixir/Phoenix best practices
7. ✅ Passes all constitution gates

**Next Phase**: Generate data model documentation and proceed to task breakdown.
