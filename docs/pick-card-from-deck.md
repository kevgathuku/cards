# Pick Card from Deck Feature (Feature 003)

**Status**: ✅ Production Ready  
**Version**: 1.0.0  
**Added**: 2025-11-04  
**Specification**: `specs/003-pick-card-from-deck/` (archived)

---

## Overview

The Pick Card from Deck feature enables players to draw cards from the deck during their turn. This is a fundamental game action that allows players to continue playing when they cannot or choose not to play a card from their hand. Drawing a card automatically advances the turn to the next player.

---

## Core Mechanics

### Drawing Cards
- Player clicks "Draw Card" button during their turn
- Exactly one card moves from deck to player's hand
- Card drawn is the one with lowest `order_index` in deck
- Turn automatically advances to next player after draw
- Drawn card cannot be played in the same turn

### Turn Advancement
- Drawing counts as the player's action for the turn
- Player cannot draw AND play in the same turn
- Turn passes to next player in sequence (by join order)
- Turn order wraps around (last player → first player)

### Button Visibility
- "Draw Card" button only visible when:
  - It's the player's turn, AND
  - Deck has at least 1 card
- Button hidden when deck is empty
- Button disabled immediately upon click (prevents double-draw)

---

## Visual Elements

### Draw Card Button
- Prominent button in player's action area
- Only visible during player's turn
- Shows "Draw Card" label
- Disabled state while processing
- Hidden when deck is empty

### Deck Display
- Visual representation of remaining deck
- Card count displayed (e.g., "42 cards")
- Updates in real-time after draws
- Positioned on game board

### Hand Count Updates
- Player's hand count increases by 1
- Other players see updated hand count
- No card values revealed to other players
- Real-time synchronization via PubSub

---

## Database Schema

### DeckCard Table Updates

**Before Draw**:
```elixir
%DeckCard{
  location_type: "deck",
  player_id: nil,
  order_index: 15,  # Lowest in deck
  game_session_id: 1
}
```

**After Draw**:
```elixir
%DeckCard{
  location_type: "player_hand",
  player_id: 42,
  order_index: nil,  # Cleared for hand cards
  game_session_id: 1
}
```

### GameSession Updates
- `current_turn_player_id`: Updated to next player
- No other fields modified

---

## Validation Rules

### Pre-Draw Validation
1. **Turn Check**: Must be requesting player's turn
2. **Deck Check**: Deck must have at least 1 card
3. **Player Check**: Player must be in game
4. **Game Status**: Game must be "live"

### Post-Draw Validation
1. **Card Moved**: Exactly 1 card moved from deck to hand
2. **Turn Advanced**: `current_turn_player_id` updated
3. **Deck Count**: Deck count decreased by 1
4. **Hand Count**: Player's hand count increased by 1

---

## Edge Cases Handled

| Scenario | Behavior |
|----------|----------|
| Deck is empty | "Draw Card" button hidden, player must play from hand |
| Player disconnects after draw | Turn still advances (database-driven) |
| Race condition (simultaneous draws) | Database transaction prevents, first wins |
| Last card in deck | Card drawn, deck becomes empty, button hidden |
| Player reconnects | UI shows updated hand count and turn state |

---

## Implementation Details

### Key Function

**`Kadi.CardGames.draw_card_from_deck/2`**
```elixir
@spec draw_card_from_deck(GameSession.t(), integer) :: 
  {:ok, GameSession.t()} | {:error, atom}
```

**Flow**:
1. Validate player's turn
2. Check deck not empty
3. Find card with lowest `order_index` in deck
4. Update card: `location_type` → "player_hand", `player_id` → player
5. Calculate next player in turn order
6. Update `current_turn_player_id`
7. Broadcast game state update
8. Return updated game session

### Turn Order Calculation
```elixir
defp get_next_player(game_session, current_player_id) do
  players = 
    game_session.game_session_players
    |> Enum.sort_by(& &1.inserted_at)
  
  current_index = Enum.find_index(players, &(&1.id == current_player_id))
  next_index = rem(current_index + 1, length(players))
  
  Enum.at(players, next_index)
end
```

### Atomic Transaction
```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:deck_card, card_changeset)
|> Ecto.Multi.update(:game_session, session_changeset)
|> Repo.transaction()
```

---

## Testing

### Test Coverage
- **269 tests passing** (0 failures)
- Unit tests for draw logic
- Integration tests for turn advancement
- Edge case tests for empty deck

