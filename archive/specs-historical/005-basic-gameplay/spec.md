# Feature Specification: Basic Gameplay - Regular Cards

**Feature Branch**: `005-basic-gameplay`  
**Created**: 2025-11-06  
**Status**: Draft  
**Input**: User description: "Implement the actual gameplay from the users. We are going to start with the regular cards - 4,5,6,7,9,10 then implement the rest later. As a general rule, the card played should match the suit or number of the last card on the played stack. For example, if the last card played has a suit of diamonds, the user can play another card matching the suit. Additionally if the last card played is a 4, then another 4 can be played and it will be valid. The regular cards can be played as just one card, or can be played as a combination. For example, if a player holds 4 of diamonds, and 4 of hearts, and the last card played is 5H (Five of hearts), the user can play both the 4H(four of hearts) and the 4D(four of diamonds) together and it counts as a valid play. Alternatively they can play just the 4H and it will also be a valid play. Implement the functionality to parse the cards a user plays and start with matching the regular cards for now, and validating if it is a valid hand. If valid, the cards are added to the stack in the order they were played i.e. the last card played remains on top of the played stack, removed from the player's cards and the turn passes to the next player"

## Clarifications

### Session 2025-11-06

- Q: When it is a player's turn and they have no valid cards to play, what should happen? → A: Player must draw a card from the deck, then the turn moves to the next player
- Q: When a player has no valid cards to play and must draw from the deck, but the deck is empty, what should happen? → A: Trigger recycling of the played stack into the deck (excluding top card)
- Q: After a player draws a card from the deck (when they have no valid play), should they be allowed to immediately play the newly drawn card if it's valid, or must they wait until their next turn? → A: Player must wait until their next turn to play the drawn card
- Q: When a player wants to play cards (either single or combo), how should they indicate which card(s) they want to play? → A: Click/tap to select cards from hand interface, then submit selection. Backend communication uses compact text notation (e.g., "4H" or "4H 4D")
- Q: Should the card notation text input be case-insensitive or case-insensitive? → A: Case-insensitive
- Q: When the played stack is recycled into the deck (when deck is empty), should the cards be shuffled randomly or placed in a specific order? → A: Shuffle randomly for unpredictability
- Q: Should card identifiers use compact notation (4H) or UUIDs, and should the backend receive cards as a list or space-separated string? → A: Use compact notation format "4H" (number + suit letter). Backend receives cards as a JSON array/list (e.g., ["4H"] or ["4H", "4D"]), NOT space-separated strings
- Q: When a player attempts an invalid play, what level of error detail should the system provide? → A: Specific error codes with user-friendly messages (e.g., "WRONG_SUIT: The card doesn't match the suit or number")
- Q: How should the system prevent race conditions when multiple players attempt to play simultaneously? → A: Database-level turn validation via GameSession.current_turn_player_id (primary safeguard), with client-side UI disabling (hide/disable play buttons when not your turn) as additional UX safeguard
- Q: When a player selects cards in the UI but doesn't submit them, what should happen to the selection state? → A: Auto-clear selection when turn changes (selection cleared if turn advances to another player)
- Q: What should happen if the backend receives malformed or invalid card notation from the frontend? → A: Return validation error with specific code (e.g., "INVALID_CARD_NOTATION: '4X' is not a valid card")
- Q: When a player loses connection and reconnects during a game, how should the UI recover and display the current game state? → A: Full state sync on reconnection (LiveView automatically reloads complete game state including current turn, all hands, played stack on mount)
- Q: When playing multiple cards in a combo, in what order should they be added to the played stack? → A: Array order is play order (first card in array goes down first, last card in array becomes top card)
- Q: How is the played stack tracked in the data model? → A: The played stack is already tracked through the existing DeckCard model with location_type='played_stack' and order_index for ordering

## Feature Dependencies

This feature builds upon and integrates with:

- **003-pick-card-from-deck** ✅ COMPLETE
  - **Reuses**: `CardGames.draw_card_from_deck/2` - Handles drawing a card when player has no valid play
  - **Integration Point**: When player has no valid cards to play, invoke this existing function instead of reimplementing
  
- **004-recycle-played-stack** ✅ COMPLETE
  - **Reuses**: `CardGames.recycle_played_stack/1` - Automatically triggered by `draw_card_from_deck/2` when deck is empty
  - **Integration Point**: No direct call needed - recycling happens automatically within the draw flow

**Important**: Do NOT reimplement drawing or recycling logic. Use existing context functions from features 003 and 004.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Play Single Matching Card (Priority: P1)

A player on their turn plays a single card from their hand that matches either the suit or number of the top card on the played stack. The system validates the play, adds the card to the played stack, removes it from the player's hand, and advances the turn to the next player.

**Why this priority**: This is the fundamental core gameplay mechanic. Without this, no game can progress. It represents the minimum viable gameplay loop.

**Independent Test**: Can be fully tested by setting up a game state with a known played stack top card (e.g., 5 of Hearts), a player with a valid matching card (e.g., 5 of Diamonds or 7 of Hearts), executing a play, and verifying the card moved from hand to stack and turn advanced.

**Acceptance Scenarios**:

1. **Given** the top card on the played stack is 5 of Hearts, and player has 5 of Diamonds in hand, **When** player plays 5 of Diamonds, **Then** the card is added to the played stack, removed from player's hand, and turn passes to next player
2. **Given** the top card on the played stack is 5 of Hearts, and player has 7 of Hearts in hand, **When** player plays 7 of Hearts, **Then** the card is added to the played stack, removed from player's hand, and turn passes to next player
3. **Given** the top card on the played stack is 10 of Clubs, and player has 10 of Spades in hand, **When** player plays 10 of Spades, **Then** the card is added to the played stack, removed from player's hand, and turn passes to next player

---

### User Story 2 - Play Multiple Matching Cards (Priority: P2)

A player on their turn plays multiple cards of the same number from their hand, where at least one card matches either the suit or number of the top card on the played stack. The system validates that all played cards have the same number, that the combination is valid, adds all cards to the played stack in the order played, removes them from the player's hand, and advances the turn.

**Why this priority**: This adds strategic depth by allowing combo plays, but the game is still playable with only single-card plays. It's a natural extension of the basic mechanic.

**Independent Test**: Can be fully tested by setting up a game state with a known played stack top card (e.g., 5 of Hearts), a player with multiple cards of the same number (e.g., 4 of Hearts and 4 of Diamonds), executing a combo play, and verifying all cards moved from hand to stack in correct order and turn advanced.

**Acceptance Scenarios**:

1. **Given** the top card is 5 of Hearts, and player has 4 of Hearts and 4 of Diamonds in hand, **When** player plays both 4H and 4D together (in array order ["4H", "4D"]), **Then** both cards are added to the played stack with 4H first and 4D on top, removed from player's hand, and turn passes to next player
2. **Given** the top card is 6 of Clubs, and player has three 6s (Diamonds, Hearts, Spades) in hand, **When** player plays all three 6s together (in array order ["6D", "6H", "6S"]), **Then** all three cards are added to the played stack in array order with 6S on top, removed from player's hand, and turn passes to next player
3. **Given** the top card is 9 of Spades, and player has 7 of Spades, 7 of Hearts, and 7 of Clubs in hand, **When** player plays all three 7s together (in array order ["7S", "7H", "7C"]), **Then** all three cards are added to the played stack in array order with 7C on top, removed from player's hand, and turn passes to next player

---

### User Story 3 - Invalid Play Rejection (Priority: P1)

A player attempts to play one or more cards that do not meet the validation rules. The system rejects the play, provides feedback on why it's invalid, keeps the cards in the player's hand, and does not advance the turn.

**Why this priority**: Essential for game integrity. Without validation, the game has no rules. This must be implemented alongside the valid play mechanics.

