# LiveView Event Contracts - Two Card Penalty UI

## Overview
This document defines the contracts for LiveView events added to support the Two Card penalty acceptance UI improvements. All events operate within the existing `KadiWeb.GameLive` LiveView module.

## Events

### accept_penalty

**Purpose**: Handle explicit user acceptance of the Two Card draw penalty

**Handler Location**: `lib/kadi_web/live/game_live.ex`

**Event Name**: `"accept_penalty"`

**Parameters**: 
```elixir
%{} # No parameters required - game context from socket
```

**Preconditions**:
- Player must be authenticated (socket.assigns.current_player)
- Game session must be in "live" status
- Current player must be the active turn player
- Game must have an active draw_penalty (socket.assigns.game_session.draw_penalty != %{})
- Draw penalty must have pending_count > 0

**Contract**:
```elixir
def handle_event("accept_penalty", _params, socket) do
  game_session = socket.assigns.game_session
  player_id = socket.assigns.current_player.id
  
  case CardGames.process_draw_penalty(game_session, player_id) do
    {:ok, updated_game_session} ->
      # Don't update socket - wait for broadcast
      {:noreply, socket}
      
    {:error, :not_current_turn} ->
      {:noreply, put_flash(socket, :error, "It's not your turn")}
      
    {:error, :no_penalty} ->
      {:noreply, put_flash(socket, :error, "No penalty to accept")}
      
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Cannot draw penalty: #{reason}")}
  end
end
```

**Success Path**:
1. `CardGames.process_draw_penalty/2` called with game_session and player_id
2. Backend draws pending_count cards from deck to player's hand
3. Backend clears draw_penalty to %{}
4. Backend advances current_turn_player_id to next player
5. Backend broadcasts `{:game_updated, updated_game_session}` via PubSub
6. All connected clients receive broadcast via `handle_info/2`
7. Socket state updated in `handle_info` callback (not in `handle_event`)
8. UI shows animation (300-500ms) of cards moving to hand
9. Penalty indicator cleared before animation starts (FR-008)
10. Turn advances to next player after animation completes

