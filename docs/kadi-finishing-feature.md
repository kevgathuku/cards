# Kadi Finishing Feature

## Overview

The Kadi finishing feature implements the "calling Kadi" mechanic that allows players to declare their intention to finish the game and win. This is similar to calling "Uno" in the Uno card game.

## Game Rules

### Winning the Game

To win a game of Kadi, a player must:

1. **Declare "Kadi"** by checking the "Declare Kadi" checkbox when playing their cards
2. **Successfully empty their hand** by playing valid card(s)
3. **Not play a blocking card** (K/J/2/3) as their final card(s)

When all conditions are met:
- The game status becomes `:finished`
- The player is marked as the winner
- A celebration banner is shown to all players
- No further actions can be taken in the game

### Invalid Finishing Attempts

A player becomes **cardless** (penalized) if they:

1. Play K, J, 2, or 3 as their final card(s) - even with Kadi declaration
2. _(Optional declaration)_ Kadi declaration is **optional** - players can empty their hand without declaring and remain in `:normal` status

### Kadi Status Management

#### Entering Kadi Status

- Check the "Declare Kadi" checkbox when playing cards
- If the play is successful, the player enters `:kadi` status
- A yellow banner appears showing "🎯 [Player] is in KADI!"
- All players can see who is in Kadi status

#### Maintaining Kadi Status

**Voluntary Draws** (regular draw button):
- A "Stay in Kadi after drawing" checkbox appears
- Default: checked (maintain Kadi)
- If unchecked: player returns to `:normal` status

**Involuntary Draws** (penalties, questions):
- Automatically reset player to `:normal` status
- No option to maintain Kadi
- Represents miscalculation of finishing attempt

## User Interface

### Declare Kadi Checkbox

**Location**: In the play form, above the "Play Selected" button  
**Visibility**: Only during normal play (not during penalty/suit selection/question)  
**Behavior**: 
- Checking the box sets player to `:kadi` status before playing
- Shown on every turn until player enters Kadi status

**Accessibility**:
- ARIA label: "Declare Kadi (required to win)"
- Tooltip: "Check this box when playing your last card(s) to declare 'Kadi' and attempt to win."

### Maintain Kadi Checkbox

**Location**: Next to the "Draw Card" button (in a separate form)  
**Visibility**: Only when player is in `:kadi` status  
**Behavior**: 
- Default: checked (player maintains Kadi)
- Unchecked: player returns to `:normal` after draw
- Only affects voluntary draws (not penalties/questions)

**Accessibility**:
- ARIA label: "Stay in Kadi after drawing"
- Tooltip: "Keep this checked to maintain your Kadi declaration after voluntary draw."

### Status Banners

#### Kadi Status Banner
- **Color**: Yellow gradient background with orange border
- **Content**: "🎯 [Player Name] is in KADI! (X cards left)"
- **Visibility**: Shown to ALL players when any player is in Kadi
- **Location**: Top of effects section
- **Accessibility**: `role="status"` `aria-live="polite"`

#### Winner Banner
- **Color**: Green gradient background with dark green border
- **Content**: "🎉 Game Finished! 🎉" + "Winner: [Player Name]"
- **Visibility**: Shown to ALL players when game is finished
- **Location**: Top of game page, before all other content
- **Actions**: "Back to Games" button

### Player Status Badge

**Location**: Next to player name in player list  
**Format**: "🎯 KADI"  
**Visibility**: Only shown for players with `:kadi` status

## Database Schema

### Game State

```clojure
{:status :finished          ;; When someone wins
 :winner 2                  ;; Player ID of winner
 :players [{:id 2
            :status :kadi}] ;; New :kadi status
 ...}
```

### Player Status Enum

Old: `[:enum :normal :penalty :skip :selecting-suit]`  
New: `[:enum :normal :penalty :skip :selecting-suit :kadi]`

### Events

#### play-cards Event

```clojure
{:type :play-cards
 :player-id 1
 :cards [...]
 :declare-kadi? true        ;; NEW - optional, default false
 :hand-size-before 3        ;; NEW - for analytics
 :timestamp ...}
```

#### draw-card Event

```clojure
{:type :draw-card
 :player-id 1
 :maintain-kadi? true       ;; NEW - optional, default false
 :timestamp ...}
```

