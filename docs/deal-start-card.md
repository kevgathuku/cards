# Deal Start Card Feature (Feature 001)

**Status**: ✅ Production Ready  
**Version**: 1.0.0  
**Added**: 2025-11-03  
**Specification**: `specs/001-deal-start-card/` (archived)

---

## Overview

The Deal Start Card feature implements the initial game setup mechanics for Kadi. When a game starts, each player receives 4 cards, and a valid starting card is automatically dealt from the deck to the played pile. This feature establishes the foundation for all gameplay by creating the initial game state.

---

## Core Mechanics

### Initial Card Distribution
- Each player receives exactly 4 cards as their starting hand
- Cards are dealt from the deck in `order_index` order (randomized by Feature 002)
- Player hands are private (only visible to the owning player)
- Other players see face-down card backs with card counts

### Starting Card Selection
- One additional card is dealt from the deck to serve as the starting card
- Starting card is placed on the played pile (visible to all players)
- **Excluded Ranks**: 2, 3, Jack, Queen, Ace cannot be starting cards
- **Kings Allowed**: As of Feature 006, Kings can be starting cards (but don't trigger direction reversal)

### Special Card Handling
When a special card is encountered during starting card selection:
1. Card is moved to the bottom of the deck
2. System continues to next card in sequence (by `order_index`)
3. Process repeats until a valid starting card is found
4. No reshuffling occurs (maintains randomization from Feature 002)

### Turn Assignment
- First turn is randomly assigned to one player
- Turn order follows join sequence (`game_session_players.inserted_at`)
- Turn rotation wraps around (last player → first player)

---

## Visual Elements

### Player's Own Hand
- Cards displayed face-up with suit and rank visible
- Interactive cards (clickable for playing)
- Card count displayed
- Organized in hand view

### Other Players' Hands
- Cards displayed as face-down card backs
- Card count visible for each player
- Player name/email displayed
- No card values revealed

### Played Pile
- Starting card displayed face-up
- Positioned centrally on game board
- Most recent card always on top
- Full pile history maintained

### Deck Pile
- Visual representation of remaining deck
- Card count displayed
- Positioned on game board
- Updates in real-time as cards are drawn

---

## Database Schema

### Tables Used

**`game_sessions`**
- `status`: Changes from "lobby" to "live" on game start
- `current_turn_player_id`: Set to randomly selected player

**`deck_cards`**
- `location_type`: "deck", "player_hand", or "played_stack"
- `player_id`: Set for cards in player hands, null for deck/played
- `order_index`: Determines card order in deck and played pile

**`game_session_players`**
- `inserted_at`: Determines turn order
- Used to calculate next player in rotation

---

## Validation Rules

### Starting Card Validation
1. **Excluded Ranks**: Cannot be 2, 3, Jack, Queen, or Ace
2. **Kings Allowed**: Kings are valid starting cards (since Feature 006)
3. **Sequential Search**: If invalid card found, move to bottom and continue
4. **Minimum Requirement**: Must have at least one valid card in deck

### Game Start Validation
1. **Minimum Players**: At least 2 players required
2. **Sufficient Cards**: Deck must have (4 × players) + 1 cards minimum
3. **Lobby Status**: Game must be in "lobby" status before starting
4. **Player Ready**: All players must be in ready state

---

## Edge Cases Handled

| Scenario | Behavior |
|----------|----------|
| Multiple special cards in sequence | Move each to bottom, continue until valid card found |
| All top cards are special | System continues through entire deck if needed |
| Insufficient cards for deal | Prevented by game setup validation |
| King as starting card | Allowed, but no direction reversal triggered |
| Player disconnects during deal | Game state persists in database, player can reconnect |

---

## Implementation Details

### Key Functions

**`Kadi.CardGames.start_game/1`**
```elixir
@spec start_game(GameSession.t()) :: {:ok, GameSession.t()} | {:error, atom}
```
Orchestrates the entire game start process:
1. Validates game can start
2. Deals 4 cards to each player
3. Selects valid starting card
4. Randomly assigns first turn
5. Updates game status to "live"
6. Broadcasts game state to all players

**`select_starting_card/1`** (private)
```elixir
@spec select_starting_card([DeckCard.t()]) :: DeckCard.t()
```
Finds first valid starting card:
- Filters out ranks: 2, 3, Jack, Queen, Ace
- Returns first valid card by `order_index`
- Moves invalid cards to bottom of deck

### Turn Order Calculation
```elixir
# Players ordered by join time
players = 
  game_session.game_session_players
  |> Enum.sort_by(& &1.inserted_at)

# Random first player
first_player = Enum.random(players)
```

---

## Testing

### Test Coverage
- **Unit Tests**: Starting card selection logic
- **Integration Tests**: Full game start workflow
- **Edge Case Tests**: Special card handling, insufficient cards

### Key Test Scenarios
1. ✅ Each player receives exactly 4 cards
2. ✅ Starting card is never a special card (2,3,J,Q,A)
3. ✅ Kings are allowed as starting cards
4. ✅ Special cards moved to bottom when encountered
5. ✅ Turn randomly assigned to one player
6. ✅ Game status changes from "lobby" to "live"
7. ✅ All players see synchronized game state
8. ✅ UI renders correctly for all players

---

## Performance

### Timing Targets
- Complete game start: < 2 seconds
- Card dealing: < 500ms
- Starting card selection: < 100ms
- UI rendering: < 1 second

### Database Operations
- 1 query: Load game session with players
- N updates: Deal cards to players (where N = 4 × player count)
- 1 update: Set starting card location
- 1 update: Update game session status
- 1 broadcast: Notify all players

All operations wrapped in `Ecto.Multi` for atomicity.

---

## Integration with Other Features

### Feature 002: Randomize Player Cards
- Depends on `order_index` randomization
- Starting card selection uses randomized deck order
- No additional shuffling needed

### Feature 003: Pick Card from Deck
- Establishes initial deck state
- Remaining cards available for drawing
- Turn order established for draw mechanics

### Feature 004: Recycle Played Stack
- Creates initial played pile with starting card
- Played pile can be recycled when deck empties
- Starting card remains visible as reference

### Feature 005: Basic Gameplay
- Establishes initial game state for play validation
- Starting card becomes first matching reference
- Turn order determines play sequence

### Feature 006: King Card
- Kings allowed as starting cards (updated requirement)
- No direction reversal when King is starting card
- Direction remains default "clockwise"

---

## Code References

### Main Implementation
- **Core Logic**: `lib/kadi/card_games.ex` (lines 80-150)
- **Starting Card Selection**: `lib/kadi/card_games.ex` (private function)
- **LiveView**: `lib/kadi_web/live/lobby_live.ex` (start game button)
- **Template**: `lib/kadi_web/live/game_live.html.heex` (game board rendering)

### Tests
- **Unit Tests**: `test/kadi/card_games_test.exs`
- **Integration Tests**: `test/kadi_web/live/game_live_test.exs`

---

## UI/UX Considerations

### Visual Feedback
- Loading indicator during game start
- Smooth transition from lobby to game view
- Cards animate into position (optional enhancement)
- Clear indication of whose turn it is

### Accessibility
- Screen reader support for card values
- Keyboard navigation for card selection
- High contrast mode for card visibility
- ARIA labels for game state

---

## Known Limitations

- No animation for card dealing (future enhancement)
- No sound effects for game start (future enhancement)
- Starting card selection is deterministic (not truly random)
- Cannot undo game start once initiated

---

## Future Enhancements

Potential improvements for future iterations:
- Animated card dealing sequence
- Sound effects for game start
- Configurable starting hand size (currently fixed at 4)
- Option to exclude additional ranks from starting card
- Replay/spectator mode for game start
- Statistics tracking for starting card distribution

---

## Related Documentation

- [Randomize Player Cards](randomize-player-cards.md) - Card shuffling mechanics
- [Pick Card from Deck](pick-card-from-deck.md) - Drawing mechanics
- [Basic Gameplay](basic-gameplay.md) - Playing cards
- [King Card Feature](king-card-feature.md) - Kings as starting cards

---

## Changelog

### Version 1.0.0 (2025-11-03)
- ✅ Initial release
- ✅ Deal 4 cards to each player
- ✅ Select valid starting card
- ✅ Exclude special cards (2,3,J,Q,A)
- ✅ Random turn assignment
- ✅ UI rendering for all players
- ✅ Database persistence

### Version 1.1.0 (2025-11-08)
- ✅ Allow Kings as starting cards (Feature 006 integration)
- ✅ No direction reversal for King starting card

---

**Last Updated**: 2025-11-08  
**Maintainer**: Development Team  
**Status**: Production Ready ✅
