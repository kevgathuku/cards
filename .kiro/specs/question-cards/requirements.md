# Requirements Document: Question Cards (Q and 8)

## Introduction

This feature introduces question card mechanics for Q (Queen) and 8 cards in the Kadi card game. Question cards prompt the player to draw a card immediately after playing them, unless they include an answer card in the same play. This creates strategic gameplay opportunities where players can build combos with question cards followed by answer cards.

## Glossary

- **Question Card**: A Q (Queen) or 8 card that prompts the player to draw unless answered in the same play
- **Answer Card**: Any non-question card that matches the suit of the last question card, played in the same combo
- **Question Combo**: Multiple Q or 8 cards played together, optionally followed by an answer card in the same play
- **Complete Play**: A play containing question cards followed by an answer card (e.g., 8H 8D 2D)
- **Incomplete Play**: A play containing only question cards without an answer, prompting the player to draw
- **System**: The Kadi card game application
- **Player**: A user participating in a game session
- **Valid Answer Card**: Any non-question card that matches the suit of the last question card, including regular cards, penalty cards (2, 3), and special cards (Ace, Jack, King)

## Requirements

### Requirement 1: Question Card with Answer in Same Play

**User Story:** As a player, I want to play a Q or 8 card with an answer in the same play, so that I can play strategic card combinations efficiently.

#### Acceptance Criteria

1. WHEN a player plays Q or 8 cards followed by an answer card in the same play, THE System SHALL validate the entire combo as one play
2. WHEN a player plays a complete question combo (e.g., 8H 8D 2D), THE System SHALL move all cards to the played pile
3. WHEN a player plays a complete question combo, THE System SHALL advance the turn to the next player
4. WHEN a player plays a complete question combo, THE System SHALL apply any special effects from the answer card (e.g., penalty from 2 or 3)
5. WHEN a player plays a complete question combo, THE System SHALL NOT prompt the player to draw

### Requirement 2: Question Card without Answer Prompts Draw

**User Story:** As a player who played a question card without an answer, I want to be prompted to draw a card, so that I complete the question requirement.

#### Acceptance Criteria

1. WHEN a player plays only Q or 8 cards without an answer card, THE System SHALL prompt the player to draw a card
2. WHEN the player is prompted to draw, THE System SHALL display a "Draw Card (Answer Question)" button
3. WHEN the player clicks the draw button, THE System SHALL draw one card from the deck to the player's hand
4. WHEN the player draws a card, THE System SHALL advance the turn to the next player
5. WHEN the deck is empty and the player must draw, THE System SHALL recycle the played stack before drawing

### Requirement 3: Answer Card Validation

**User Story:** As a player, I want to include an answer card with my question cards, so that I can avoid drawing.

#### Acceptance Criteria

1. WHEN a player includes an answer card after question cards, THE System SHALL validate the answer matches the suit or rank of the last question card
2. WHEN validating an answer card, THE System SHALL allow regular cards (4, 5, 6, 7, 9, 10) that match the suit or rank
3. WHEN validating an answer card, THE System SHALL allow penalty cards (2, 3) that match the suit or rank
4. WHEN validating an answer card, THE System SHALL allow special cards (Ace, Jack, King) that match the suit or rank
5. WHEN a player includes a Q or 8 after question cards, THE System SHALL treat it as another question card (not an answer)

### Requirement 4: Multiple Question Cards in Combo

**User Story:** As a player, I want to play multiple question cards together, so that I can build strategic combos.

#### Acceptance Criteria

1. WHEN a player plays multiple Q or 8 cards together, THE System SHALL validate that each subsequent card matches the previous card by suit or rank
2. WHEN a player plays multiple question cards, THE System SHALL use the suit of the last question card for answer validation
3. WHEN a player plays mixed Q and 8 cards together (e.g., 8H QH QD 8D), THE System SHALL validate each card matches the previous by suit or rank
4. WHEN a player plays multiple question cards without an answer, THE System SHALL prompt the player to draw once
5. WHEN a player plays multiple question cards with an answer, THE System SHALL validate the answer against the last question card's suit

### Requirement 5: Special Card Answer Effects

**User Story:** As a player, I want to use special cards as answers to question cards, so that I can trigger their effects.

#### Acceptance Criteria

1. WHEN a player plays question cards with an Ace as the answer, THE System SHALL trigger suit selection after the play
2. WHEN a player plays question cards with a 2 as the answer, THE System SHALL activate the draw penalty for the next player
3. WHEN a player plays question cards with a 3 as the answer, THE System SHALL activate the draw penalty for the next player
4. WHEN a player plays question cards with a Jack as the answer, THE System SHALL trigger the skip effect
5. WHEN a player plays question cards with a King as the answer, THE System SHALL trigger the direction reversal

### Requirement 6: Question Card Combos with Answer Combos

**User Story:** As a player, I want to play multiple Q or 8 cards together with multiple answer cards, so that I can use combos strategically.

#### Acceptance Criteria

