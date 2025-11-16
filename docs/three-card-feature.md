# Three Card Draw Penalty Feature (Feature 010)

**Status**: ✅ Production Ready  
**Version**: 1.0.0  
**Added**: 2025-11-16  
**Specification**: `.kiro/specs/three-card/`

---

## Overview

The Three Card feature introduces a second penalty mechanic to the Kadi card game. Playing a '3' card forces the next player to draw 3 cards unless they can block it. This feature works alongside the existing '2' card penalty system, with cross-blocking prevention to maintain balanced gameplay.

---

## Core Mechanics

### Penalty Activation
- Playing a '3' card creates a draw penalty targeting the next player
- Penalty state is stored in `game_sessions.draw_penalty` map field
- Structure: `%{active: true, penalty_type: "three", target_player_id: integer, created_by_player_id: integer}`
- Penalty persists in database until resolved (database-driven architecture)

### Penalty Blocking
Players can block an active '3' penalty by playing:
1. **Ace Card**: Completely clears the penalty and triggers suit selection (action_suit set to blocked '3' suit)
2. **Another '3' Card**: Transfers the penalty to the next player

**Cross-Blocking Prevention**: 
- '2' cards CANNOT block '3' penalties
- '3' cards CANNOT block '2' penalties
- Validation enforces penalty_type matching

### Penalty Resolution
- **Manual Draw**: Player clicks "Draw 3 Cards" button to accept penalty
- **Turn Advancement**: After penalty draw, turn advances to next player
- **No Play After Draw**: Player cannot play the drawn cards immediately
- **Deck Recycling**: If deck has insufficient cards, played pile is automatically recycled

### Special Rules
- **Starting Card**: '3' cards are excluded from starting card selection
- **Last Card**: '3' can be played as last card (player enters "cardless" status, penalty still applies to next player)
- **Non-Additive**: Playing multiple '3's in a combo does NOT stack the penalty (always 3 cards)
- **Suit/Rank Matching**: After Ace blocks a '3', next player can match either:
  - The suit of the blocked '3' (stored in `action_suit`), OR
  - Play any '3' card (rank match)

---

## User Stories

### US1: Penalty Activation (Requirements 1.1, 1.4)
**As a player**, I want to play a '3' card to force the next player to draw 3 cards, so I can gain a strategic advantage.

**Behavior**:
- Playing '3' activates penalty state with `penalty_type: "three"`
- Next player receives notification about the penalty
- Persistent penalty indicator appears showing "must draw 3 cards"
- Turn advances normally after '3' is played
- Penalty remains active until resolved

### US2: Blocking with Ace (Requirements 2.1-2.4)
**As a player**, I want to block a '3' penalty with an Ace, so I can avoid drawing cards.

