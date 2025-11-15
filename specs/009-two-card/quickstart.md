# Quickstart: Two Card Draw Penalty (Feature 009)

## Overview
Implements special rules for the '2' card:
- Playing '2' forces next player to draw 2 cards (unless blocked)
- Penalty can be blocked by Ace or another '2'
- '2' cannot be starting or finishing card
- Penalty is not additive

## Steps

1. **Update Data Model**
   - Edit: `lib/kadi/games/game_session.ex`
     - Add field to schema: `field :draw_penalty, :map, default: %{active: false, count: 0, target_player_id: nil}`
     - Update struct definition to include `draw_penalty`
     - No new tables required

2. **Implement Player Actions**
   - Edit: `lib/kadi/card_games.ex`
     - Update `play_card/3`, `draw_card_from_deck/2`, and penalty/block logic to handle '2' card rules
     - Enforce validation rules for '2', Ace, finishing card
     - Reference: See validation logic in `lib/kadi/games/play_validator.ex`

3. **Integrate with Game Logic**
   - Edit: `lib/kadi/card_games.ex` and `lib/kadi_web/live/game_live.ex`
     - Ensure penalty state transitions are atomic (use Ecto.Multi for DB updates)
     - Broadcast game updates via PubSub after penalty/block/draw actions
     - Reference: See PubSub usage in `lib/kadi_web/live/game_live.ex`

4. **Test Edge Cases**
   - Edit: `test/kadi/card_games/special_cards_two_test.exs`
     - Add/extend tests for:
       - '2' as starting/finishing card
       - Penalty transfer and blocking
       - Suit matching with requested_suit
       - UI feedback for penalty
       - Edge cases (blocked, transferred, etc)

5. **UI Feedback** ✅ COMPLETED
   - Edit: `lib/kadi_web/live/game_live.ex` and `assets/css/app.css`
     - ✅ Penalty notification toast shows when player is targeted (FR-011)
     - ✅ Persistent visual indicator on game board when penalty active (FR-012)
     - ✅ Styled with Tailwind CSS and custom pulse animation
     - Implementation:
       - Added `check_and_show_penalty_notification/3` helper function
       - Added `find_penalty_creator/1` to identify who played the '2'
       - Toast notification with red styling for penalty type
       - Persistent banner with exclamation icons and penalty details
       - Custom CSS animation for subtle pulse effect

## Commands
- Run tests: `mix test`
- Format code: `mix format`
- Start server: `mix phx.server`
