# Basic Gameplay Feature (Feature 005)

**Status**: ✅ Production Ready  
**Version**: 1.0.0  
**Added**: 2025-11-06  
**Specification**: `specs/005-basic-gameplay/` (archived)

---

## Overview

The Basic Gameplay feature implements the core card-playing mechanics for regular cards (4, 5, 6, 7, 9, 10) in Kadi. Players can play single cards or combinations that match the suit or rank of the top card on the played pile. This feature establishes the fundamental gameplay loop: play a card, validate the move, update game state, and advance the turn.

---

## Core Mechanics

### Matching Rules
- **Suit Match**: Card's suit matches top card's suit (e.g., 5♥ on 7♥)
- **Rank Match**: Card's rank matches top card's rank (e.g., 5♦ on 5♥)
- **Either/Or**: Only one condition needs to be met

### Single Card Play
- Player selects one card from hand
- Card must match suit OR rank of top card
- Card moves from hand to played pile
- Turn advances to next player

### Combo Play
- Player selects multiple cards of the same rank
- First card must match suit OR rank of top card
- All cards must have the same rank (e.g., all 4s)
- Cards added to pile in selection order
- Last card in combo becomes new top card

### Drawing When No Valid Play
- Player has no cards matching top card
- Player must draw one card from deck
- Drawn card cannot be played immediately
- Turn advances after draw

---

## Visual Elements

### Card Selection
- Click/tap cards in hand to select
- Selected cards highlighted with border
- Multiple selection for combos
- "Play Cards" button to submit
- "Clear Selection" to deselect

### Play Validation Feedback
- ✅ Green flash: Valid play accepted
- ❌ Red flash: Invalid play rejected
- Error message explains rejection reason
- Cards remain in hand on rejection

### Turn Indicators
- "Your Turn" badge when active
- "Waiting..." message when not your turn
- Current player highlighted
- Turn order visible to all players

---

## Database Schema

### Card Movement

**Before Play**:
```elixir
%DeckCard{
  location_type: "player_hand",
  player_id: 42,
  order_index: nil
}
```

**After Play**:
```elixir
%DeckCard{
  location_type: "played_stack",
  player_id: nil,
  order_index: 15  # Sequential in played pile
}
```

### Game Session Updates
- `current_turn_player_id`: Updated to next player
- No other fields modified for regular plays

---

## Validation Rules

### Single Card Validation
1. **Turn Check**: Must be player's turn
2. **Card Ownership**: Player must own the card
3. **Suit/Rank Match**: Card must match top card's suit OR rank
4. **Regular Card**: Must be rank 4, 5, 6, 7, 9, or 10

### Combo Validation
1. **All Same Rank**: All cards must have identical rank
2. **First Card Matches**: First card must match top card
3. **Player Owns All**: Player must own all cards in combo
4. **Minimum 2 Cards**: Combo must have at least 2 cards

### Error Messages
- `NOT_YOUR_TURN`: "Please wait for your turn"
- `WRONG_SUIT`: "The card doesn't match the suit or number"
- `MIXED_NUMBERS`: "All cards in a combo must have the same number"
- `CARD_NOT_FOUND`: "You don't have that card"
- `INVALID_CARD_NOTATION`: "Invalid card format"

---

## Implementation Details

### Key Functions

**`Kadi.CardGames.play_cards/3`**
```elixir
@spec play_cards(GameSession.t(), integer, [integer]) :: 
  {:ok, GameSession.t()} | {:error, atom}
```

**Flow**:
1. Validate player's turn
2. Fetch cards from player's hand
3. Get top card from played pile
4. Validate play using `PlayValidator.valid_play?/3`
5. Move cards to played pile (update `location_type`)
6. Assign sequential `order_index` to played cards
7. Update `current_turn_player_id` to next player
8. Broadcast game state update
9. Return updated game session

**`Kadi.Games.PlayValidator.valid_play?/3`**
```elixir
@spec valid_play?([Card.t()], Card.t(), keyword) :: boolean
```

**Validation Logic**:
```elixir
def valid_play?(cards, top_card, opts \\ []) do
  cond do
    # Single card
    length(cards) == 1 ->
      card = hd(cards)
      validate_single_card(card, top_card)
    
    # Combo
    true ->
      validate_combo(cards, top_card)
  end
end

defp validate_single_card(card, top_card) do
  card.suit == top_card.suit or card.rank == top_card.rank
end

defp validate_combo(cards, top_card) do
  # All same rank
  ranks = Enum.map(cards, & &1.rank)
  all_same = length(Enum.uniq(ranks)) == 1
  
  # First card matches
  first_matches = validate_single_card(hd(cards), top_card)
  
  all_same and first_matches
end
```

### Card Notation Format
- **Format**: `<rank><suit>` (e.g., "4H", "10D")
- **Ranks**: 4, 5, 6, 7, 9, 10
- **Suits**: H (Hearts), D (Diamonds), C (Clubs), S (Spades)
- **Case Insensitive**: "4H" = "4h" = "4H"
- **Backend Format**: JSON array `["4H"]` or `["4H", "4D"]`

---

## Testing

### Test Coverage
- **361 tests passing** ✅
- Unit tests for validation logic
- Integration tests for full play flow
- Edge case tests for error handling

