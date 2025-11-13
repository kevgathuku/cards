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
