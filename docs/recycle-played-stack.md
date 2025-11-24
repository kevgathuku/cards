# Recycle Played Stack Feature (Feature 004)

**Status**: ✅ Production Ready  
**Version**: 1.0.0  
**Added**: 2025-11-05  
**Specification**: `specs/004-recycle-played-stack/` (archived)

---

## Overview

The Recycle Played Stack feature automatically rebuilds the deck when it runs out of cards. When a player tries to draw from an empty deck, the system takes all cards from the played pile (except the topmost card), shuffles them, and creates a new deck. This ensures games can continue indefinitely without running out of cards.

---

## Core Mechanics

### Automatic Triggering
- Triggered automatically when deck is empty and player draws
- No manual user action required
- Seamlessly integrated into draw flow
- Transparent to players (happens behind the scenes)

### Recycling Process
1. **Identify Cards**: Find all cards in played_stack except topmost
2. **Shuffle**: Randomize card order using `Enum.shuffle/1`
3. **Assign Indices**: Give new sequential `order_index` values (1..N)
4. **Move Cards**: Change `location_type` from "played_stack" to "deck"
5. **Clear Ownership**: Set `player_id` to nil for all recycled cards
6. **Keep Top Card**: Topmost card remains visible on played pile

### Topmost Card Identification
- Card with highest `order_index` in played_stack
- Remains in played_stack as reference for next play
- Maintains game continuity (players know what to match)

---

## Visual Elements

### Deck Replenishment
- Deck count updates from 0 to N (number of recycled cards)
- No special animation or notification (seamless)
- Played pile shows only topmost card after recycle
- Players see updated deck count immediately

### Played Pile
- Topmost card remains visible
- Other played cards "disappear" into deck
- Visual continuity maintained
- No disruption to gameplay

---

## Database Schema

### Before Recycling

**Deck**: Empty (0 cards)
```elixir
# No cards with location_type = "deck"
```

**Played Stack**: Multiple cards
```elixir
[
  %DeckCard{location_type: "played_stack", order_index: 1},  # First played
  %DeckCard{location_type: "played_stack", order_index: 2},
  %DeckCard{location_type: "played_stack", order_index: 3},
  %DeckCard{location_type: "played_stack", order_index: 4}   # Topmost (kept)
]
```

### After Recycling

**Deck**: Replenished with shuffled cards
```elixir
[
  %DeckCard{location_type: "deck", order_index: 1, player_id: nil},
  %DeckCard{location_type: "deck", order_index: 2, player_id: nil},
  %DeckCard{location_type: "deck", order_index: 3, player_id: nil}
]
```

**Played Stack**: Only topmost card
```elixir
[
  %DeckCard{location_type: "played_stack", order_index: 4}  # Unchanged
]
```

---

## Implementation Details

### Key Function

**`Kadi.CardGames.recycle_played_stack/1`**
```elixir
@spec recycle_played_stack(GameSession.t()) :: 
  {:ok, GameSession.t()} | {:error, atom}
```

**Algorithm**:
```elixir
def recycle_played_stack(game_session) do
  played_cards = get_played_stack_cards(game_session)
  
  case played_cards do
    [] -> {:error, :no_cards_in_played_stack}
    [_only_one] -> {:error, :insufficient_cards_to_recycle}
    cards ->
      # Find topmost card (highest order_index)
      topmost = Enum.max_by(cards, & &1.order_index)
      
      # Get cards to recycle (all except topmost)
      recyclable = Enum.reject(cards, &(&1.id == topmost.id))
      
      # Shuffle and assign new indices
      shuffled_indices = Enum.shuffle(1..length(recyclable))
      
      # Update cards in transaction
      Ecto.Multi.new()
      |> update_cards_to_deck(recyclable, shuffled_indices)
      |> Repo.transaction()
  end
end
```

### Integration with Draw Flow

