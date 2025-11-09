# Feature Specification: Jack Card (Jump/Skip Functionality)

**Feature Branch**: `007-jack-card`  
**Created**: 2025-11-08  
**Status**: Draft  
**Input**: User description: "Implement the functionality for the J / Jack card. In this game J functions as a Jump card. Playing a J skips / jumps over the next player in the turn. J can be played in a combo, and the number of jumps aligns with the number of J cards played. For example, in a game with 3 players, when player 1 plays 2 Js during their turn, the turn comes back to them. J also has to follow the previous rules - it has to match the suit or rank of the top card"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single Jack Skips Next Player (Priority: P1)

A player plays a single Jack card, causing the turn to skip over the next player and move to the player after them.

**Why this priority**: Core functionality that introduces the basic Jack mechanic. This is the minimum viable implementation that delivers the "jump" behavior.

**Independent Test**: Can be fully tested by setting up a 3-player game, having player 1 play a Jack, and verifying the turn advances to player 3 (skipping player 2).

**Acceptance Scenarios**:

1. **Given** a 3-player game (P1, P2, P3) where it's P1's turn and P1 has a Jack matching the top card, **When** P1 plays the Jack, **Then** the turn advances to P3 (P2 is skipped)
2. **Given** a 4-player game (P1, P2, P3, P4) where it's P2's turn and P2 has a Jack matching the top card, **When** P2 plays the Jack, **Then** the turn advances to P4 (P3 is skipped)
3. **Given** a 2-player game (P1, P2) where it's P1's turn and P1 has a Jack matching the top card, **When** P1 plays the Jack, **Then** the turn wraps around and comes back to P1 (since there's only one other player to skip)

---

### User Story 2 - Jack Combo Multiplies Skip Count (Priority: P2)

A player plays multiple Jack cards in a combo, with each Jack adding one more skip. The number of players skipped equals the number of Jacks played.

**Why this priority**: Extends the basic mechanic with combo functionality, allowing for strategic gameplay where accumulated Jacks can be used for greater effect.

**Independent Test**: Can be fully tested by setting up a 3-player game, having player 1 play 2 Jacks, and verifying the turn skips 2 players (wrapping back to player 1).

**Acceptance Scenarios**:

1. **Given** a 3-player game (P1, P2, P3) where it's P1's turn and P1 has 2 Jacks of the same rank matching the top card, **When** P1 plays both Jacks, **Then** the turn skips 2 players (P2 and P3) and returns to P1
2. **Given** a 5-player game where it's P1's turn and P1 has 3 Jacks matching the top card, **When** P1 plays 3 Jacks, **Then** the turn advances to P5 (skipping P2, P3, P4)
3. **Given** a 4-player game (P1, P2, P3, P4) where it's P1's turn and P1 has 4 Jacks matching the top card, **When** P1 plays 4 Jacks, **Then** the turn wraps around and advances to P2 (skipping P2, P3, P4, then wrapping to skip P1, landing on P2)

---

### User Story 3 - Jack Follows Standard Matching Rules (Priority: P1)

Jack cards can only be played if they match the top card's suit or rank, following the same validation rules as other cards.

**Why this priority**: Ensures consistency with existing game rules and prevents Jacks from being overpowered "play anytime" cards.

**Independent Test**: Can be fully tested by attempting to play a Jack that doesn't match the top card and verifying it's rejected.

**Acceptance Scenarios**:

1. **Given** the top card is 5 of hearts and player has Jack of hearts, **When** player plays the Jack, **Then** the play is accepted (suit matches)
2. **Given** the top card is Jack of diamonds and player has Jack of clubs, **When** player plays the Jack, **Then** the play is accepted (rank matches)
3. **Given** the top card is 7 of spades and player has Jack of hearts, **When** player attempts to play the Jack, **Then** the play is rejected (neither suit nor rank matches)

---

### User Story 4 - Jack Combo Validation (Priority: P2)

When playing multiple Jacks as a combo, all Jacks must be of the same rank (all Jacks), and at least one must match the top card.

**Why this priority**: Maintains combo consistency with other cards while allowing strategic Jack accumulation.

**Independent Test**: Can be fully tested by attempting various Jack combo scenarios and verifying proper validation.

**Acceptance Scenarios**:

1. **Given** the top card is Jack of diamonds and player has Jack of hearts and Jack of clubs, **When** player plays both Jacks, **Then** the play is accepted (all same rank, first matches top card)
2. **Given** the top card is 8 of hearts and player has Jack of hearts and Jack of diamonds, **When** player plays both Jacks, **Then** the play is accepted (all same rank, first matches by suit)
3. **Given** the top card is 5 of clubs and player has Jack of spades and Jack of diamonds, **When** player attempts to play both Jacks, **Then** the play is rejected (neither Jack matches top card)

---

### User Story 5 - Jack as Last Card Creates Cardless State (Priority: P1)

When a player plays Jack(s) as their last card(s), they enter cardless state instead of winning. They must wait for their turn to return before drawing a card.

**Why this priority**: Critical game rule that prevents Jack from being a winning card, maintaining game balance and strategy.

**Independent Test**: Can be fully tested by setting up a scenario where a player has only Jack(s) in hand, plays them, and verifies they enter cardless state rather than winning.

**Acceptance Scenarios**:

1. **Given** a 3-player game where P1 has only 1 Jack left matching the top card, **When** P1 plays the Jack, **Then** P1 enters cardless state and the turn advances to P3 (skipping P2, not counting P1 in skip)
2. **Given** a 4-player game where P2 has only 2 Jacks left matching the top card, **When** P2 plays both Jacks as a combo, **Then** P2 enters cardless state and the turn advances to P1 (skipping P3 and P4, wrapping around, not counting P2 in skip)
3. **Given** a player in cardless state from playing Jack(s), **When** their turn arrives, **Then** they automatically draw exactly one card and exit cardless state (regardless of how many Jacks were played)

---

### Edge Cases

- **Wrap-around in small games**: In a 2-player game, playing a single Jack skips the other player and returns to the current player
- **Multiple wrap-arounds**: In a 3-player game, playing 4 Jacks skips through the full turn order and continues (P1 → skip P2, P3, P1, P2 → lands on P3)
- **Jack as starting card**: Jack is excluded from valid starting cards (like other special cards 2, 3, 8, Queen, Ace). If Jack is the only remaining candidate after dealing cards, the selection continues until a valid regular card (4, 5, 6, 7, 9, 10) or King is found
- **Jack as last card - Cardless state**: Playing Jack(s) as the last card(s) in hand results in the player becoming cardless (not winning). The player must wait for their next turn to draw a card
- **Direction interaction**: Jack skip count respects the current direction (clockwise vs counter-clockwise set by King cards)
- **Cardless player interaction**: When calculating skips, cardless players waiting for their turn to draw are counted in the skip calculation

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow players to play a single Jack card when it matches the top card by suit OR rank
- **FR-002**: System MUST skip exactly one player in turn order when a single Jack is played
- **FR-003**: System MUST allow players to play multiple Jack cards as a combo when all cards are Jacks and at least one matches the top card
- **FR-004**: System MUST skip N players when N Jack cards are played in a combo
- **FR-005**: System MUST calculate skip count by wrapping around the player list when necessary (e.g., in a 3-player game, skipping 2 players from P1 goes to P3, then back to P1)
- **FR-006**: System MUST respect the current turn direction (clockwise/counter-clockwise) when calculating which players are skipped
- **FR-007**: System MUST update the top card to the last Jack played when Jack(s) are played
- **FR-008**: System MUST move Jack card(s) from player's hand to the played stack with proper order_index
- **FR-009**: System MUST reject Jack plays that don't match the top card by suit or rank
- **FR-010**: System MUST handle wrap-around scenarios correctly in games with fewer players than Jacks played (e.g., playing 4 Jacks in a 3-player game)
- **FR-011**: System MUST treat Jack cards as special cards (excluded from valid starting cards) in start card selection, along with other special cards (2, 3, 8, Queen, Ace)
- **FR-012**: System MUST transition player to cardless state when Jack(s) are played as the last card(s) in hand (Jack cannot be used to win the game)
- **FR-013**: System MUST skip N other players (not including the cardless player) when Jack(s) cause a player to enter cardless state
- **FR-014**: System MUST allow cardless player (from playing Jack) to draw exactly one card when their turn arrives, regardless of the number of Jacks played

### Key Entities

- **Jack Card**: A special card with rank "jack" and one of four suits (hearts, diamonds, clubs, spades). When played, causes turn skipping behavior.
- **Game Session**: Tracks current_turn_player_id and turn_direction, both of which are affected by Jack plays
- **Skip Calculation**: The logic that determines which player receives the turn after N Jacks are played, considering player count, current position, and direction

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a 3-player game, when a player plays 1 Jack, the turn advances 2 positions (skipping 1 player) in 100% of cases
- **SC-002**: When a player plays N Jacks in a combo, exactly N players are skipped in 100% of cases
- **SC-003**: Jack cards can only be played when they match the top card by suit or rank, with validation failures occurring for non-matching attempts
- **SC-004**: In a 2-player game, playing 1 Jack returns the turn to the same player in 100% of cases (skip count wraps around)
- **SC-005**: Players can successfully play Jack combos (2, 3, or 4 Jacks) with skip behavior multiplying correctly based on combo size
- **SC-006**: Jack skip calculations respect the current direction (clockwise/counter-clockwise) set by previous King plays

## Assumptions

- Jack cards follow the same combo rules as regular cards: all cards must be the same rank (all Jacks)
- The first Jack in a combo must match the top card, subsequent Jacks don't need independent validation
- Skip calculation counts all players in the game, including cardless players waiting to draw
- Jack plays do not affect the turn direction (only King cards toggle direction)
- Jack validation follows the same pattern as King: dedicated validation function in PlayValidator module
- Jack is excluded from valid starting cards (treated like other special cards: 2, 3, 8, Queen, Ace), only regular cards (4, 5, 6, 7, 9, 10) and King can be starting cards
- Maximum combo size is 4 Jacks (one of each suit)
- When calculating skips with wrap-around, the same player can be "skipped" multiple times if the combo size exceeds player count

## Clarifications

### Session 2025-11-08

- Q: Can Jack be played as the last card to win the game? → A: No, playing Jack(s) as the last card(s) results in the player becoming cardless (not winning). Jack cannot be used as a winning card.
- Q: Does the cardless player themselves count in the skip calculation, or do we skip N other players beyond the cardless player? → A: Skip N other players from cardless player's position (cardless player not counted in skip)
- Q: Can Jack appear as the initial card on the played stack when a game starts, or should it be excluded like other special cards? → A: Exclude Jack from starting cards (treat consistently with other special cards 2, 3, 8, Queen, Ace)
- Q: When the cardless player's turn comes back around (after the skips), do they draw exactly one card, or do they draw N cards (where N = number of Jacks they played)? → A: Draw exactly one card (standard cardless behavior)
- Q: Should Jack validation use the same pattern as King (with a dedicated validation function), or should Jack be handled differently in the validation logic? → A: Create dedicated `valid_jack_play?/2` function (consistent with King pattern)

### Session 2025-11-09

- Q: Should Jack be excluded from valid starting cards (like other special cards 2, 3, 8, Queen, Ace)? → A: Yes, exclude Jack from starting cards (treat consistently with other special cards)