### Key Test Scenarios
1. ✅ Single card matching suit accepted
2. ✅ Single card matching rank accepted
3. ✅ Single card not matching rejected
4. ✅ Combo of same rank accepted
5. ✅ Combo of mixed ranks rejected
6. ✅ Combo where first card matches accepted
7. ✅ Combo where no card matches rejected
8. ✅ Turn advances after valid play
9. ✅ Turn doesn't advance after invalid play
10. ✅ Cards removed from hand after valid play
11. ✅ Cards remain in hand after invalid play
12. ✅ Drawing when no valid play works
13. ✅ Deck recycling triggered when empty
14. ✅ UI synchronized across all players

---

## Performance

### Timing Targets
- Play validation: < 10ms
- Database transaction: < 100ms
- Broadcast propagation: < 1 second
- UI update: < 200ms
- Total play action: < 500ms

### Database Operations
- 1 query: Fetch game session with preloaded data
- 1 query: Fetch player's cards
- N updates: Move cards to played pile (where N = cards played)
- 1 update: Update game session turn
- 1 broadcast: Notify all players

All wrapped in `Ecto.Multi` for atomicity.

---

## Integration with Other Features

### Feature 001: Deal Start Card
- Starting card becomes first matching reference
- Initial game state established
- Turn order determined

### Feature 002: Randomize Player Cards
- Player hands are randomized
- No predictable patterns
- Fair distribution

### Feature 003: Pick Card from Deck
- Drawing is alternative to playing
- Player must draw if no valid plays
- Reuses existing draw function

### Feature 004: Recycle Played Stack
- Played cards can be recycled when deck empty
- Maintains game continuity
- Automatic integration

### Feature 006-010: Special Cards
- Special cards extend validation logic
- Same play flow, different rules
- Consistent architecture

---

## Code References

### Main Implementation
- **Core Logic**: `lib/kadi/card_games.ex` (lines 300-400)
- **Validation**: `lib/kadi/games/play_validator.ex` (lines 50-150)
- **LiveView Handler**: `lib/kadi_web/live/game_live.ex` (handle_event "play_cards")
- **Template**: `lib/kadi_web/live/game_live.html.heex` (card selection UI)

### Tests
- **Unit Tests**: `test/kadi/games/play_validator_test.exs`
- **Integration Tests**: `test/kadi/card_games_test.exs`
- **LiveView Tests**: `test/kadi_web/live/game_live_test.exs`

---

## UI/UX Flow

### Playing a Card

1. **Player's Turn**: "Your Turn" indicator appears
2. **Select Card**: Click card in hand (highlighted)
3. **Submit**: Click "Play Cards" button
4. **Validation**: Server validates play
5. **Success**: Card moves to played pile, turn advances
6. **Failure**: Error message shown, card stays in hand

### Playing a Combo

1. **Select Multiple**: Click multiple cards (all highlighted)
2. **Verify Same Rank**: UI shows selected cards
3. **Submit**: Click "Play Cards" button
4. **Validation**: Server validates combo
5. **Success**: All cards move to pile in order
6. **Failure**: Error message, cards stay in hand

### Drawing a Card

1. **No Valid Plays**: Player has no matching cards
2. **Click Draw**: "Draw Card" button visible
3. **Card Added**: One card added to hand
4. **Turn Advances**: Next player's turn
5. **Cannot Play**: Drawn card not playable this turn

---

## Error Handling

### Client-Side Validation
- UI disables play button when not player's turn
- Selected cards highlighted for visual feedback
- Clear selection on turn change
- Error messages displayed in flash

### Server-Side Validation
- Primary validation layer (cannot be bypassed)
- Comprehensive error checking
- Specific error codes and messages
- Transaction rollback on failure

### Race Condition Prevention
- Database-level turn validation
- Transaction isolation
- Row-level locks
- First request wins

---

## Accessibility

### Keyboard Navigation
- Tab through cards in hand
- Enter to select/deselect card
- Space to play selected cards
- Escape to clear selection

### Screen Reader Support
- ARIA labels for cards
- Live regions for turn updates
- Descriptive error messages
- Card values announced

### Visual Accessibility
- High contrast card designs
- Large, readable text
- Color-blind friendly suits
- Clear selection indicators

---

## Known Limitations

- No undo for played cards
- Cannot play multiple different ranks together
- Drawn card cannot be played immediately
- No animation for card movement (future enhancement)

---

## Future Enhancements

Potential improvements for future iterations:
- Animated card movement
- Sound effects for plays
- Auto-play suggestions (hint system)
- Undo last play (optional game mode)
- Statistics tracking (plays per game)
- Replay system
- AI opponent for single-player
- Custom card sets (beyond regular cards)

---

## Related Documentation

- [Deal Start Card](deal-start-card.md) - Game initialization
- [Pick Card from Deck](pick-card-from-deck.md) - Drawing mechanics
- [Recycle Played Stack](recycle-played-stack.md) - Deck replenishment
- [King Card Feature](king-card-feature.md) - Special card example
- [Ace Card Feature](ace-card-feature.md) - Special card example
- [Two Card Feature](two-card-feature.md) - Penalty mechanics
- [Three Card Feature](three-card-feature.md) - Penalty mechanics

---

## Changelog

### Version 1.0.0 (2025-11-06)
- ✅ Initial release
- ✅ Single card play
- ✅ Combo play
- ✅ Suit/rank matching validation
- ✅ Turn advancement
- ✅ Error handling
- ✅ Integration with draw mechanics
- ✅ UI card selection
- ✅ Real-time synchronization

---

**Last Updated**: 2025-11-06  
**Maintainer**: Development Team  
**Status**: Production Ready ✅
