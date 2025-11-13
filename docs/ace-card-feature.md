# Ace Card Special Action

**Feature**: Suit selection mechanic for Ace cards  
**Status**: Implemented  
**Added**: 2025-11-13  
**Specification**: `specs/008-ace-card-feature/`

## Overview

The Ace card introduces a suit selection mechanic to the game. When a player plays an Ace, they must select which suit the next player must follow. This creates strategic gameplay opportunities and adds depth to card play decisions.

## User Stories

### US1: Core Ace Play and Suit Selection

**As a player**, I want to play an Ace card and select a suit, so that I can control what the next player must play.

**Behavior**:
- Playing an Ace pauses the game in "select_suit" state
- Player must choose one of four suits: hearts, diamonds, clubs, or spades
- Game displays suit selection buttons (UI)
- After selection, turn advances to the next player
- Selected suit is stored in `game_sessions.action_suit`

### US2: Suit Enforcement

**As a player**, I want the next player to be forced to play the requested suit or draw, so the Ace card has meaningful impact.

**Behavior**:
- Next player must play a card matching the requested suit
- If they don't have a matching card, they must draw from the deck
- **Critical**: The suit requirement persists across draws and multiple turns
- Suit requirement is only cleared when a matching card is successfully played
- Another Ace can override the current suit requirement
- UI highlights which cards are playable (matching suit or Aces)

### US3: Ace Override

**As a player**, I want to play an Ace to override an existing suit requirement, so I can change the strategic situation.

**Behavior**:
- Aces can be played regardless of any active suit requirement
- Playing an Ace clears the previous `action_suit`
- New suit selection replaces the old requirement
- Next player must follow the new suit

## Game Mechanics

### Ace Play Rules

1. **Wild Card**: Aces can be played on any card, regardless of suit or rank
2. **Action Trigger**: Playing an Ace triggers the "select_suit" game state
3. **Multiple Aces**: Playing multiple Aces together only prompts for suit selection once
4. **Turn Pause**: Turn does NOT advance when Ace is played (waits for suit selection)
5. **Starting Card**: Aces can be selected as the starting card for a new game
6. **Starting Card Exception**: When an Ace IS the starting card, no suit selection is triggered - players simply match the Ace's suit using normal matching rules

### Suit Selection Rules

1. **Valid Suits**: hearts, diamonds, clubs, spades
2. **Current Player Only**: Only the player who played the Ace can select the suit
3. **Required Action**: Suit selection is mandatory before game can continue
4. **Turn Advancement**: After suit selection, turn advances to the next player

### Suit Enforcement Rules

1. **Lead Card Matching**: For combos, only the lead card must match the requested suit
2. **Ace Exception**: Players can always play an Ace, even if it doesn't match the suit
3. **Persistence**: Suit requirement persists across:
   - Card draws
   - Multiple turns
   - Direction changes (King plays)
   - Player skips (Jack plays)
4. **Clearing**: Suit requirement is cleared only when:
   - A matching suit card is successfully played, OR
   - Another Ace is played (which sets a new requirement)

### Edge Cases

1. **Last Card**: Playing an Ace as the last card still requires suit selection
2. **Deck Exhaustion**: If deck runs out while `action_suit` is set, played stack is recycled
3. **Integration with King**: Ace after King respects counter-clockwise direction
4. **Integration with Jack**: Jack after Ace preserves `action_suit` but skips players
5. **Ace Starting Card**: When an Ace is the starting card, `action_type` and `action_suit` remain nil - no suit selection is triggered, players simply play matching cards using normal suit-matching rules

## Database Schema

### Fields Added to `game_sessions`

```elixir
action_type: :string      # "select_suit" when awaiting suit selection
action_suit: :string      # "hearts", "diamonds", "clubs", or "spades"
```

### State Transitions

```
Normal Play → Ace Played → action_type: "select_suit"
                          ↓
                   Suit Selected → action_suit: "hearts"
                                  action_type: nil
                          ↓
              Next Player Plays Matching Card → action_suit: nil
```

## Implementation Details

### Key Functions