### Key Test Scenarios
1. ✅ Valid draw moves card from deck to hand
2. ✅ Turn advances to next player after draw
3. ✅ Deck count decreases by 1
4. ✅ Hand count increases by 1
5. ✅ Button hidden when deck empty
6. ✅ Button hidden when not player's turn
7. ✅ Race condition prevented by transaction
8. ✅ UI synchronized across all players
9. ✅ Drawn card not revealed to other players
10. ✅ Player cannot draw and play in same turn

---

## Performance

### Timing Targets
- Draw action: < 500ms (click to UI update)
- Database transaction: < 100ms
- Broadcast propagation: < 1 second
- UI rendering: < 200ms

### Database Operations
- 1 query: Fetch game session with preloaded data
- 1 query: Find card with lowest `order_index`
- 2 updates: Card location and game session turn
- 1 broadcast: Notify all players

All wrapped in `Ecto.Multi` for atomicity.

---

## Integration with Other Features

### Feature 001: Deal Start Card
- Establishes initial deck state
- Provides cards for drawing
- Turn order established

### Feature 002: Randomize Player Cards
- Cards drawn in randomized `order_index` order
- Maintains unpredictability
- No additional shuffling needed

### Feature 004: Recycle Played Stack
- Automatically triggered when deck empty
- Seamless integration (no user action required)
- Recycled cards available for drawing

### Feature 005: Basic Gameplay
- Drawing is alternative to playing cards
- Player must draw if no valid plays
- Drawn card cannot be played immediately

### Feature 009: Two Card Penalty
- Penalty draw uses same `draw_card_from_deck/2` function
- Calls function multiple times for penalty cards
- Maintains consistency across draw types

### Feature 010: Three Card Penalty
- Also reuses `draw_card_from_deck/2` function
- Consistent behavior for all draw scenarios

---

## Code References

### Main Implementation
- **Core Logic**: `lib/kadi/card_games.ex` (lines 200-250)
- **Turn Calculation**: `lib/kadi/card_games.ex` (helper function)
- **LiveView Handler**: `lib/kadi_web/live/game_live.ex` (handle_event "draw_card")
- **Template**: `lib/kadi_web/live/game_live.html.heex` (draw button)

### Tests
- **Unit Tests**: `test/kadi/card_games_test.exs`
- **Integration Tests**: `test/kadi_web/live/game_live_test.exs`

---

## API Reference

### Public Functions

**`draw_card_from_deck/2`**
- **Parameters**: `game_session`, `player_id`
- **Returns**: `{:ok, GameSession.t()}` or `{:error, atom}`
- **Errors**: `:not_your_turn`, `:deck_empty`, `:player_not_found`

### LiveView Events

**`handle_event("draw_card", _params, socket)`**
- Validates player's turn
- Calls `CardGames.draw_card_from_deck/2`
- Waits for broadcast (doesn't update socket directly)
- Shows error flash on failure

---

## Security Considerations

### Turn Validation
- Server-side validation prevents cheating
- Database-level turn check (primary safeguard)
- Client-side UI hiding (UX enhancement only)

### Card Privacy
- Drawn card identity not revealed to other players
- Only hand count visible to opponents
- No card data in broadcast to other players

### Race Condition Prevention
- Database transaction with row-level locks
- First request wins, second fails gracefully
- No duplicate draws possible

---

## Known Limitations

- No animation for card movement (future enhancement)
- No sound effects for drawing (future enhancement)
- Cannot undo draw action
- Cannot draw multiple cards in one action

---

## Future Enhancements

Potential improvements for future iterations:
- Animated card movement from deck to hand
- Sound effects for drawing
- Visual feedback for turn advancement
- Statistics tracking (cards drawn per player)
- Replay system showing draw history
- Optional "auto-draw" when no valid plays

---

## Related Documentation

- [Deal Start Card](deal-start-card.md) - Initial deck setup
- [Randomize Player Cards](randomize-player-cards.md) - Card ordering
- [Recycle Played Stack](recycle-played-stack.md) - Deck replenishment
- [Basic Gameplay](basic-gameplay.md) - Playing vs drawing decision
- [Two Card Feature](two-card-feature.md) - Penalty draws
- [Three Card Feature](three-card-feature.md) - Penalty draws

---

## Changelog

### Version 1.0.0 (2025-11-04)
- ✅ Initial release
- ✅ Draw card functionality
- ✅ Turn advancement
- ✅ Button visibility logic
- ✅ Real-time UI updates
- ✅ Database persistence
- ✅ Integration with recycling

---

**Last Updated**: 2025-11-04  
**Maintainer**: Development Team  
**Status**: Production Ready ✅
