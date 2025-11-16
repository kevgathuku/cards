# Requirements Document: Three Card Draw Penalty

## Introduction

This feature implements the "3 card" special card mechanic for the Kadi card game. The 3 card forces the next player to draw 3 cards from the deck as a penalty. Similar to the 2 card, this penalty can be blocked by playing an Ace or another 3 card, which transfers the penalty to the next player. When multiple 3 cards are played in a single turn, the effect is not cumulative - the penalty remains 3 cards regardless of how many 3s are played together.

## Glossary

- **Game System**: The Kadi multiplayer card game platform
- **Player**: A participant in an active game session
- **Three Card**: A playing card with rank "3" (any suit)
- **Draw Penalty**: A game state requiring a player to draw a specific number of cards
- **Blocking Card**: An Ace or another 3 card that can prevent or transfer a 3 card draw penalty (note: 2 cards and 3 cards are not compatible - a 2 cannot block a 3 penalty and vice versa)
- **Top Card**: The most recently played card on the play pile
- **Play Pile**: The stack of cards that have been played during the game
- **Draw Deck**: The stack of unplayed cards available for drawing
- **Requested Suit**: An active suit requirement set by a previously played Ace
- **Matching Rules**: Standard game rules requiring played cards to match the suit or rank of the top card

## Requirements

### Requirement 1

**User Story:** As a player, I want to play a 3 card during my turn to force the next player to draw 3 cards from the deck, giving me a strategic advantage.

#### Acceptance Criteria

1. WHEN a Player plays a Three Card that matches the suit or rank of the Top Card, THE Game System SHALL update the game state to indicate a Draw Penalty of 3 cards for the next Player
2. WHEN a Player attempts to play a Three Card that does not match the suit or rank of the Top Card, THE Game System SHALL reject the play
3. WHEN a Draw Penalty of 3 cards is active and the next Player has no Blocking Card, THE Game System SHALL display a "Draw 3 Cards" button to the Player
4. WHEN a Player clicks the "Draw 3 Cards" button, THE Game System SHALL draw 3 cards from the Draw Deck to the Player's hand, display a card-drawing animation, end the Player's turn automatically after animation completion, clear the Draw Penalty, and advance to the next Player

### Requirement 2

**User Story:** As a player facing a 3 card penalty, I want to play an Ace to block the penalty and avoid drawing 3 cards.

#### Acceptance Criteria

1. WHEN a Draw Penalty of 3 cards is active and a Player plays an Ace, THE Game System SHALL clear the Draw Penalty and set the suit or rank of the most recent Three Card as the active Matching Rules requirement
2. WHEN a Player blocks a Draw Penalty with an Ace, THE Game System SHALL NOT prompt the Player to select a suit
3. WHEN an Ace blocks a Draw Penalty and the next Player plays a card matching the suit or rank of the blocked Three Card, THE Game System SHALL clear the suit requirement
4. WHEN a Player plays an Ace to block a Draw Penalty, THE Game System SHALL end the Player's turn immediately without allowing additional card plays

### Requirement 3

**User Story:** As a player facing a 3 card penalty, I want to play another 3 card to transfer the penalty to the next player, avoiding drawing cards myself.

#### Acceptance Criteria

1. WHEN a Draw Penalty of 3 cards is active and a Player plays another Three Card, THE Game System SHALL transfer the Draw Penalty to the next Player
2. WHEN a Player blocks a Draw Penalty with a Three Card, THE Game System SHALL NOT increase the penalty amount (penalty remains 3 cards)
3. WHEN a Three Card blocks a Draw Penalty, THE Game System SHALL set the blocking Three Card as the new Top Card
4. WHEN a Player plays a Three Card to block, THE Game System SHALL accept any Three Card regardless of suit because the Top Card is always a Three Card when facing a penalty

### Requirement 4

**User Story:** As a player, when I play multiple 3 cards in a single turn, the effect should be the same as playing just one 3 card (the next player draws 3 cards, not 6 or more).

#### Acceptance Criteria