**`Kadi.CardGames.select_suit/3`**
- Handles suit selection after Ace play
- Validates player is current turn holder
- Updates `action_suit` and advances turn
- Broadcasts game state update

**`Kadi.Games.PlayValidator.valid_ace_play?/3`**
- Validates Ace plays (must all be Aces)
- Aces bypass suit and rank matching
- Aces bypass active `action_suit` requirements

**`Kadi.CardGames.execute_play/3`**
- Detects Ace plays and sets `action_type: "select_suit"`
- Turn advancement pauses until suit is selected
- Clears `action_suit` when matching card is played

### Telemetry Events

**`[:kadi, :ace, :suit_selected]`**

Emitted when a player selects a suit after playing an Ace.

**Metadata**:
```elixir
%{
  game_session_id: integer,
  player_id: integer,
  suit: string,              # "hearts", "diamonds", "clubs", "spades"
  timestamp: DateTime.t()
}
```

## UI Elements

### Suit Selection Interface

When `action_type == "select_suit"`:
- Display message: "Select a suit:"
- Show four suit selection buttons (styled with Tailwind CSS)
- Buttons emit `select_suit` event with chosen suit
- Disabled for non-current-turn players

### Active Suit Indicator

When `action_suit` is set:
- Display purple banner showing required suit with symbol
- Highlight playable cards (matching suit) with green border
- Highlight Aces with green border (always playable)
- Show error message if invalid card played: "You must play {suit} or an Ace"

## Testing

### Test Coverage

**Unit Tests**: `test/kadi/games/play_validator_test.exs`
- Ace validation logic
- Suit matching with `action_suit`

**Integration Tests**: `test/kadi/card_games/special_cards_ace_test.exs`
- Full Ace play workflow
- Suit selection and enforcement
- Persistence across draws
- Ace override mechanics

**Edge Case Tests**: `test/kadi/card_games_test.exs`
- Ace as last card
- Multiple Aces
- Deck exhaustion scenarios
- Integration with King and Jack

**LiveView Tests**: `test/kadi_web/live/game_live_test.exs`
- Suit selection UI rendering
- Button click events
- State updates after selection

### Test Scenarios

1. ✅ Playing Ace sets `action_type: "select_suit"`
2. ✅ Turn doesn't advance until suit selected
3. ✅ Suit selection updates `action_suit` and advances turn
4. ✅ Next player can only play matching suit or Ace
5. ✅ Suit requirement persists after drawing
6. ✅ Multiple players drawing in sequence
7. ✅ Ace overrides existing `action_suit`
8. ✅ Ace as starting card allowed
9. ✅ **Ace as starting card has no suit restriction** - no `action_type` or `action_suit` set, normal matching rules apply
10. ✅ Ace as last card triggers selection
11. ✅ Multiple Aces only prompt once
12. ✅ Deck exhaustion with `action_suit` recycles correctly
13. ✅ Integration with King (direction)
14. ✅ Integration with Jack (skip)

## Manual Testing

### Verification Checklist

- [ ] Play Ace via UI, verify suit selection buttons appear
- [ ] Select suit, verify turn advances
- [ ] Next player tries to play non-matching card, verify rejection
- [ ] Next player plays matching card, verify acceptance
- [ ] Next player plays Ace, verify override works
- [ ] Trigger deck exhaustion with active `action_suit`, verify recycle
- [ ] Verify telemetry events in logs

## Related Features

- **Feature 006**: King card (direction reversal) - direction persists through Ace plays
- **Feature 007**: Jack card (player skip) - skip logic preserves `action_suit`

## Future Enhancements

Potential improvements not in current scope:

- Visual suit icons in selection buttons
- Animation for suit selection
- Sound effects for Ace plays
- AI player suit selection strategy
- Suit selection timeout (auto-select random suit)

## References

- **Specification**: `specs/008-ace-card-feature/spec.md`
- **Task List**: `specs/008-ace-card-feature/tasks.md`
- **Data Model**: `specs/008-ace-card-feature/data-model.md`
- **Migration**: `priv/repo/migrations/*_add_action_fields_to_game_sessions.exs`
