# Feature Specification: Deal Start Card

**Feature Branch**: `001-deal-start-card`  
**Created**: 2025-11-03
**Status**: Draft  
**Input**: User description: "Flesh out the start game action. After assigning cards to each player, deal a start card from the deck. It cannot be 2,3,J,K,Q or A. Add some visualisation on the frontend so that the player can see their own cards, the cards played and the deck"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Game Start and Initial Deal (Priority: P1)

As a player, when the game starts, I want to see my assigned cards, the first card played from the deck, and the remaining deck, so that I understand the initial state of the game.

**Why this priority**: This is the fundamental action of starting a game. Without it, players cannot begin to play.

**Independent Test**: Can be tested by starting a new game with at least two players. The test passes if all players' screens correctly display their own unique hand, a common starting card, and the deck.

**Acceptance Scenarios**:

1. **Given** a game lobby with at least two players, **When** the host starts the game, **Then** each player receives their initial hand of cards, a single valid start card is visible on the played pile, and a deck pile is visible.
2. **Given** the game has just started, **When** a player looks at their screen, **Then** they can only see the value of their own cards, not the cards of other players.

### Edge Cases

- What happens if the first N cards drawn from the deck are all special cards (2, 3, J, Q, K, A)? The system should handle this gracefully by continuing to draw until a valid card is found.
- What happens if the deck has fewer cards than the number of players + 1? (This should be prevented by game setup rules, but is an edge case to consider).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST automatically deal one card from the deck after all players have received their hands to serve as the starting card.
- **FR-002**: The starting card MUST NOT be a 2, 3, Jack, Queen, King, or Ace.
- **FR-003**: If a special card (as defined in FR-002) is drawn to be the starting card, the system MUST place it back into the deck, shuffle, and draw a new card until a valid one is selected.
- **FR-004**: The user interface MUST render a view of the current player's own hand of cards.
- **FR-005**: The user interface MUST render a view of the played cards pile, initialized with the valid starting card.
- **FR-006**: The user interface MUST render a visual representation of the drawing deck.
- **FR-007**: The system MUST maintain the order of cards in the played stack, with the most recently played card being identifiable.

### Key Entities *(include if feature involves data)*

- **GameSession**: Represents the state of a single game, including players, deck, and played pile.
- **Player**: A participant in the game, having their own hand of cards.
- **Card**: An individual playing card with a suit and rank.
- **Deck**: The collection of cards from which players draw.
- **PlayedPile**: The collection of cards that have been played, starting with the initial card.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of newly started games have a valid (non-special) starting card on the played pile.
- **SC-002**: On game start, the complete initial game view (player hand, deck, played pile) renders for all players in under 2 seconds.
- **SC-003**: The game state (player hands, deck, played pile) is correctly and consistently synchronized across all connected players' screens immediately upon game start.