1. WHEN a Player plays multiple Three Cards in a single turn, THE Game System SHALL apply only a single Draw Penalty of 3 cards to the next Player
2. WHEN a Player plays two Three Cards together, THE Game System SHALL NOT create a Draw Penalty of 6 cards
3. WHEN a Player plays three or more Three Cards together, THE Game System SHALL apply the same Draw Penalty of 3 cards as playing a single Three Card

### Requirement 5

**User Story:** As a player facing a 3 card penalty with blocking cards available, I want the option to either play my blocking card or accept the penalty, allowing me to make strategic decisions.

#### Acceptance Criteria

1. WHEN a Draw Penalty of 3 cards is active and a Player has Blocking Cards, THE Game System SHALL display both the "Draw 3 Cards" button and make the Blocking Cards clickable
2. WHEN a Player with Blocking Cards clicks the "Draw 3 Cards" button, THE Game System SHALL draw 3 cards, end the Player's turn, and clear the Draw Penalty
3. WHEN a Draw Penalty is active and a Player attempts to play a non-Blocking Card (including a 2 card, which cannot block a 3 card penalty), THE Game System SHALL display the error message "Penalty Active. You must play blocking card or draw penalty cards"
4. WHEN a Player clicks the "Draw 3 Cards" button, THE Game System SHALL remove the visual penalty indicator immediately before the drawing animation starts

### Requirement 6

**User Story:** As a player, I need the system to handle edge cases correctly when the draw deck has insufficient cards for the 3 card penalty.

#### Acceptance Criteria

1. WHEN a Player must draw 3 cards and the Draw Deck has fewer than 3 cards, THE Game System SHALL draw available cards, recycle the Play Pile (keeping the Top Card), and draw remaining cards from the new Draw Deck
2. WHEN a Player must draw 3 cards and the Draw Deck is empty with cards available to recycle, THE Game System SHALL recycle the Play Pile and draw 3 cards from the new Draw Deck
3. WHEN a Player must draw 3 cards and the Draw Deck is empty with no cards to recycle, THE Game System SHALL log the anomaly, draw 0 cards, and skip the Player's turn
4. IF a Requested Suit is active and a Player plays a Three Card, THE Game System SHALL require the Three Card to match the Requested Suit, clear the Requested Suit upon valid play, and apply the Draw Penalty

### Requirement 7

**User Story:** As a player, I need clear visual feedback when a 3 card penalty is active so I understand the game state.

#### Acceptance Criteria

1. WHEN a Three Card is played, THE Game System SHALL display a persistent visual indicator on the game board showing "Draw 3 penalty active"
2. WHEN a Player is forced to draw 3 cards, THE Game System SHALL display a notification message explaining the reason (e.g., "You must draw 3 cards due to [Player]'s 3 card")
3. WHEN a Draw Penalty is cleared or transferred, THE Game System SHALL update or remove the visual indicator accordingly
4. WHEN the "Draw 3 Cards" button is displayed, THE Game System SHALL show animation/transition as cards move from the Draw Deck to the Player's hand

### Requirement 8

**User Story:** As a player, I need the system to enforce that 2 cards and 3 cards are not compatible for blocking penalties, so the game rules are clear and consistent.

#### Acceptance Criteria

1. WHEN a Draw Penalty of 3 cards is active and a Player attempts to play a 2 card (even if it matches the suit or rank), THE Game System SHALL reject the play and display an error message
2. WHEN a Draw Penalty of 2 cards is active and a Player attempts to play a 3 card (even if it matches the suit or rank), THE Game System SHALL reject the play and display an error message
3. WHEN a Three Card Draw Penalty is active, THE Game System SHALL only accept Ace cards or other Three Cards as Blocking Cards
4. WHEN a 2 card Draw Penalty is active, THE Game System SHALL only accept Ace cards or other 2 cards as Blocking Cards

### Requirement 9

**User Story:** As a game administrator, I need the system to prevent 3 cards from being selected as the starting card to avoid immediate penalties at game start.

#### Acceptance Criteria

1. WHEN the Game System selects a starting card during game initialization, THE Game System SHALL exclude all Three Cards (and 2 cards) from the selection pool
2. WHEN a game starts, THE Game System SHALL ensure the Top Card is never a Three Card
3. IF a Three Card is played as a Player's last card, THE Game System SHALL set the Player's status to "cardless" and apply the Draw Penalty to the next Player
