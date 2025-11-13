# Feature Specification: Ace Card Special Action

**Feature Branch**: `008-ace-card-feature`  
**Created**: 2025-11-10  
**Status**: Draft  
**Input**: User description: "Implement the functionality for the Ace card. When played it should enable the player to request for a particular suit to be played in the next turn. With this in force, only a card matching the suit is valid in the next play, unless another player plays another Ace, and then they can request a different suit or the same one if they choose to. After the A is played, if the subsequent players don't have the suit requested, their only option is to draw a card from the deck. An A can be played at whatever time and doesn't need to match the suit or rank of the top card"

## Clarifications

### Session 2025-11-10

- Q: (Provided upfront) Can a player play multiple aces in the same hand? → A: Yes, but the effect is the same as playing just one ace.
- Q: How should the player be prompted to select a suit after playing an Ace? → A: Display a button for each of the four suits.
- Q: What is the desired behavior if a player disconnects after playing an Ace but before selecting a suit? → A: The game is paused for that player, who is prompted to complete the move upon reconnecting.
- Q: (Provided upfront) What happens if the draw deck is empty and a player needs to draw? → A: Recycle the played cards to form a new draw deck.
- Q: When recycling the played cards to form a new draw deck, should the current top card on the play pile be included in the new deck? → A: No, the top card of the play pile is left in place and is not included in the new draw deck.
- Q: What should happen if a player must draw, but the draw deck is empty and there are no cards to recycle? → A: Log anomaly and skip (pass turn).

### Session 2025-11-13

- Q: When should the requested suit requirement be cleared? → A: Persist the requested suit across multiple turns until either (1) a player successfully plays a card matching the requested suit, or (2) a player plays an Ace and sets a new suit.
- Q: What happens to the requested suit when a player draws a card? → A: The requested suit persists after a player draws (their turn ends but the suit requirement remains active for the next player).
- Q: Can an Ace be selected as the starting card when dealing? → A: Yes, Aces are allowed as starting cards. When an Ace is the starting card, the first player can play any suit without needing to select a suit requirement (it behaves like a played Ace but without requesting a specific suit).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player uses an Ace to change the required suit (Priority: P1)

As a player, I want to play an Ace card at any point in my turn to change the active suit, forcing the next player to follow the suit I choose.

**Why this priority**: This is the core functionality of the Ace card and introduces a strategic new game mechanic.

**Independent Test**: Can be tested by starting a a game, giving a player an Ace, having them play it, and verifying that the game state correctly reflects the newly requested suit.

**Acceptance Scenarios**:

1. **Given** the top card is a '7 of Hearts', **When** the current player plays an 'Ace of Spades' and requests 'Clubs', **Then** the game state is updated to require 'Clubs' for the next turn.
2. **Given** it is a player's turn, **When** they play an Ace, **Then** the system MUST prompt them to choose a suit.
3. **Given** a player has chosen a new suit after playing an Ace, **Then** the game's top card is the Ace, but the active suit for the next play is the one chosen by the player.

---

### User Story 2 - Subsequent player must follow the requested suit (Priority: P2)

As the next player, I must play a card that matches the suit requested by the player who played an Ace, or draw a card if I cannot.

**Why this priority**: This enforces the rule introduced by the Ace card, making the previous story's action meaningful.

**Independent Test**: Following the test for P1, the next player attempts to play a card. Verify that only cards of the requested suit are accepted.

**Acceptance Scenarios**:

1. **Given** the previous player played an Ace and requested 'Diamonds', **When** the current player plays a 'King of Diamonds', **Then** the play is accepted, their turn ends, and the requested suit requirement is cleared.
2. **Given** the previous player played an Ace and requested 'Diamonds', **When** the current player attempts to play a 'King of Spades', **Then** the play is rejected and the player is notified they must play a 'Diamond'.
3. **Given** the previous player played an Ace and requested 'Diamonds' and the current player has no 'Diamonds', **When** the player chooses to draw a card, **Then** they draw one card from the deck, their turn ends, and the requested suit requirement persists for the next player.
4. **Given** the previous player played an Ace and requested 'Spades', **When** the current player plays a combo of '9 of Spades' and '9 of Hearts', **Then** the play is accepted because the lead card matches the requested suit, and the requested suit requirement is cleared.
5. **Given** Player A played an Ace and requested 'Hearts', and Player B drew a card (because they had no Hearts), **When** it becomes Player C's turn, **Then** Player C must still play a Heart or draw a card.
6. **Given** the requested suit is 'Clubs' and has persisted for two turns with players drawing, **When** a player finally plays a 'Club', **Then** the requested suit requirement is cleared.

