# Feature Specification: Deal Start Card

**Feature Branch**: `001-deal-start-card`  
**Created**: 2025-11-03
**Status**: Draft  
**Input**: User description: "Flesh out the start game action. After assigning cards to each player, deal a start card from the deck. It cannot be 2,3,J,K,Q or A. Add some visualisation on the frontend so that the player can see their own cards, the cards played and the deck"

## Clarifications

### Session 2025-11-03

- Q: When a special card is rejected as the start card, should the system shuffle the entire remaining deck (re-randomizing all `order_index` values) or simply skip to the next sequential card? → A: Skip to next sequential card by `order_index` without reshuffling
- Q: How many cards should each player receive in their initial hand when the game starts? → A: 4 cards
- Q: Which player should be assigned the first turn when the game starts? → A: Random player selection
- Q: What should happen to special cards that are skipped when searching for a valid start card? → A: Move them to the bottom of the deck
- Q: Should the UI show other players' cards (as face-down card backs) or hide them entirely from view? → A: Show other players' hands as face-down card backs with count displayed

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Game Start and Initial Deal (Priority: P1)

As a player, when the game starts, I want to see my assigned cards, the first card played from the deck, and the remaining deck, so that I understand the initial state of the game.

**Why this priority**: This is the fundamental action of starting a game. Without it, players cannot begin to play.

**Independent Test**: Can be tested by starting a new game with at least two players. The test passes if all players' screens correctly display their own unique hand, a common starting card, and the deck.

**Acceptance Scenarios**:

1. **Given** a game lobby with at least two players, **When** the host starts the game, **Then** each player receives their initial hand of cards, a single valid start card is visible on the played pile, and a deck pile is visible.
2. **Given** the game has just started, **When** a player looks at their screen, **Then** they can see the face-up values of their own 4 cards, other players' hands displayed as face-down card backs with counts, the played pile with the starting card, and the deck.

### Edge Cases

- What happens if the first N cards drawn from the deck are all special cards (2, 3, J, Q, K, A)? The system should handle this gracefully by moving each special card to the bottom of the deck and continuing sequentially until a valid card is found.
- What happens if the deck has fewer cards than (4 × number of players) + 1? (This should be prevented by game setup rules, but is an edge case to consider).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST deal exactly 4 cards to each player as their initial hand, then automatically deal one additional card from the deck to serve as the starting card.
- **FR-002**: The starting card MUST NOT be a 2, 3, Jack, Queen, King, or Ace.
- **FR-003**: If a special card (as defined in FR-002) is encountered when seeking the starting card, the system MUST move it to the bottom of the deck and continue to the next sequential card (by `order_index`) until a valid one is found.
- **FR-004**: The user interface MUST render a view of the current player's own hand of cards with face-up values visible.
- **FR-004a**: The user interface MUST render other players' hands as face-down card backs with the card count displayed for each player.
- **FR-005**: The user interface MUST render a view of the played cards pile, initialized with the valid starting card.
- **FR-006**: The user interface MUST render a visual representation of the drawing deck.
- **FR-007**: The system MUST maintain the order of cards in the played stack, with the most recently played card being identifiable.
- **FR-008**: The system MUST randomly assign the turn to one player when the game starts.

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