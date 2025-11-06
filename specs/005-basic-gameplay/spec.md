# Feature Specification: Basic Gameplay - Regular Cards

**Feature Branch**: `005-basic-gameplay`  
**Created**: 2025-11-06  
**Status**: Draft  
**Input**: User description: "Implement the actual gameplay from the users. We are going to start with the regular cards - 4,5,6,7,9,10 then implement the rest later. As a general rule, the card played should match the suit or number of the last card on the played stack. For example, if the last card played has a suit of diamonds, the user can play another card matching the suit. Additionally if the last card played is a 4, then another 4 can be played and it will be valid. The regular cards can be played as just one card, or can be played as a combination. For example, if a player holds 4 of diamonds, and 4 of hearts, and the last card played is 5H (Five of hearts), the user can play both the 4H(four of hearts) and the 4D(four of diamonds) together and it counts as a valid play. Alternatively they can play just the 4H and it will also be a valid play. Implement the functionality to parse the cards a user plays and start with matching the regular cards for now, and validating if it is a valid hand. If valid, the cards are added to the stack in the order they were played i.e. the last card played remains on top of the played stack, removed from the player's cards and the turn passes to the next player"

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

1. **Given** the top card is 5 of Hearts, and player has 4 of Hearts and 4 of Diamonds in hand, **When** player plays both 4H and 4D together, **Then** both cards are added to the played stack (with 4D on top), removed from player's hand, and turn passes to next player
2. **Given** the top card is 6 of Clubs, and player has three 6s (Diamonds, Hearts, Spades) in hand, **When** player plays all three 6s together, **Then** all three cards are added to the played stack in played order, removed from player's hand, and turn passes to next player
3. **Given** the top card is 9 of Spades, and player has 7 of Spades, 7 of Hearts, and 7 of Clubs in hand, **When** player plays all three 7s together, **Then** all three cards are added to the played stack (with the last 7 played on top), removed from player's hand, and turn passes to next player

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

### Edge Cases

- What happens when a player has no valid cards to play?
- How does the system handle a player attempting to play cards they don't have in their hand?
- What happens if a player tries to play cards in rapid succession before turn updates?
- How does the system handle simultaneous plays from multiple players?
- What happens when the played stack is empty (first play of the game)?
- How does the system handle malformed input (invalid card representations)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST validate that at least one card in a play matches either the suit OR the number of the top card on the played stack
- **FR-002**: System MUST accept plays of single regular cards (4, 5, 6, 7, 9, 10) that match the top card's suit or number
- **FR-003**: System MUST accept plays of multiple cards only when all cards have the same number
- **FR-004**: System MUST validate that in a multi-card play, at least one card matches the top card's suit or number
- **FR-005**: System MUST reject plays where cards have different numbers
- **FR-006**: System MUST reject plays where no card matches the top card's suit or number
- **FR-007**: System MUST add played cards to the played stack in the order they were played, with the last card becoming the new top card
- **FR-008**: System MUST remove successfully played cards from the player's hand
- **FR-009**: System MUST advance the turn to the next player after a successful play
- **FR-010**: System MUST NOT advance the turn when a play is rejected
- **FR-011**: System MUST NOT modify the player's hand when a play is rejected
- **FR-012**: System MUST provide feedback to the player when a play is rejected, indicating the reason
- **FR-013**: System MUST parse user input representing one or more cards to play
- **FR-014**: System MUST validate that the player actually has the cards they are attempting to play in their hand

### Key Entities

- **Play**: Represents a player's action of playing one or more cards. Contains the list of cards being played, the player making the play, and the game state at the time of play
- **Card**: Represents a playing card with a suit (Hearts, Diamonds, Clubs, Spades) and a number (4, 5, 6, 7, 9, 10 for regular cards)
- **Played Stack**: An ordered collection of cards that have been played. The top card (most recently played) determines what cards can be played next
- **Player Hand**: A collection of cards that a player currently holds
- **Turn**: Represents which player is currently allowed to play. Advances sequentially through players

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Players can successfully play valid single cards with 100% accuracy (all valid plays are accepted, all invalid plays are rejected)
- **SC-002**: Players can successfully play valid card combinations with 100% accuracy
- **SC-003**: Invalid plays are rejected 100% of the time with clear feedback indicating the specific rule violation
- **SC-004**: Game state is correctly updated after each play within 100 milliseconds (cards moved, turn advanced)
- **SC-005**: Players can complete a full round of turns (all players play once) with correct turn progression 100% of the time
- **SC-006**: System handles edge cases (empty stack, no valid cards, malformed input) without crashing or corrupting game state
