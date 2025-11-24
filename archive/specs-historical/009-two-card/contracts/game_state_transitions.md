# API Contract: Game State Transitions (Feature 009 - Two Card)

## Transition: Penalty Activation
- **Trigger:** Player plays '2' card
- **Effect:**
  - draw_penalty.active = true
  - draw_penalty.count = 2
  - draw_penalty.target_player_id = next player
  - requested_suit = nil
  - **UI:** Toast notification shown to targeted player (FR-011)
  - **UI:** Persistent penalty indicator displayed on game board (FR-012)

## Transition: Penalty Blocked
- **Trigger:** Next player plays Ace or another '2'
- **Effect:**
  - If Ace: draw_penalty.active = false, requested_suit = suit of '2'
  - If '2': draw_penalty.target_player_id = next player
  - **UI:** Penalty indicator updates to show new target (if '2') or disappears (if Ace)

## Transition: Penalty Draw
- **Trigger:** Target player draws (auto-draw via T022)
- **Effect:**
  - Player draws 2 cards
  - draw_penalty.active = false
  - **UI:** Penalty indicator disappears
  - **UI:** Toast notification cleared

## Transition: Finishing Card
- **Trigger:** Player plays '2' as last card
- **Effect:**
  - Player enters "cardless" status (not winning)
  - Penalty still applies to next player
  - Game continues

## Transition: Suit Matching
- **Trigger:** Suit requested by Ace
- **Effect:**
  - Only cards matching requested_suit can be played until satisfied

## UI State (Phase 5 Implementation)

### Penalty Notification (FR-011)
- **Type:** Toast notification (auto-dismiss after 2s)
- **Trigger:** When draw_penalty.target_player_id == current_player.id
- **Message:** "You must draw {count} cards due to {player}'s '2' card"
- **Styling:** Red background (bg-red-50, border-red-300, text-red-800)

### Penalty Indicator (FR-012)
- **Type:** Persistent banner
- **Visibility:** All players see it when draw_penalty.active == true
- **Content:** 
  - Exclamation triangle icons
  - "Draw {count} Penalty Active"
  - "{target_player} must draw {count} cards or block with an Ace/'2'"
- **Styling:** Red theme with pulse animation
- **Location:** Below direction indicator, above toast notifications