```elixir
def draw_card_from_deck(game_session, player_id) do
  deck_cards = get_deck_cards(game_session)
  
  case deck_cards do
    [] ->
      # Deck empty - trigger recycle
      case recycle_played_stack(game_session) do
        {:ok, recycled_session} ->
          # Retry draw with new deck
          draw_card_from_deck(recycled_session, player_id)
        {:error, reason} ->
          {:error, reason}
      end
    
    [card | _] ->
      # Normal draw logic
      execute_draw(game_session, card, player_id)
  end
end
```

### Atomic Transaction
```elixir
Ecto.Multi.new()
|> Ecto.Multi.update_all(:recycle_cards, query, [
  set: [
    location_type: "deck",
    player_id: nil,
    order_index: fragment("...")
  ]
])
|> Repo.transaction()
```

---

## Validation Rules

### Pre-Recycle Validation
1. **Minimum Cards**: Played stack must have at least 2 cards
   - 1 card to recycle
   - 1 topmost card to keep
2. **Deck Empty**: Deck must be empty (0 cards)
3. **Game Active**: Game must be in "live" status

### Post-Recycle Validation
1. **Deck Replenished**: Deck has N-1 cards (where N = played stack size)
2. **Top Card Kept**: 1 card remains in played_stack
3. **Indices Assigned**: All recycled cards have new `order_index` (1..N-1)
4. **Ownership Cleared**: All recycled cards have `player_id` = nil

---

## Edge Cases Handled

| Scenario | Behavior |
|----------|----------|
| Played stack empty | Return `{:error, :no_cards_in_played_stack}` |
| Only 1 card in played stack | Return `{:error, :insufficient_cards_to_recycle}` |
| Deck still empty after recycle | Should never occur (guard clause checks) |
| Multiple players drawing simultaneously | Transaction prevents race conditions |
| Player disconnects during recycle | Transaction ensures atomicity |

---

## Error Handling

### Error Types

**`:no_cards_in_played_stack`**
- Played stack is completely empty
- Should never occur in normal gameplay
- Indicates game state corruption

**`:insufficient_cards_to_recycle`**
- Only 1 card in played stack (the topmost)
- Cannot recycle (need minimum 2 cards)
- Player cannot draw, turn skipped

**Transaction Errors**
- Database operation failures
- Rare, indicates system issues
- Transaction rollback ensures consistency

### Error Propagation
```elixir
# Errors bubble up to draw_card_from_deck/2
case recycle_played_stack(game_session) do
  {:ok, recycled} -> draw_card_from_deck(recycled, player_id)
  {:error, :insufficient_cards_to_recycle} ->
    # Log anomaly, skip player's turn
    Logger.warning("Cannot recycle: insufficient cards")
    {:error, :deck_exhaustion}
end
```

---

## Testing

### Test Coverage
- **9/9 unit tests passing** ✅
- **3/3 integration tests passing** ✅
- 100% pass rate

### Key Test Scenarios
1. ✅ Successfully recycles cards from played stack
2. ✅ Keeps topmost card (highest order_index) in played stack
3. ✅ Assigns sequential shuffled indices to recycled cards
4. ✅ Returns error when played stack is empty
5. ✅ Returns error when only 1 card in played stack
6. ✅ Clears player_id on recycled cards
7. ✅ Drawing from empty deck triggers recycle and succeeds
8. ✅ Returns error when cannot recycle (only 1 card)
9. ✅ Topmost card remains visible after recycle

---

## Performance

### Timing Targets
- Typical recycle (40-50 cards): < 100ms
- Full 51-card recycle: < 200ms
- Well within 1-second performance target

### Database Operations
- 1 query: Fetch played stack cards
- N updates: Move cards to deck (where N = recyclable cards)
- 1 query: Reload game session
- **Total**: ~2 queries + N updates

### Memory Usage
- Minimal: Single array for shuffling
- No additional data structures
- Garbage collected after recycle

---

## Integration with Other Features

### Feature 002: Randomize Player Cards
- Uses same shuffling algorithm (`Enum.shuffle/1`)
- Maintains randomization quality
- Consistent behavior across features

### Feature 003: Pick Card from Deck
- Automatically triggered by draw function
- Seamless integration (no code duplication)
- Single broadcast after complete flow