**Independent Test**: Can be fully tested by attempting various invalid plays (wrong suit/number, mixed numbers in combo, etc.) and verifying the system rejects them with appropriate feedback and maintains game state.

**Acceptance Scenarios**:

1. **Given** the top card is 5 of Hearts, and player has 9 of Clubs in hand, **When** player attempts to play 9 of Clubs, **Then** the play is rejected, player receives feedback that the card doesn't match suit or number, and the card remains in player's hand
2. **Given** the top card is 7 of Diamonds, and player attempts to play 4 of Hearts and 6 of Hearts together, **When** player submits this combo, **Then** the play is rejected because the cards have different numbers, player receives feedback, and both cards remain in player's hand
3. **Given** the top card is 10 of Spades, and player has 4 of Clubs and 4 of Hearts in hand, **When** player attempts to play both 4s together, **Then** the play is rejected because neither matches the suit or number of the top card, player receives feedback, and both cards remain in player's hand

---

### User Story 4 - Draw Card When No Valid Play (Priority: P1)

A player on their turn has no valid cards to play. The system allows the player to draw a card from the deck, adds it to their hand, and advances the turn to the next player. The drawn card cannot be played immediately and must wait until the player's next turn.

**Why this priority**: Essential for game progression when a player cannot play. Without this, games would stall. This is a core mechanic equal in importance to playing cards.

**Independent Test**: Can be fully tested by setting up a game state where a player has no cards matching the top card, executing a draw action, and verifying a card moved from deck to hand and turn advanced without allowing immediate play.

**Acceptance Scenarios**:

1. **Given** the top card is 5 of Hearts, and player has only 9 of Clubs and 10 of Diamonds (no matching cards), **When** player draws from the deck, **Then** one card is added to player's hand from the deck and turn passes to next player
2. **Given** the deck has 3 cards remaining, and player cannot play any cards, **When** player draws from the deck, **Then** the deck has 2 cards remaining, player's hand increases by 1 card, and turn advances
3. **Given** the deck is empty, and player cannot play any cards, **When** player attempts to draw, **Then** the played stack (excluding top card) is recycled into the deck, player draws one card from the newly filled deck, and turn advances
4. **Given** player draws a 5 of Diamonds and the top card is 5 of Hearts, **When** the draw action completes, **Then** the turn advances to next player without allowing the player to immediately play the 5 of Diamonds

---

### Edge Cases