---

### User Story 3 - Player uses another Ace to override the requested suit (Priority: P3)

As a player, if the previous player set a suit with an Ace, I want to be able to play my own Ace to change the required suit again.

**Why this priority**: This adds a counter-play dynamic and makes the game more competitive.

**Independent Test**: Following the test for P1, give the next player an Ace and have them play it. Verify they can set a new suit.

**Acceptance Scenarios**:

1. **Given** the previous player played an Ace and requested 'Hearts', **When** the current player plays an 'Ace of Clubs' and requests 'Spades', **Then** the play is accepted and the new required suit for the next player is 'Spades' (the previous 'Hearts' requirement is cleared).

---

### Edge Cases

- What happens if a player plays an Ace as their very last card? The player wins, and the suit-changing effect does not apply to the next game.
- What happens if an Ace is selected as the starting card? The Ace is allowed as a starting card. The first player can play any suit without needing to match a specific suit (it behaves like a played Ace but without requesting a specific suit).
- What happens if the draw deck is empty and a player needs to draw because they don't have the requested suit? The played cards are recycled to form a new draw deck.
- Can a player play an Ace even if they have other playable cards (of the required suit)? Yes, an Ace can be played at any time.
- What happens if a player disconnects after playing an Ace but before selecting a suit? The game is paused for that player, who is prompted to complete the move upon reconnecting.
- What happens if a player must draw when the draw deck is empty and there are no cards in the play pile to recycle? The system should log this anomaly, and the player's turn is skipped.
- What happens if multiple players in a row must draw because none of them have the requested suit? The requested suit requirement persists until someone plays a matching card or plays an Ace to change it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow a player to play an Ace card at any time during their turn, regardless of the top card's suit or rank.
- **FR-002**: Upon playing an Ace, the system MUST prompt the player to select a suit by displaying a button for each of the four suits (Clubs, Diamonds, Hearts, Spades).
- **FR-003**: The system MUST update the game state to reflect the player's chosen suit as the required suit, which persists across multiple turns until either (1) a player successfully plays a card matching the requested suit, or (2) a player plays an Ace and sets a new suit.
- **FR-004**: The system MUST validate the next player's move, enforcing that the lead card's suit matches the requested suit (for combos, subsequent cards may have different suits).
- **FR-005**: If a player's lead card does not match the requested suit, the system MUST reject the play, unless that card is also an Ace.
- **FR-006**: If a player does not have any cards of the requested suit, their only valid move is to draw one card from the deck; after drawing, their turn ends and the requested suit requirement persists for the next player.
- **FR-007**: Playing an Ace card MUST be a valid move even when a suit has been requested by a previous Ace.
- **FR-008**: A player MAY play multiple Aces in a single turn if they have them; this action has the same effect as playing a single Ace and only prompts for a suit choice once.
- **FR-009**: When the draw deck is replenished by recycling the play pile, the top card of the play pile MUST be left in place and not be included in the new draw deck.

### Key Entities *(include if feature involves data)*

- **Game**: Represents the overall state of the card game, including the current player, the deck, the pile, and any special game state rules (like a requested suit).
- **Player**: Represents a participant in the game, holding a hand of cards.
- **Card**: Represents a playing card, with a suit and a rank (e.g., Ace of Spades).
- **Suit**: Represents the four suits: Clubs, Diamonds, Hearts, Spades.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of plays following an Ace card correctly enforce the requested suit rule (or are another Ace).
- **SC-002**: When a player has no cards of the requested suit, they are correctly restricted to only the "draw card" action.
- **SC-003**: User session recordings show that players successfully use the Ace card to change game flow without errors or confusion.
- **SC-004**: The time from playing an Ace to selecting a suit and confirming the move should be less than 5 seconds for 95% of users.

## Assumptions

- After a player draws a card because they cannot play the requested suit, their turn ends. They cannot play the drawn card in the same turn, even if it matches the requested suit. The requested suit requirement persists for the next player.
- The game has a mechanism to handle an empty draw deck. If a player must draw but the deck is empty, the played cards are recycled to form a new draw deck.
- When a player successfully plays a card matching the requested suit, the requested suit requirement is cleared and normal gameplay resumes.