**Behavior**:
- Player can play an Ace to clear the penalty
- Penalty is completely cleared (doesn't transfer)
- `action_suit` is set to the suit of the blocked '3' card
- Next player must follow the suit requirement
- Enhanced UI message: "Ace blocked penalty! Active suit: [suit] from last penalty card"
- Penalty indicator disappears from UI

### US3: Transferring with '3' (Requirements 3.1-3.3)
**As a player**, I want to play another '3' to transfer the penalty, so I can defend myself while attacking the next player.

**Behavior**:
- Player can play a '3' matching the current suit
- Penalty transfers to the next player
- `penalty_type` remains "three"
- Penalty creator updates to current player
- UI updates to show new target

### US4: Non-Additive Combos (Requirements 4.1-4.3)
**As a player**, I expect multiple '3's played together to not stack the penalty, to prevent unfair gameplay.

**Behavior**:
- Playing 2+ '3' cards in one turn only creates 3-card penalty
- Combo validation ensures all cards are rank '3'
- First '3' must match top card per normal rules
- Penalty count is always 3, regardless of combo size

### US5: Penalty Acceptance (Requirements 7.1-7.2)
**As a player with no blocking cards**, I want a clear way to accept the penalty, so I know how to proceed.

**Behavior**:
- "Draw 3 Cards" button appears when penalty active
- Button shows pulse animation to draw attention
- Clicking draws 3 cards automatically
- Penalty indicator clears after draw
- Turn advances automatically after draw
- Error shown if trying to play non-blocking cards

### US6: Cross-Blocking Prevention (Requirements 8.1-8.4)
**As a player**, I expect that '2' and '3' penalties cannot block each other, to maintain game balance.

**Behavior**:
- Playing '2' when '3' penalty is active → rejected with error
- Playing '3' when '2' penalty is active → rejected with error
- Error message: "Invalid play" or "Penalty Active"
- Penalty remains active after invalid play attempt
- Only matching penalty type or Ace can block

### US7: Edge Cases (Requirements 6.1-6.3, 9.1-9.3)
**As a player**, I expect the game to handle edge cases gracefully.

**Behavior**:
- '3' as last card: Player becomes cardless, penalty still applies
- Deck exhaustion: Played pile is recycled to draw 3 cards
- Multiple '3's: Penalty is 3, not cumulative
- Starting card: Never a '3' (excluded from selection)

---

## Visual & UX Indicators

### Penalty Button
- Dedicated "Draw 3 Cards" button appears when penalty active
- Red styling with pulse animation
- Only visible when it's the penalized player's turn
- Button text clearly indicates penalty amount (3 cards)

### Penalty Indicator Banner
- Persistent indicator at top of game board
- Shows who created the penalty (player email)
- Displays "must draw 3 cards"
- Exclamation icon emphasizes warning
- Clears after penalty is resolved

### Enhanced Ace Blocking Message
When Ace blocks a '3' penalty:
- Special message: "Ace blocked penalty!"
- Shows active suit requirement
- Displays the blocked penalty card (3 with suit symbol)
- Message: "Active suit: [Suit] from last penalty card"
- Helps players understand the suit requirement origin

### Card Highlighting
- Valid cards (matching suit or rank '3') are highlighted with green border
- Invalid cards remain unselectable during penalty
- Visual feedback helps players identify blocking options

---

## Database Touchpoints

| Table                 | Fields Impacted                          | Notes                                                |
|-----------------------|------------------------------------------|------------------------------------------------------|
| `game_sessions`       | `draw_penalty`, `current_turn_player_id`, `action_suit` | Penalty state includes `penalty_type: "three"` |
| `deck_cards`          | `location_type`, `player_id`, `order_index`| Cards move: deck → hand during penalty draw         |
| `game_session_players`| `status`                                  | Player can become "cardless" after playing '3'       |

### Penalty State Structure
```elixir
%{
  active: boolean,
  penalty_type: string,    # "two" or "three" - count derived via penalty_count/1
  target_player_id: integer,
  created_by_player_id: integer  # optional, for tracking
}
```

**Important**: The `count` field has been removed from the data structure. The penalty count is derived dynamically using the `CardGames.penalty_count/1` helper function:

```elixir
def penalty_count(penalty_type) do
  case penalty_type do
    "two" -> 2
    "three" -> 3
    _ -> 0
  end
end
```

This eliminates redundancy and ensures the count always matches the penalty_type.

### Migration
- Reused existing `draw_penalty` column (`:map` type) from Feature 009
- Added `penalty_type` field to distinguish between '2' and '3' penalties
- Removed `count` field to eliminate redundancy
- Migration script: `priv/repo/migrate_penalty_data.exs` (backfills existing penalties and removes count field)
- Backward compatible: Old code with count field still works, but new code uses penalty_type only

---

## Validation Rules

### Play Validation (`Kadi.Games.PlayValidator`)

1. **Starting Card**: '3' cards cannot be selected as starting card
2. **Suit Matching**: Blocking '3' or Ace must match active `action_suit`
3. **Rank/Suit Choice**: After Ace blocks '3', next player can play:
   - Any card matching the suit, OR
   - Any '3' card (rank match)
4. **Combo Validation**: Multiple '3's must all be rank "3"
5. **Non-Additive**: Penalty count stays at 3 regardless of combo size
6. **Cross-Blocking**: '2' cannot block '3', '3' cannot block '2'

### Enforcement

```elixir
# Cross-blocking prevention
def valid_play?(cards, top_card, opts) do
  penalty_active? = Keyword.get(opts, :penalty_active?, false)
  penalty_type = Keyword.get(opts, :penalty_type)
  
  if penalty_active? do
    case penalty_type do
      "three" ->
        # Only '3' or Ace can block
        all_threes?(cards) or all_aces?(cards)
      "two" ->
        # Only '2' or Ace can block
        all_twos?(cards) or all_aces?(cards)
    end
  else
    # Normal validation
  end
end
```

---

## Edge Cases Covered

| Scenario                                 | Behaviour                                                     |
|------------------------------------------|----------------------------------------------------------------|
| '3' as last card                        | Player enters "cardless" status, penalty applies to next      |
| Multiple '3's in combo                  | Penalty is 3 cards (non-additive), not 6 or 9                |
| Ace blocks then '3' played              | Next player can match suit OR play any '3' (rank)            |
| Deck exhaustion during penalty draw     | Played pile is recycled, draw continues normally              |
| Penalty + no cards to recycle           | Anomaly logged, player skipped with toast notification        |
| Playing '3' after King                  | Penalty applies in counter-clockwise direction                |
| Playing '3' after Jack                  | Penalty applies after skip calculation                        |
| Multi-player penalty chains             | '3' → '3' → '3' transfers through multiple players            |
| '2' tries to block '3'                  | Rejected with error, penalty remains active                   |
| '3' tries to block '2'                  | Rejected with error, penalty remains active                   |
| Starting card selection                 | '3' excluded (verified across multiple games)                 |

---

## Architecture Patterns

### Database-Driven State
- All penalty state stored in PostgreSQL, not in-memory
- `draw_penalty` map field is source of truth
- `penalty_type` field distinguishes between '2' and '3' penalties
- No GenServer state for penalty tracking
- State persists across LiveView reconnects

### Penalty Type System
```elixir
# Helper function to get penalty count
def penalty_count(%{draw_penalty: %{"penalty_type" => "three"}}), do: 3
def penalty_count(%{draw_penalty: %{"penalty_type" => "two"}}), do: 2
def penalty_count(_), do: 0
```

### Atomic Transactions
```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:deck_cards, move_cards_changeset)
|> Ecto.Multi.update(:game_session, penalty_changeset)
|> Repo.transaction()
```

### PubSub Broadcasting
- `broadcast_game_update/1` sends updated game state to all players
- Broadcasts after every state change (penalty activation, blocking, draw)
- LiveView clients receive updates via `handle_info/2`
- Real-time synchronization across devices

---

## Testing

### Automated Coverage
- Total Tests: 403 (all passing) ✅
- Feature Tests: 15+ comprehensive tests in `special_cards_three_test.exs` ✅
- End-to-End Tests: 5 comprehensive E2E tests in `game_live_test.exs` ✅
- Coverage Areas:
  - Penalty activation and transfer scenarios
  - Blocking with Ace and '3' cards
  - Cross-blocking prevention ('2' vs '3')
  - Suit/rank matching after Ace blocks
  - Multi-player penalty chains
  - Edge cases (last card, combo plays, deck exhaustion, starting card)

### Key Test Suites

#### `test/kadi/card_games/special_cards_three_test.exs`
- Penalty activation when '3' is played
- Blocking penalty with Ace
- Blocking and transferring with another '3'
- Cross-blocking prevention ('2' cannot block '3', vice versa)
- Multiple '3's non-additive behavior
- '3' as last card (cardless state)
- `process_draw_penalty/2` with penalty_type='three'

#### `test/kadi/games/play_validator_test.exs`
- '3' card validation (no penalty)
- '3' card blocking when penalty active
- Cross-blocking prevention in validator
- '3' card with action_suit enforcement

#### `test/kadi_web/live/game_live_test.exs` (End-to-End)
- **E2E Test 1**: Complete 3 card penalty flow (play → see button → draw 3)
- **E2E Test 2**: 3 card blocking with another 3 (A → B → C transfer)
- **E2E Test 3**: 3 card blocking with Ace (penalty clears, suit requirement)
- **E2E Test 4**: Cross-blocking prevention (2 vs 3 rejection)
- **E2E Test 5**: Edge cases (last card, recycling, multiple 3s, starting card)

### Test Results
```
Finished in 21.7 seconds (13.9s async, 7.7s sync)
24 doctests, 403 tests, 0 failures
```

---

## Performance Notes

- Penalty check at turn start: O(1) map lookup
- `penalty_count/1` helper: O(1) pattern matching
- All operations use `Ecto.Multi` for atomic writes
- Fresh DB queries before broadcasts ensure data consistency
- No N+1 query issues introduced
- Minimal database overhead (reuses existing map field)

---

## Integration with Existing Features

### Ace Card (Feature 008)
- Ace can block both '2' and '3' penalties
- After blocking '3', `action_suit` is set to the blocked '3' suit
- Enhanced UI message shows penalty blocking context
- Suit requirement persists until matched

### King Card (Feature 006)
- '3' penalties work in both clockwise and counter-clockwise directions
- Direction reversal doesn't affect penalty mechanics
- Cardless state works with '3' as last card

### Jack Card (Feature 007)
- '3' penalties apply after skip calculation
- Skip mechanics don't interfere with penalty state
- Turn order respects both skip and penalty

### Two Card (Feature 009)
- '2' and '3' penalties are mutually exclusive
- Cross-blocking prevention enforced at validation layer
- Both use same `draw_penalty` field with different `penalty_type`
- UI handles both penalty types with appropriate messaging

---

## Known Limitations

- No sound effects for penalty activation (future enhancement)
- Penalty stacking variant not implemented (could be optional game mode)
- No animation for penalty transfer (future enhancement)
- Enhanced Ace blocking message only shows for '3' penalties (design decision)

---

## Critical Implementation Details

### Penalty Type Migration
**Challenge**: Existing '2' penalties didn't have `penalty_type` field.

**Solution**: Created migration script `priv/repo/migrate_penalty_data.exs`:
```elixir
# Backfill existing penalties with penalty_type: "two"
game_sessions
|> where([gs], fragment("? IS NOT NULL", gs.draw_penalty))
|> where([gs], fragment("?->>'active' = 'true'", gs.draw_penalty))
|> update([gs], set: [
  draw_penalty: fragment(
    "jsonb_set(?, '{penalty_type}', '\"two\"')",
    gs.draw_penalty
  )
])
|> Repo.update_all([])
```

### Cross-Blocking Validation
**Implementation**: Validator checks `penalty_type` before allowing plays:
```elixir
if penalty_active? and penalty_type == "three" do
  # Only '3' or Ace can block
  all_threes?(cards) or all_aces?(cards)
end
```

### Enhanced Ace Blocking UI
**Feature**: When Ace blocks a penalty, UI shows enhanced message with context:
- Regular Ace play: "Required Suit: [suit]" (normal suit selection)
- Ace blocks penalty: "Ace blocked penalty! Active suit: [suit] from last penalty card"
- Helps players understand why suit requirement exists

---

## Migration Guide

### For Developers
```bash
# Run migration script (if needed for existing data)
mix run priv/repo/migrate_penalty_data.exs

# Run tests
mix test  # Expect 403/403 passing

# Format code
mix format
```

### For Players
- New '3' card behavior is automatically available
- No configuration or settings changes required
- Game state persists across sessions (database-backed)
- Works seamlessly with existing '2' card penalties

### Rollback (if needed)
- No database schema changes (reuses existing `draw_penalty` column)
- Simply remove '3' card logic from codebase
- Existing games continue to work normally

---

## Related Documentation

### Specifications
- Requirements: `.kiro/specs/three-card/requirements.md`
- Design: `.kiro/specs/three-card/design.md`
- Task Breakdown: `.kiro/specs/three-card/tasks.md`

### Code References
- Core Logic: `lib/kadi/card_games.ex` (lines 450-550)
- Validation: `lib/kadi/games/play_validator.ex` (lines 200-250)
- LiveView UI: `lib/kadi_web/live/game_live.ex` (lines 150-200)
- Template: `lib/kadi_web/live/game_live.html.heex` (lines 100-150)
- Tests: `test/kadi/card_games/special_cards_three_test.exs`
- E2E Tests: `test/kadi_web/live/game_live_test.exs` (lines 1600-2200)

### Related Features
- [Two Card Feature](two-card-feature.md) - Sister penalty mechanic
- [Ace Card Feature](ace-card-feature.md) - Suit selection after Ace blocks
- [Jack Card Feature](jack-card-feature.md) - Skip mechanics interaction
- [King Card Feature](king-card-feature.md) - Direction change interaction

---

## Future Enhancements

Potential improvements for future iterations:
- Sound effects for penalty activation and blocking
- Animated penalty transfer visualization
- Penalty stacking variant (optional game mode)
- Penalty statistics in player profiles
- Replay system for penalty chains
- Custom penalty amounts (game configuration)
- Tournament mode with penalty scoring
- Visual distinction between '2' and '3' penalties (different colors)

---

## Glossary

- **Penalty Type**: Distinguishes between "two" and "three" penalties
- **Cross-Blocking**: Prevention of '2' blocking '3' and vice versa
- **Enhanced Message**: Special UI message when Ace blocks penalty
- **Non-Additive**: Multiple '3's don't stack penalty (always 3 cards)
- **Penalty Count Helper**: Function that returns 2 or 3 based on penalty_type
- **Action Suit**: Required suit after Ace blocks penalty
- **Cardless**: Player status after playing last card
- **Fresh Query**: Database query after transaction commit

---

## Changelog

### Version 1.0.0 (2025-11-16)
- ✅ Initial release
- ✅ Penalty activation with penalty_type="three"
- ✅ Blocking with Ace and '3' cards
- ✅ Cross-blocking prevention ('2' vs '3')
- ✅ Enhanced Ace blocking UI message
- ✅ Non-additive combo behavior
- ✅ Edge case handling (last card, recycling, starting card)
- ✅ Integration with existing features (Ace, King, Jack, Two)
- ✅ Comprehensive test coverage (403 tests passing)
- ✅ End-to-end testing (5 E2E scenarios)
- ✅ Migration script for existing data
- ✅ Documentation complete

---

**Last Updated**: 2025-11-16  
**Maintainer**: Development Team  
**Status**: Production Ready ✅