- When a player has no valid cards to play, they must draw a card from the deck
- When the deck is empty and a player needs to draw, the played stack (excluding the top card) is recycled into the deck before drawing
- Players select cards by clicking/tapping them in the UI; backend receives compact card notation
- Backend card notation parsing is case-insensitive (both "4H" and "4h" are valid)
- How does the system handle a player attempting to play cards they don't have in their hand?
- What happens if a player tries to play cards in rapid succession before turn updates?
- How does the system handle simultaneous plays from multiple players?
- What happens when the played stack is empty (first play of the game)?
- How does the system handle malformed card notation from the UI (backend validates and returns INVALID_CARD_NOTATION error)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST validate that it is the requesting player's turn by checking GameSession.current_turn_player_id before processing any play action
- **FR-002**: System MUST validate that at least one card in a play matches either the suit OR the number of the top card on the played stack
- **FR-003**: System MUST accept plays of single regular cards (4, 5, 6, 7, 9, 10) that match the top card's suit or number
- **FR-004**: System MUST validate that in a multi-card play, at least one card matches the top card's suit or number
- **FR-005**: System MUST reject plays where cards have different numbers
- **FR-006**: System MUST reject plays where no card matches the top card's suit or number
- **FR-007**: System MUST add played cards to the played stack in the order they were played, with the last card becoming the new top card (for combos: first card in array goes down first, last card in array becomes top card)
- **FR-008**: System MUST remove successfully played cards from the player's hand
- **FR-009**: System MUST advance the turn to the next player after a successful play
- **FR-010**: System MUST NOT advance the turn when a play is rejected
- **FR-011**: System MUST NOT modify the player's hand when a play is rejected
- **FR-012**: System MUST provide feedback to the player when a play is rejected, using specific error codes paired with user-friendly messages (e.g., "NOT_YOUR_TURN: Please wait for your turn", "WRONG_SUIT: The card doesn't match the suit or number", "MIXED_NUMBERS: All cards in a combo must have the same number")
- **FR-013**: System MUST provide a user interface allowing players to select cards from their hand by clicking/tapping
- **FR-014**: System MUST hide or disable play action buttons in the UI when it is not the player's turn (as additional UX safeguard beyond server-side validation)
- **FR-015**: System MUST communicate selected cards to the backend using card notation format as a JSON array/list (e.g., ["4H"] for single card, ["4H", "4D"] for combo)
- **FR-016**: System MUST validate that the player actually has the cards they are attempting to play in their hand
- **FR-017**: System MUST allow a player to draw a card from the deck when they have no valid cards to play
- **FR-018**: System MUST add the drawn card to the player's hand
- **FR-019**: System MUST advance the turn to the next player after a player draws a card
- **FR-020**: System MUST recycle the played stack (excluding the top card) into the deck when the deck is empty and a player needs to draw
- **FR-021**: System MUST randomly shuffle the recycled cards when creating a new deck from the played stack
- **FR-022**: System MUST NOT allow a player to play a newly drawn card in the same turn it was drawn
- **FR-023**: Backend MUST accept card notation in the format: number followed by suit letter (4H, 5D, 6C, 7S, 9H, 10D, etc.) where H=Hearts, D=Diamonds, C=Clubs, S=Spades
- **FR-024**: Backend MUST accept card lists as JSON arrays (e.g., ["4H", "4D", "4C"]) for combo plays, NOT space-separated strings
- **FR-025**: Backend MUST parse card notation in a case-insensitive manner (e.g., "4H", "4h", and "4H" are all valid)
- **FR-026**: Backend MUST validate card notation format and return specific error codes for malformed notation (e.g., "INVALID_CARD_NOTATION: '4X' is not a valid card" for invalid suit, "INVALID_CARD_NOTATION: '99H' is not a valid card number" for invalid number)

### Key Entities

- **Play**: Represents a player's action of playing one or more cards. Contains the list of cards being played, the player making the play, and the game state at the time of play
- **Card**: Represents a playing card with a suit (Hearts, Diamonds, Clubs, Spades) and a number (4, 5, 6, 7, 9, 10 for regular cards)
- **Played Stack**: An ordered collection of cards that have been played. The top card (most recently played) determines what cards can be played next
- **Player Hand**: A collection of cards that a player currently holds
- **Turn**: Represents which player is currently allowed to play. Advances sequentially through players
- **Deck**: An ordered collection of undealt cards that players draw from when they cannot play. Can be replenished by recycling the played stack (excluding top card) when empty

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Players can successfully play valid single cards with 100% accuracy (all valid plays are accepted, all invalid plays are rejected)
- **SC-002**: Players can successfully play valid card combinations with 100% accuracy
- **SC-003**: Invalid plays are rejected 100% of the time with clear feedback indicating the specific rule violation
- **SC-004**: Game state is correctly updated after each play within 100 milliseconds (cards moved, turn advanced)
- **SC-005**: Players can complete a full round of turns (all players play once) with correct turn progression 100% of the time
- **SC-006**: System handles edge cases (empty stack, no valid cards, malformed input) without crashing or corrupting game state
- **SC-007**: Players can draw cards when they have no valid plays, with the deck correctly replenishing from the played stack when empty 100% of the time
- **SC-008**: UI automatically clears card selection state when turn changes to another player 100% of the time
- **SC-009**: When a player reconnects after network disconnection, the UI displays the current accurate game state (current turn, all hands, played stack) within 2 seconds 100% of the time