## Implementation Details

### Core Functions

#### `check-cardless` (game.clj:315)

Updated rules:
- K/J/2/3 as last card → ALWAYS `:cardless` (even with Kadi)
- All other scenarios → No change to player status

#### `play-cards-cmd` (game.clj:438)

New parameter: `declare-kadi?` (optional, default false)

Logic flow:
1. Set player to `:kadi` if `declare-kadi?` is true
2. Play cards normally
3. Check cardless (may override to `:cardless`)
4. **Check for win**: If player in `:kadi` AND hand empty → set game to `:finished`, set `:winner`
5. Advance turn

#### `draw-card` (game.clj:187)

New parameter: `maintain-kadi?` (optional, default false)

Logic:
- If `maintain-kadi?` is true AND player currently in `:kadi` → stay in `:kadi`
- Otherwise → reset to `:normal`

### Event Replay

The `apply-action` multimethod properly handles events with or without the new fields:
- `declare-kadi?` defaults to `nil`/`false` → backward compatible
- `maintain-kadi?` defaults to `nil`/`false` → backward compatible

Old events replay correctly without the new fields.

## Testing

10 comprehensive tests cover all scenarios:

1. ✅ Valid single card finish with Kadi → Win
2. ✅ Valid combo finish with Kadi → Win
3. ✅ Invalid: King as last card → Cardless
4. ✅ Invalid: Jack as last card → Cardless
5. ✅ Invalid: 2 as last card → Cardless
6. ✅ Invalid: 3 as last card → Cardless
7. ✅ Empty hand without Kadi → Normal (optional declaration)
8. ✅ Voluntary draw + maintain → Stay in Kadi
9. ✅ Voluntary draw + no maintain → Reset to normal
10. ✅ Accept penalty in Kadi → Auto-reset to normal

All tests passing: `63 tests, 286 assertions, 0 failures`

## Behavior Matrix

| Scenario | Kadi? | Last Cards | Result |
|----------|-------|------------|--------|
| Valid finish | ✅ | 5♥ | **🏆 WIN** |
| Valid combo | ✅ | 7♥ 7♦ 7♣ | **🏆 WIN** |
| Invalid (K/J/2/3) | ✅ | K♥ | **Cardless** ⚠️ |
| No declaration | ❌ | 5♥ | **Normal** (no penalty) |
| Voluntary draw + maintain | - | - | **Stay Kadi** 🎯 |
| Accept penalty | - | - | **Auto-reset** |

## Migration Notes

### Backward Compatibility

- New `:kadi` player status added to schema
- Old games with 4 player statuses continue to work
- Events without `declare-kadi?` or `maintain-kadi?` replay correctly
- No database migration required - schema is additive

### Game Behavior Changes

**Before this feature**:
- Players could finish by emptying their hand
- No declaration required
- K/J/2/3 as last card → cardless

**After this feature**:
- Players must declare Kadi to win
- Without declaration, empty hand → normal status (no penalty)
- K/J/2/3 as last card → still cardless
- Voluntary draws allow maintaining Kadi status
- Involuntary draws (penalty/question) auto-reset Kadi

## Future Enhancements

Potential improvements (not currently implemented):

1. **Sound effects** when someone declares Kadi or wins
2. **Confetti animation** on winner banner
3. **Game statistics** (turns played, cards drawn, etc.)
4. **Rematch button** after game finishes
5. **Kadi history** - track who called Kadi when
6. **Mobile optimization** - responsive checkboxes and banners
7. **Notification** when opponent enters Kadi (browser notification)

## Related Files

- `src/kadi/schema.clj` - Schema definitions
- `src/kadi/game.clj` - Core game logic
- `src/kadi/handlers.clj` - HTTP handlers
- `src/kadi/views.clj` - UI components
- `test/kadi/game_test.clj` - Test suite
- `docs/CLOJURE_BOOTSTRAP_BRIEF.md` - Game rules reference

## See Also

- [Clojure Bootstrap Brief](./CLOJURE_BOOTSTRAP_BRIEF.md) - Full game specification
- [Game Rules Summary](./CLOJURE_BOOTSTRAP_BRIEF.md#28-kadi-finishing) - Section 2.8