1. WHEN a player plays multiple Q or 8 cards followed by answer cards, THE System SHALL validate the question cards match each other by suit or rank
2. WHEN a player plays question cards followed by multiple answer cards (e.g., 8H 8D 4D 4H), THE System SHALL validate the answer cards form a valid combo
3. WHEN a player plays question cards followed by answer cards, THE System SHALL validate the first answer card matches the suit or rank of the last question card
4. WHEN a player plays question cards followed by answer cards, THE System SHALL validate all answer cards have the same rank
5. WHEN a player plays question cards with answer cards, THE System SHALL process the entire play as one action and advance the turn

### Requirement 7: Question Card Combo Validation

**User Story:** As a player, I want to play question cards in combos with answers, so that I can make efficient plays.

#### Acceptance Criteria

1. WHEN a player plays a combo starting with Q or 8 cards, THE System SHALL validate that question cards form a valid sequence
2. WHEN a player plays Q or 8 cards followed by a non-question card, THE System SHALL treat the non-question card as the answer
3. WHEN a player plays a combo like "8H 8D 2D", THE System SHALL validate 8H and 8D as questions and 2D as the answer
4. WHEN a player plays a combo with an answer, THE System SHALL validate the answer matches the suit of the last question card
5. WHEN a player plays only question cards without an answer, THE System SHALL activate question_active state

### Requirement 8: Starting Card Exclusion

**User Story:** As a player starting a new game, I expect Q and 8 cards to be excluded from starting card selection, so that the game begins with a simple card.

#### Acceptance Criteria

1. WHEN the System selects a starting card for a new game, THE System SHALL exclude Q cards from selection
2. WHEN the System selects a starting card for a new game, THE System SHALL exclude 8 cards from selection
3. WHEN the System selects a starting card, THE System SHALL only choose from regular cards (4, 5, 6, 7, 9, 10)

### Requirement 9: Last Card Handling

**User Story:** As a player, I want to be able to play a Q or 8 as my last card, so that I can attempt to win strategically.

#### Acceptance Criteria

1. WHEN a player plays a Q or 8 as their last card without an answer, THE System SHALL prompt the player to draw
2. WHEN a player draws after playing their last card, THE System SHALL remove the player from "cardless" status
3. WHEN a player plays a Q or 8 with an answer as their last cards, THE System SHALL allow the play as valid
4. WHEN a player plays a Q or 8 with an answer as their last cards, THE System SHALL advance the turn to the next player
5. WHEN a player plays a Q or 8 as their last card and draws, THE System SHALL advance the turn to the next player

Note: Game finishing functionality (declaring a winner when a player has no cards) is out of scope for this feature.

### Requirement 10: Invalid Combo Rejection

**User Story:** As a player, I expect invalid question card combos to be rejected, so that the game rules are enforced.

#### Acceptance Criteria

1. WHEN a player attempts to play question cards with an answer that doesn't match the suit or rank, THE System SHALL reject the play with an error message
2. WHEN a player attempts to play question cards that don't match the top card, THE System SHALL reject the play
3. WHEN a player is prompted to draw and attempts to play cards instead, THE System SHALL reject the play
4. WHEN an invalid combo is rejected, THE System SHALL display an appropriate error message
5. WHEN a player plays question cards ending with Q or 8, THE System SHALL treat the entire play as questions and prompt to draw

### Requirement 11: Visual Indicators

**User Story:** As a player, I want clear visual indicators when I need to draw after playing a question card, so that I understand what to do.

#### Acceptance Criteria

1. WHEN a player plays question cards without an answer, THE System SHALL display a "Draw Card (Answer Question)" button
2. WHEN the draw button is displayed, THE System SHALL show a message indicating the player must draw
3. WHEN the player draws the card, THE System SHALL remove the draw button
4. WHEN the player draws the card, THE System SHALL advance the turn normally
5. WHEN a player plays question cards with an answer, THE System SHALL NOT display the draw button

### Requirement 12: Next Player Plays Normally

**User Story:** As the next player after a question card was played, I want to play normally, so that the game flow is simple.

#### Acceptance Criteria

1. WHEN a player plays question cards and draws, THE System SHALL advance the turn to the next player
2. WHEN it is the next player's turn after a question card, THE System SHALL allow normal card matching (suit or rank)
3. WHEN the next player plays a card, THE System SHALL validate against the last question card played (now the top card)
4. WHEN the next player plays a card, THE System SHALL NOT apply any special question card rules
5. WHEN the next player plays an Ace, THE System SHALL allow it regardless of the top card suit or rank

### Requirement 13: Integration with Existing Features

**User Story:** As a player, I expect question cards to work seamlessly with existing game features, so that gameplay is consistent.

#### Acceptance Criteria

1. WHEN a player uses a King card as an answer to question cards, THE System SHALL reverse direction and advance the turn
2. WHEN a player uses a Jack card as an answer to question cards, THE System SHALL skip the next player and advance the turn
3. WHEN a player uses an Ace as an answer to question cards, THE System SHALL trigger suit selection
4. WHEN a player uses a penalty card (2 or 3) as an answer to question cards, THE System SHALL activate the penalty for the next player
5. WHEN deck exhaustion occurs during question draw, THE System SHALL recycle the played stack before drawing