**Error Paths**:
- **:not_current_turn**: Flash error "It's not your turn", button remains visible
- **:no_penalty**: Flash error "No penalty to accept", button hidden (shouldn't occur if UI logic correct)
- **:insufficient_cards**: Flash error "Not enough cards in deck to draw penalty" (rare edge case)
- **Other errors**: Flash generic error message with reason

**Side Effects**:
- Database: 
  - Updates game_sessions.draw_penalty to %{}
  - Updates game_sessions.current_turn_player_id
  - Updates deck_cards.location_type for drawn cards ("deck" → "player_hand")
  - Updates deck_cards.player_id for drawn cards (NULL → player_id)
- PubSub: Broadcasts game_updated event to all subscribed clients
- UI (via broadcast): 
  - Hides "Draw 2 Cards" button
  - Shows animation of cards moving to hand
  - Clears penalty indicator
  - Updates turn indicator
  - Enables/disables action buttons based on new turn

**Validation**:
- Player authentication: Required by LiveView mount (on_mount :require_authenticated_player)
- Turn validation: Checked in `CardGames.process_draw_penalty/2` (returns :not_current_turn if invalid)
- Penalty existence: Checked in `CardGames.process_draw_penalty/2` (returns :no_penalty if none)

**Testing Requirements**:
- Unit test: Verify event handler calls `CardGames.process_draw_penalty/2` correctly
- Integration test: Verify full flow from button click → DB update → broadcast → UI update
- Error test: Verify each error path displays correct flash message
- Multi-client test: Verify all connected players see penalty acceptance (SPR-002 pattern)
- Animation test: Verify penalty indicator cleared before animation starts (FR-008)

**Related Requirements**:
- FR-004: Explicit acceptance button replaces automatic drawing
- FR-005: Button temporarily replaces normal "Draw Card" button
- FR-006: Specific error messages for edge cases
- FR-008: Penalty indicator cleared before animation
- SC-005: Button only visible when penalty active and player's turn
- SC-006: Penalty accepted and cards drawn with single click
- SC-007: Animation provides clear visual feedback

**Dependencies**:
- Existing: `Kadi.CardGames.process_draw_penalty/2` (card_games.ex lines 487-543)
- Existing: Phoenix PubSub broadcast mechanism
- Existing: LiveView JS hooks for animations (if needed)
- New: CSS transitions for card movement animation (app.css)
- New: Socket assign for animation trigger state

---

## State Management

### Socket Assigns Related to Penalty UI

```elixir
socket.assigns = %{
  game_session: %GameSession{
    draw_penalty: %{
      pending_count: 2 | 4 | 6 | 8,  # Number of cards to draw
      source_player_id: integer()     # ID of player who played the 2
    } | %{},  # Empty map when no penalty active
    current_turn_player_id: integer(),
    # ... other fields
  },
  current_player: %Player{id: integer()},
  show_penalty_animation: boolean(),  # NEW: Trigger for card movement animation
  # ... other assigns
}
```

### State Flow

1. **Penalty Active State**
   - Condition: `game_session.draw_penalty != %{}`
   - UI: "Draw 2 Cards" button visible (replaces "Draw Card")
   - Blocking: Cards in hand clickable (strategic choice per FR-009)

2. **Button Click State**
   - Trigger: User clicks "Draw 2 Cards" button
   - Event: `accept_penalty` fired
   - Handler: Calls `CardGames.process_draw_penalty/2`
   - UI: No immediate socket update (wait for broadcast)

3. **Processing State**
   - Backend: Ecto.Multi transaction updating DB
   - Backend: Broadcast `game_updated` event
   - UI: Button remains visible during processing

4. **Animation Trigger State** (from broadcast)
   - Condition: `handle_info({:game_updated, game_session}, socket)`
   - Action: Set `show_penalty_animation: true` in socket assigns
   - UI: Penalty indicator cleared immediately (FR-008)
   - UI: Start 300-500ms animation of cards moving to hand

5. **Post-Animation State**
   - Backend state: `game_session.draw_penalty == %{}`
   - Backend state: `current_turn_player_id` advanced to next player
   - UI: "Draw 2 Cards" button hidden
   - UI: Normal "Draw Card" button visible (if player's turn)
   - UI: Turn indicator updated

### Button Visibility Logic

```elixir
@doc """
Determines if penalty acceptance button should be shown.

Returns true when:
1. Draw penalty exists (draw_penalty != %{})
2. Current player is the turn player
3. Game session is in "live" status

This replaces the normal "Draw Card" button when active.
"""
def show_penalty_button?(game_session, current_player) do
  game_session.draw_penalty != %{} and
  game_session.current_turn_player_id == current_player.id and
  game_session.status == "live"
end
```

### Error Message Mapping

```elixir
# From FR-006: Specific error messages for edge cases
case CardGames.process_draw_penalty(game_session, player_id) do
  {:error, :not_current_turn} -> 
    "It's not your turn"
    
  {:error, :no_penalty} -> 
    "No penalty to accept"
    
  {:error, :insufficient_cards} -> 
    "Not enough cards in deck to draw penalty"
    
  {:error, reason} -> 
    "Cannot draw penalty: #{reason}"
end
```

---

## Integration Points

### With Existing Code

**CardGames Context** (lib/kadi/card_games.ex):
- Reuses: `process_draw_penalty/2` (lines 487-543)
- No modifications needed to backend logic
- Returns `{:ok, game_session}` or `{:error, reason}`

**GameLive** (lib/kadi_web/live/game_live.ex):
- Extends: `handle_event/3` with new `"accept_penalty"` clause
- Extends: `handle_info/2` to set animation trigger on game_updated
- Extends: Template logic for conditional button rendering

**Tests** (test/kadi/card_games/special_cards_two_test.exs):
- Reuses: SPR-002 multi-device test pattern (lines 856-959)
- Extends: Add UI-specific tests in game_live_test.exs

### With New Code

**CSS Animations** (assets/css/app.css):
- Defines: `.penalty-card-animation` class with 300-500ms transition
- Applies: Transform/opacity changes for card movement effect

**Template** (lib/kadi_web/live/game_live.html.heex):
- Adds: Conditional rendering for penalty button vs normal draw button
- Adds: Animation classes on card elements when `show_penalty_animation` true

---

## Performance Considerations

- **Response Time**: Button click → DB update → broadcast should complete in <100ms
- **Animation Duration**: 300-500ms CSS transition (configurable)
- **Network**: Broadcast to N clients scales linearly with player count
- **Database**: Single Ecto.Multi transaction (4-5 operations), indexed on player_id and game_session_id

---

## Security Considerations

- **Authentication**: Verified by LiveView `on_mount :require_authenticated_player`
- **Authorization**: Player can only accept penalty for themselves (player_id from socket.assigns)
- **Turn Validation**: Backend enforces current_turn_player_id check
- **Race Conditions**: Ecto.Multi ensures atomic updates, broadcasts ensure all clients sync

---

## Backwards Compatibility

- No breaking changes: Existing `process_draw_penalty/2` function unchanged
- No schema changes: Uses existing `draw_penalty` field
- No API changes: All UI-only additions
- Tests: Existing backend tests unaffected, new UI tests added separately

---

## Documentation References

- Spec: `/Users/kevin/code/elixir/cards/specs/009-two-card/spec.md`
- Plan: `/Users/kevin/code/elixir/cards/specs/009-two-card/plan.md`
- Research: `/Users/kevin/code/elixir/cards/specs/009-two-card/research.md`
- Data Model: `/Users/kevin/code/elixir/cards/specs/009-two-card/data-model.md`
