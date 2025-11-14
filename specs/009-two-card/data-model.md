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
