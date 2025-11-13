# API Contract: Game State Transitions (Feature 009 - Two Card)

## Transition: Penalty Activation
- **Trigger:** Player plays '2' card
- **Effect:**
  - draw_penalty.active = true
  - draw_penalty.count = 2
  - draw_penalty.target_player_id = next player
  - requested_suit = nil

## Transition: Penalty Blocked
- **Trigger:** Next player plays Ace or another '2'
- **Effect:**
  - If Ace: draw_penalty.active = false, requested_suit = suit of '2'
  - If '2': draw_penalty.target_player_id = next player

## Transition: Penalty Draw
- **Trigger:** Target player draws
- **Effect:**
  - Player draws 2 cards
  - draw_penalty.active = false

## Transition: Finishing Card
- **Trigger:** Player attempts to finish with '2'
- **Effect:**
  - {:error, "Cannot finish with '2' card"}

## Transition: Suit Matching
- **Trigger:** Suit requested by Ace
- **Effect:**
  - Only cards matching requested_suit can be played until satisfied
