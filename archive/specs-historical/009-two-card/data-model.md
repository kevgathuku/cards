# Data Model: Two Card Draw Penalty (Feature 009)

## Entities

### GameSession
- id: integer
- status: string ("lobby", "live", "complete")
- current_turn_player_id: integer
- requested_suit: string | nil
- draw_penalty: %{active: boolean, count: integer, target_player_id: integer | nil}
- ...existing fields...

### Player
- id: integer
- hand: [Card]
- ...existing fields...

### Card
- id: integer
- suit: string
- rank: string
- ...existing fields...

## Relationships
- GameSession has many Players (via game_session_players)
- GameSession has one Deck
- Deck has many Cards (via deck_cards)
- Penalty state is tracked in GameSession struct (no new table needed)

## Validation Rules
- '2' card cannot be starting card
- '2' card cannot be finishing card (player becomes cardless, penalty applies)
- Penalty can be blocked by Ace or another '2'
- Penalty is not additive (multiple '2's = draw 2)
- Requested suit must be matched if active

## State Transitions
- On playing '2': draw_penalty.active = true, draw_penalty.count = 2, draw_penalty.target_player_id = next player
- On blocking with Ace: draw_penalty.active = false, requested_suit = suit of '2'
- On blocking with '2': draw_penalty.target_player_id = next player
- On drawing: draw_penalty.active = false

## Continuity & Multi-Device Support (Constitution Section 2.1)

### Database-Backed State
- **draw_penalty** field in GameSession table enables full state recovery
- All penalty state (active, count, target_player_id) persisted to PostgreSQL
- No volatile in-memory state - database is single source of truth

### Disconnect/Reconnect Scenarios
- Player disconnects with active penalty → penalty state preserved in database
- Player reconnects → LiveView reloads GameSession from database with penalty intact
- Other players continue to see penalty indicator via PubSub broadcasts

### Multi-Device Support
- Player can close browser/switch devices while penalty is active
- Resume game from any device → penalty state loaded from database
- GameSession.draw_penalty field ensures consistent state across all sessions

### Recovery Mechanisms
- LiveView crashes → game reconstructed from database on reconnect
- Server restart → games resume with penalty state intact (database-persisted)
- Network interruption → penalty state maintained, UI resynchronizes on reconnect

---

## UI State (Session 2025-11-15 Improvements)

### LiveView Socket Assigns (Transient UI State)

**No new database fields required** - all UI enhancements use existing draw_penalty field

#### Button Visibility State
- **Computed from**: `@game_session.draw_penalty["active"]` && `@game_session.draw_penalty["target_player_id"] == @current_player.id`
- **Button shown**: "Draw 2 Cards" when penalty targets current player
- **Button hidden**: Normal "Draw Card" button when no penalty active
- **Strategic choice**: Button AND blocking cards (Ace/'2') both clickable simultaneously

#### Animation State
- **Trigger**: `accept_penalty` event clicked
- **Client-side hook**: `push_event("animate_draw", %{count: 2, duration: 400})`
- **CSS transitions**: Cards entering hand with `ease-out` timing
- **No server state**: Animation is purely visual, doesn't affect game logic

#### Error Message State  
- **Flash message**: "Penalty Active. You must play blocking card or draw penalty cards"
- **Triggered**: When player clicks non-blocking card during active penalty
- **Storage**: Phoenix flash (session-based, clears on next action)
- **Display**: Inline near card hand, not modal/toast

#### Penalty Indicator Timing
- **Visible when**: `draw_penalty["active"] == true`
- **Clears**: Immediately on `accept_penalty` click (database update sets `active: false`)
- **Animation timing**: Indicator disappears BEFORE card drawing animation starts (per FR-008)
- **Broadcast**: All connected clients see indicator change via PubSub

### State Flow Diagram

```
Player's Turn + Penalty Active
        ↓
   [Draw 2 Cards Button Visible]
   [Blocking Cards Clickable]
        ↓
   Player clicks button
        ↓
   1. send accept_penalty event
   2. server: process_draw_penalty/2
   3. server: draw_penalty.active = false (DB)
   4. server: broadcast game_updated
        ↓
   5. client: penalty indicator disappears (immediate)
   6. client: animate_draw event (300-500ms)
   7. client: hand updates with new cards
   8. server: turn auto-advances (already in process_draw_penalty)
```

### No Schema Changes Required

All UI improvements leverage existing `game_sessions.draw_penalty` :map field:
- Button visibility: computed from draw_penalty["active"] and draw_penalty["target_player_id"]
- Animation: client-side visual effect, no server state
- Error messages: transient flash storage
- Indicator timing: controlled by draw_penalty["active"] boolean

**Constitution compliance**: Section 2.1 (Database-Backed State) satisfied - all game-critical state remains in PostgreSQL, UI changes are presentation-layer only.
```