### Feature 005: Basic Gameplay
- Ensures game never stalls due to empty deck
- Players can always draw when needed
- Maintains gameplay continuity

### Feature 009: Two Card Penalty
- Penalty draws trigger recycling if needed
- Multiple draws handled correctly
- Consistent behavior

### Feature 010: Three Card Penalty
- Same recycling behavior for 3-card penalties
- Handles larger draw amounts
- No special cases needed

---

## Code References

### Main Implementation
- **Core Logic**: `lib/kadi/card_games.ex` (lines 250-300)
- **Integration**: `lib/kadi/card_games.ex` (draw_card_from_deck/2)
- **Helper Functions**: `lib/kadi/card_games.ex` (private functions)

### Tests
- **Unit Tests**: `test/kadi/card_games_test.exs` (recycle_played_stack/1 describe block)
- **Integration Tests**: `test/kadi/card_games_test.exs` (draw with recycle describe block)

---

## Algorithm Analysis

### Shuffle Algorithm
- **Method**: Fisher-Yates shuffle (via `Enum.shuffle/1`)
- **Time Complexity**: O(n) where n = recyclable cards
- **Space Complexity**: O(n)
- **Randomness**: Pseudo-random, sufficient for card games

### Order Index Assignment
- **Method**: Sequential indices in shuffled order
- **Example**: 4 cards → indices [3, 1, 4, 2] (shuffled 1..4)
- **Properties**: Unique, sequential, randomized

---

## Security Considerations

### Randomness Quality
- Uses Erlang's `:rand` module
- Sufficient for game fairness
- Not cryptographically secure (not required)

### Concurrency Safety
- Protected by turn validation
- Database transaction prevents race conditions
- Row-level locks ensure atomicity

### Card Privacy
- Recycled cards have no player association
- No information leakage about previous owners
- Fair redistribution

---

## Known Limitations

- No visual feedback for recycling (happens silently)
- Cannot manually trigger recycle
- Minimum 2 cards required in played stack
- No animation for card movement

---

## Future Enhancements

Potential improvements for future iterations:
- Visual notification when recycling occurs
- Animation showing cards moving from pile to deck
- Sound effect for recycling
- Statistics tracking (recycles per game)
- Optional "shuffle" button for manual recycle
- Configurable minimum cards for recycle

---

## Debugging & Troubleshooting

### Common Issues

**Issue**: "Insufficient cards to recycle" error
- **Cause**: Only 1 card in played stack
- **Solution**: Game should end or handle gracefully

**Issue**: Deck still empty after recycle
- **Cause**: Logic error (should never occur)
- **Solution**: Check guard clauses and validation

**Issue**: Topmost card changed after recycle
- **Cause**: Incorrect topmost identification
- **Solution**: Verify `max_by` logic on `order_index`

### Diagnostic Queries

```elixir
# Check played stack state
DeckCard
|> where([dc], dc.game_session_id == ^game_id)
|> where([dc], dc.location_type == "played_stack")
|> order_by([dc], asc: dc.order_index)
|> Repo.all()

# Check deck state after recycle
DeckCard
|> where([dc], dc.game_session_id == ^game_id)
|> where([dc], dc.location_type == "deck")
|> select([dc], count(dc.id))
|> Repo.one()
```

---

## Related Documentation

- [Pick Card from Deck](pick-card-from-deck.md) - Triggers recycling
- [Randomize Player Cards](randomize-player-cards.md) - Shuffling algorithm
- [Basic Gameplay](basic-gameplay.md) - Gameplay continuity
- [Two Card Feature](two-card-feature.md) - Penalty draws
- [Three Card Feature](three-card-feature.md) - Penalty draws

---

## Changelog

### Version 1.0.0 (2025-11-05)
- ✅ Initial release
- ✅ Automatic recycling on empty deck
- ✅ Topmost card preservation
- ✅ Shuffling and re-indexing
- ✅ Error handling for edge cases
- ✅ Integration with draw flow
- ✅ Comprehensive test coverage

---

**Last Updated**: 2025-11-05  
**Maintainer**: Development Team  
**Status**: Production Ready ✅
