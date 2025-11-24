# Feature Specification: Pick Card from Deck

**Feature Branch**: `003-pick-card-from-deck`  
**Created**: 2025-11-04
**Status**: Draft  
**Input**: User description: "Add a new feature to enable the player to pick a card from the deck. This is a valid move. The card they pick up should be moved from the deck and moved to the player's cards. The turn should then be assigned to the next player"

## Clarifications

### Session 2025-11-04

- Q: Should there be a limit on how many cards a player can have in their hand? → A: No limit
- Q: What should happen if the deck is empty when a player tries to pick a card? → A: Hide "Draw Card" button when deck is empty (deck recycling will be separate feature 004)
- Q: Should picking a card from the deck be allowed at any time during the player's turn, or only under specific conditions (e.g., cannot play any cards)? → A: Player can pick once OR play once, then turn auto-advances
- Q: How are players ordered for turn rotation? → A: By join order (`game_session_players.inserted_at`), wraps around
- Q: Is there a visual indicator for whose turn it is? → A: Yes, based on existing UI showing "Current Player" and "It's your turn!"
- Q: What should the button be labeled? → A: "Draw Card"
- Q: How should UI update after clicking? → A: Button disabled, UI updates only after broadcast received

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pick Card from Deck (Priority: P1)

As a player, when it's my turn, I want to be able to pick a card from the deck so that I can add it to my hand and continue playing the game.

**Why this priority**: This is a fundamental game action in Poker/Kadi. Players need this action when they cannot or choose not to play a card from their hand.

**Independent Test**: Can be tested by starting a game with 2+ players and having the current player click "Pick Card" button. Test passes if the player's hand increases by one card, the deck decreases by one card, and the turn advances to the next player.

**Acceptance Scenarios**:

1. **Given** a game is in progress and it's my turn, **When** I click "Draw Card", **Then** a card is moved from the deck to my hand, my hand count increases by 1, the deck count decreases by 1, the turn passes to the next player, and the "Draw Card" button is disabled.
2. **Given** a game is in progress and it's NOT my turn, **When** I view the game, **Then** the "Draw Card" button is hidden/disabled.
3. **Given** it's my turn and I draw a card from the deck, **When** the next player views the game, **Then** they see that it's now their turn and my hand count has increased by 1.

### User Story 2 - Empty Deck Handling (Priority: P2)

As a player, when the deck is empty, I want the "Draw Card" button to be hidden so that I understand I must play a card from my hand instead.

**Why this priority**: Edge case handling to prevent confusion and ensure game integrity.

**Independent Test**: Can be tested by creating a game state where the deck has 0 cards.

**Acceptance Scenarios**:

1. **Given** the deck is empty (0 cards remaining), **When** it's my turn, **Then** the "Draw Card" button is hidden and I can only play a card from my hand.
2. **Given** the deck is empty and it's my turn, **When** I play a card from my hand, **Then** the turn passes to the next player normally.

**Note**: Deck recycling (rebuilding deck from played stack) will be implemented in feature 004-recycle-played-stack.

### Edge Cases

- What happens if the deck has 0 cards? → "Draw Card" button is hidden; player must play from hand (deck recycling is feature 004)
- What happens if a player disconnects immediately after drawing a card? → Turn should still advance based on database state
- What happens if two players try to draw simultaneously (race condition)? → Database transaction should prevent this; first one wins
- Should the drawn card's identity be revealed to other players? → No, only the card count increases
- Can a player draw multiple times in one turn? → No, drawing once auto-advances turn (same as playing a card)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a "Draw Card" button that is visible only to the player whose turn it is and when the deck is not empty.
- **FR-002**: The system MUST validate that it is the requesting player's turn before allowing them to draw a card.
- **FR-003**: When a player draws a card from the deck, the system MUST move exactly one card from the deck to the player's hand.
- **FR-004**: The card drawn MUST be the next card in the deck based on the lowest `order_index` among remaining deck cards.
- **FR-005**: After a card is successfully drawn, the system MUST advance the turn to the next player in sequential order (by join time, wrapping around).
- **FR-006**: If the deck is empty (0 cards), the system MUST hide the "Draw Card" button.
- **FR-007**: The UI MUST update in real-time for all players showing: the current player's increased hand count, the decreased deck count, and the updated current turn player.
- **FR-008**: The system MUST broadcast the game state update to all connected players after a successful draw action.
- **FR-009**: Other players MUST NOT see which specific card was drawn, only that the player's hand count increased.
- **FR-010**: Drawing a card MUST automatically advance the turn (player cannot draw AND play in same turn).

### Non-Functional Requirements

- **NFR-001**: The draw card action MUST complete within 500ms from click to UI update.
- **NFR-002**: The action MUST be atomic (either fully succeeds or fully fails) using database transaction.
- **NFR-003**: The "Draw Card" button MUST be hidden when it's not the player's turn or when the deck is empty.
- **NFR-004**: The button MUST be disabled immediately upon click, re-enabling only after broadcast confirms state update.

### Key Entities *(include if feature involves data)*

- **GameSession**: Tracks `current_turn_player_id` to determine whose turn it is
- **Player**: Has a collection of cards in their hand
- **DeckCard**: Join table with `location_type` ('deck', 'player_hand', 'played_stack') and `player_id`
- **Deck**: Contains cards with `location_type` = 'deck'

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of valid draw card actions result in exactly one card moved from deck to player hand in database
- **SC-002**: 100% of draw card actions correctly advance the turn to the next player (by join order)
- **SC-003**: The draw card action completes within 500ms for 95% of requests
- **SC-004**: 100% of draw attempts when it's not the player's turn are prevented (button hidden)
- **SC-005**: UI updates are synchronized across all connected players within 1 second of the draw action
- **SC-006**: "Draw Card" button is hidden in 100% of cases where deck is empty

## Out of Scope *(mandatory)*

- **OOS-001**: Automatic card drawing when a player cannot make a valid move (requires separate game rule logic)
- **OOS-002**: Recycling played pile back into deck when deck is empty (future feature 004-recycle-played-stack)
- **OOS-003**: Animation effects for card movement (future UI enhancement)
- **OOS-004**: Undo/reverse draw action (not a valid game rule)
- **OOS-005**: Drawing multiple cards in one action (FR-010: draw auto-advances turn)
- **OOS-006**: Playing a card from hand (separate feature - not included here)

## Technical Approach *(optional)*

### High-Level Design

**Database Changes**: No schema changes required. Uses existing `deck_cards` table with `location_type` and `order_index`.

**Backend Flow**:
1. New function `Kadi.CardGames.draw_card_from_deck(game_session_id, player_id)`
2. Validate player's turn: `game_session.current_turn_player_id == player_id`
3. Validate deck not empty: `deck_cards WHERE location_type = 'deck'` count > 0
4. Find next card in deck: `SELECT * FROM deck_cards WHERE location_type = 'deck' ORDER BY order_index LIMIT 1`
5. Update card location: `UPDATE deck_cards SET location_type = 'player_hand', player_id = ?, order_index = NULL WHERE id = ?`
6. Calculate next player in turn order (by `game_session_players.inserted_at`, wrap around)
7. Update game session: `UPDATE game_sessions SET current_turn_player_id = ? WHERE id = ?`
8. Broadcast `game_updated` event to all players

**Frontend Flow**:
1. Add "Draw Card" button in GameLive template (visible only when `@current_turn_player.id == @current_player.id AND @deck_size > 0`)
2. Add `phx-click="draw_card"` event handler with `phx-disable-with` for loading state
3. Handle `handle_event("draw_card", ...)` in GameLive
4. Call `CardGames.draw_card_from_deck/2`
5. Do NOT update socket directly - wait for broadcast (NFR-004)
6. Update socket assigns via existing `handle_info` broadcast handler

**Turn Order Logic**:
- Query `game_session_players` ordered by `inserted_at` ASC
- Find current player's position in ordered list
- Advance to next position (wrap around to first if at end)

### Dependencies

- Phoenix LiveView (existing)
- Ecto transactions (existing pattern)
- Phoenix PubSub (existing for broadcasts)
- Database: PostgreSQL with existing schema

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Race condition (multiple players pick simultaneously) | High | Use database transaction with row-level locks |
| Empty deck edge case | Medium | Validate deck has cards before attempting pick |
| Turn order calculation error | High | Add comprehensive tests for 2, 3, 4+ player scenarios |
| Broadcast failure (some players not updated) | Medium | LiveView handles reconnection; rely on existing PubSub infrastructure |

## References *(optional)*

- Related Feature: 001-deal-start-card (establishes initial game state and deck)
- Related Feature: 002-randomize-player-cards (ensures deck order_index is randomized)
- Phoenix LiveView Event Handling: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_event/3
- Ecto Transactions: https://hexdocs.pm/ecto/Ecto.Repo.html#c:transaction/2
