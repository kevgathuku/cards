# Feature Specification: Two Card Draw Penalty

**Feature Branch**: `009-two-card`  
**Created**: 2025-01-20  
**Status**: Draft  
**Input**: User description: "Implement the functionality for the '2' card. The '2' is a special card that forces the next player to draw 2 cards from the deck. To play a '2', it must match the suit or rank of the top card on the play pile. The effect can be blocked by playing an Ace or by playing another '2' (which transfers the burden to the next player). If multiple '2' cards are played in one turn from a hand, the effect is the same as playing a single '2' (not additive: 2x'2' = draw 2, not 4)."

## Clarifications

### Session 2025-11-15

- Q: When a player faces a '2' penalty and has no Ace or '2' to block it, should drawing be automatic or require user action? → A: Button required; no automatic draw (player must explicitly accept penalty).
- Q: When the "Accept Penalty" button is displayed, what should happen to other UI elements during the turn? → A: Keep cards clickable but show error message if player tries to play non-blocking card.
- Q: When a player clicks the "Accept Penalty" button and draws 2 cards, should there be visual feedback? → A: Show animation/transition as cards move from deck to hand.
- Q: When a player HAS blocking cards (Ace or '2'), should they see both the "Accept Penalty" button and their blocking cards as clickable? → A: Show both; player can choose to play blocking card OR accept penalty.
- Q: What text/label should appear on the "Accept Penalty" button? → A: "Draw 2 Cards".
- Q: After clicking "Draw 2 Cards" and drawing, should the game automatically advance to the next player? → A: Automatically advance to next player after animation completes.
- Q: Should the visual indicator showing "Draw 2 penalty active" remain visible during the draw animation? → A: Disappear when button is clicked (before drawing animation starts).
- Q: What should the error message say when trying to play a non-blocking card while penalty is active? → A: "Penalty Active. You must play blocking card or draw penalty cards".
- Q: When a 2 is blocked by an Ace, what card requirements apply to the subsequent play? → A: The subsequent play should match the suit or rank of the last 2 played before the Ace (the Ace sets this as the active requirement).

### Session 2025-11-14

- Q: When a player plays the '2' as their last card, what status should they enter? → A: The player should enter "cardless" status (hand empty), not just remain in "normal" status. This clarifies that playing '2' as the last card triggers cardless status entry, similar to King/Jack. Being cardless does NOT mean the player has won - the penalty still applies to the next player and the game continues. (Note: A winning cardless state exists conceptually but has not been implemented yet.)

### Session 2025-11-13

- Q: When a '2' is the starting card and the first player blocks with another '2', what happens? → A: '2' cards are not allowed as starting cards. The system must exclude rank '2' when selecting the starting card.
- Q: When a player facing a '2' penalty plays an Ace to block it, does the Ace need to match the suit/rank of the top card (the '2'), or can any Ace be played regardless? → A: Any Ace can be played regardless of suit (Ace ignores matching rules). When blocking a '2' penalty with an Ace, the player cannot request a suit. Instead, the suit or rank of the most recent '2' card becomes the active matching requirement for subsequent plays (next player must match either suit or rank of that '2').
- Q: When blocking a '2' penalty with another '2', does the blocking '2' card need to match the suit/rank of the top card (the original '2'), or can any '2' be played? → A: Any '2' can be played to block because the top card is always a '2' when facing a penalty, so any '2' matches by rank (standard matching rules apply).
- Q: When a player blocks a '2' penalty with an Ace, and the suit of the '2' becomes active, can the next player play any card matching that suit, or are there additional restrictions? → A: Any card matching the suit or rank of the blocked '2' can be played (normal matching rules apply based on the '2' as the reference card).
- Q: When a requested suit is already active (from a previous Ace play) and a player wants to play a '2' to create a penalty, must the '2' match the requested suit? → A: Yes, the '2' must match the requested suit (requested suit takes precedence over normal matching rules).
- Q: When both a '2' penalty AND a requested suit are active simultaneously, and a player blocks with another '2', what happens to the requested suit? → A: The requested suit is cleared when any valid card matching it is played (including when creating the initial '2' penalty). When blocking by playing another '2', the requested suit has already been cleared, so only the penalty transfers.
- Q: When a player is forced to draw 2 cards due to the penalty, should there be any UI indication (notification/message) to inform them why they're drawing, or does it happen silently? → A: Show a notification/message explaining the '2' penalty (e.g., "You must draw 2 cards due to [Player]'s '2' card").
- Q: When a player plays a '2' to create a penalty, should there be any visual indication on the game board that the next player must draw 2 cards (beyond just the notification)? → A: Yes, show a persistent visual indicator on the game board (e.g., badge/icon showing "Draw 2 penalty active").
- Q: When an Ace blocks a '2' penalty, does the player get to continue their turn after blocking, or does their turn end immediately? → A: The player's turn ends immediately after blocking with the Ace. They do NOT get to select a suit or play additional cards.
- Q: When a player blocks a '2' penalty with an Ace (and the '2's suit becomes active), and the next player successfully plays a card matching that suit, should the suit requirement be cleared? → A: Yes, clear the suit requirement immediately (consistent with normal Ace suit requirement behavior).
- Q: Is the '2' card allowed as a valid finishing card (last card played to win)? → A: No, the '2' card is not allowed as a valid finishing card. When a player plays the '2' as their last card, they become cardless but do not win; additional game logic must handle this scenario.
- Q: What happens when a player plays the '2' as their last card and becomes cardless? → A: The player enters "cardless" status (hand empty) and the penalty still applies to the next player. The player who played the last '2' becomes cardless, but the next player must draw 2 cards (or block) as normal. Being cardless does NOT mean the player has won the game - the game continues.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player plays a '2' card to force next player to draw (Priority: P1)

As a player, I want to play a '2' card during my turn to force the next player to draw 2 cards from the deck, giving me a strategic advantage.

**Why this priority**: This is the core functionality of the '2' card penalty mechanic and introduces the fundamental rule.

**Independent Test**: Can be tested by starting a game, giving a player a '2' card that matches the top card, having them play it, and verifying that the next player is forced to draw 2 cards.

**Acceptance Scenarios**:

1. **Given** the top card is a '7 of Hearts', **When** the current player plays a '2 of Hearts', **Then** the game state is updated to indicate the next player must draw 2 cards.
2. **Given** the top card is a '2 of Spades', **When** the current player plays a '2 of Diamonds', **Then** the game state is updated to indicate the next player must draw 2 cards (rank match).
3. **Given** the top card is a 'King of Clubs', **When** the current player attempts to play a '2 of Hearts', **Then** the play is rejected because the '2' does not match the suit or rank of the top card.
4. **Given** the current player plays a '2' and the next player has no blocking cards, **When** it becomes the next player's turn, **Then** they automatically draw 2 cards from the deck, their turn ends, and the draw penalty is cleared.

---

### User Story 2 - Next player blocks '2' penalty with an Ace (Priority: P2)

As the next player who is facing a '2' card penalty, I want to play an Ace to block the penalty and change the required suit, avoiding having to draw 2 cards.

**Why this priority**: This adds strategic depth by allowing players to defend against the '2' card using an Ace.

**Independent Test**: Following the test for P1, give the next player an Ace and verify they can play it to block the penalty and change the suit.

**Acceptance Scenarios**:

1. **Given** the previous player played a '2 of Hearts' and the current player must draw 2 cards, **When** the current player plays an Ace, **Then** the draw penalty is cleared, the player does not draw cards, and the next player must play a card matching the suit (Hearts) or rank (2) of the blocked '2'.
2. **Given** a '2' penalty is active, **When** the current player plays an Ace, **Then** the system does NOT prompt them to select a suit; instead, the suit or rank of the blocking '2' becomes the active matching requirement for subsequent plays.
3. **Given** the previous player played a '2 of Clubs', the current player blocks with an Ace, **When** it becomes the next player's turn, **Then** they must play a Club (matching suit) or any '2' (matching rank), or draw a card.

---

### User Story 3 - Next player blocks '2' penalty with another '2' (Priority: P2)

As the next player who is facing a '2' card penalty, I want to play another '2' card to transfer the penalty to the next player, avoiding having to draw cards myself.

**Why this priority**: This creates a chain reaction mechanic and adds tactical counterplay.

**Independent Test**: Following the test for P1, give the next player a '2' card and verify they can play it to transfer the penalty.

**Acceptance Scenarios**:

1. **Given** the previous player played a '2' and the current player must draw 2 cards, **When** the current player plays another '2', **Then** the draw penalty is transferred to the next player (they must draw 2 cards), and the current player does not draw any cards.
2. **Given** Player A plays a '2', Player B plays a '2', **When** it becomes Player C's turn and they have no Ace or '2', **Then** Player C must draw 2 cards and their turn ends.
3. **Given** the top card is a '2 of Hearts', **When** the current player facing a penalty plays a '2 of Clubs', **Then** the play is accepted because it matches rank, and the penalty is transferred to the next player.

---

### User Story 4 - Multiple '2' cards in one play have the same effect (Priority: P3)

As a player, when I play multiple '2' cards in a single turn, the effect should be the same as playing just one '2' card (the next player draws 2 cards, not 4 or more).

**Why this priority**: This clarifies the rule for combo plays and prevents the effect from becoming too powerful.

**Independent Test**: Give a player multiple '2' cards and verify that playing them together results in only a 2-card draw penalty.

**Acceptance Scenarios**:

1. **Given** the top card is a '2 of Hearts', **When** the current player plays a combo of '2 of Hearts' and '2 of Diamonds', **Then** the next player must draw 2 cards (not 4).
2. **Given** the top card is a '5 of Spades', **When** the current player plays three '2 of Spades' cards, **Then** the next player must draw 2 cards (not 6).

---

### User Story 5 - Player has no blocking cards and must accept penalty (Priority: P2)

As a player facing a '2' card penalty, if I have no Ace or '2' card to block it, I must click the "Draw 2 Cards" button to accept the penalty, draw 2 cards from the deck, and end my turn.

**Why this priority**: This enforces the penalty mechanism and ensures the rule is applied consistently while giving players explicit control.

**Independent Test**: Create a scenario where a player faces a '2' penalty with no blocking cards and verify they see the "Draw 2 Cards" button and can click it to draw cards.

**Acceptance Scenarios**:

1. **Given** the previous player played a '2' and the current player has no Ace or '2' cards, **When** it becomes the current player's turn, **Then** the normal "Draw" button is replaced with a "Draw 2 Cards" button, and clicking it causes them to draw 2 cards from the deck, shows a card-drawing animation, their turn ends automatically after the animation, and the draw penalty is cleared.
2. **Given** the previous player played a '2' and the current player has no blocking cards, **When** the current player attempts to play a non-blocking card, **Then** an error message "Penalty Active. You must play blocking card or draw penalty cards" is displayed.
3. **Given** a player clicks "Draw 2 Cards" but the deck has only 1 card, **When** the penalty is applied, **Then** the player draws the 1 available card, the played cards are recycled to form a new deck, and the player draws the second card from the new deck.
4. **Given** a player clicks "Draw 2 Cards" but the deck is empty and there are cards to recycle, **When** the penalty is applied, **Then** the played cards are recycled, and the player draws 2 cards from the new deck.
5. **Given** a '2' penalty is active, **When** the player clicks the "Draw 2 Cards" button, **Then** the visual indicator showing "Draw 2 penalty active" disappears immediately before the drawing animation starts.

---

### User Story 6 - Player with blocking cards chooses to accept penalty (Priority: P3)

As a player facing a '2' card penalty who has blocking cards (Ace or '2'), I want the option to click the "Draw 2 Cards" button instead of playing my blocking card, allowing me to save my valuable card for a better strategic moment.

**Why this priority**: This adds strategic depth by allowing players to make tactical decisions about when to use their blocking cards.

**Independent Test**: Create a scenario where a player has blocking cards and verify they can choose to either play them or click the "Draw 2 Cards" button.

**Acceptance Scenarios**:

1. **Given** the previous player played a '2' and the current player has an Ace, **When** it becomes the current player's turn, **Then** both the "Draw 2 Cards" button AND the Ace card are interactive/clickable, allowing the player to choose between blocking or accepting the penalty.
2. **Given** the previous player played a '2' and the current player has a '2' card, **When** the current player clicks the "Draw 2 Cards" button (instead of playing their '2'), **Then** they draw 2 cards, their turn ends, and the penalty is cleared (not transferred).
3. **Given** a '2' penalty is active and the player has blocking cards, **When** the player clicks the "Draw 2 Cards" button, **Then** the same behavior occurs as if they had no blocking cards (draw animation, turn ends, penalty cleared).

---

### Edge Cases

- What happens if a '2' is played as the very last card? The '2' card is NOT allowed as a valid finishing card. When a player plays the '2' as their last card, they enter "cardless" status (hand empty), but the penalty still applies to the next player, who must draw 2 cards (or block) as normal. Being cardless does NOT mean the player has won the game - the game continues.
- What happens if a '2' is selected as the starting card? '2' cards are NOT allowed as starting cards. The system must exclude rank '2' when selecting the starting card during game initialization.
- What happens if the draw deck is empty and a player needs to draw 2 cards? The played cards are recycled to form a new draw deck (keeping the top card on the play pile), and the player draws from the new deck.
- What happens if the draw deck has only 1 card and a player must draw 2? The player draws the 1 available card, the played cards are recycled, and they draw the second card from the new deck.
- What happens if a player must draw 2 cards, but the draw deck is empty and there are no cards in the play pile to recycle (only the top card remains)? The system should log this anomaly, the player draws 0 cards, and their turn is skipped.
- Can a player play a '2' even if they have other playable cards? Yes, a '2' can be played whenever it matches the suit or rank of the top card.
- What happens if a requested suit is active (from an Ace) and a player plays a '2'? The '2' must match the requested suit (if a suit is active) or can be any rank '2'. If it matches, the draw penalty is applied and the requested suit is cleared.
- What happens if a '2' penalty is active AND a requested suit is active? The blocking card (Ace or '2') must satisfy the requested suit requirement. If the player cannot play a card, they draw 2 cards and the requested suit persists.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow a player to play a '2' card during their turn only if it matches the suit or rank of the top card on the play pile.
- **FR-002**: Upon playing a '2', the system MUST update the game state to indicate the next player must draw 2 cards from the deck.
- **FR-003**: The system MUST allow the next player to block the '2' penalty by playing an Ace card (which clears the penalty and sets the suit or rank of the last '2' played as the active matching requirement for subsequent plays, WITHOUT prompting for suit selection) or by playing another '2' card (which transfers the penalty to the next player).
- **FR-004**: When a '2' penalty is active and it is a player's turn, the system MUST replace the normal "Draw" button with a "Draw 2 Cards" button that allows the player to explicitly accept the penalty.
- **FR-005**: When a player facing a '2' penalty clicks the "Draw 2 Cards" button, the system MUST: (a) make them draw 2 cards from the deck, (b) show animation/transition as cards move from deck to hand, (c) end their turn automatically after animation completes, (d) clear the draw penalty, and (e) advance to the next player.
- **FR-006**: When a '2' penalty is active, the system MUST keep cards in the player's hand clickable but MUST show the error message "Penalty Active. You must play blocking card or draw penalty cards" if the player attempts to play a non-blocking card (any card other than Ace or '2').
- **FR-007**: When a '2' penalty is active and the player HAS blocking cards (Ace or '2'), the system MUST display both the "Draw 2 Cards" button AND allow the player to click their blocking cards, giving them the choice to either block or accept the penalty.
- **FR-008**: When a player clicks the "Draw 2 Cards" button, the visual indicator showing "Draw 2 penalty active" (from FR-013) MUST disappear immediately (before the drawing animation starts).
- **FR-009**: When a player plays multiple '2' cards in a single turn (combo), the system MUST apply only a single 2-card draw penalty to the next player (not additive).
- **FR-010**: If a requested suit is active (from an Ace) and a player plays a '2', the '2' MUST match the requested suit to be valid. Playing a valid '2' MUST clear the requested suit requirement and apply the draw penalty.
- **FR-011**: If both a draw penalty and a requested suit are active, the blocking card (Ace or '2') MUST match the requested suit. If no valid card can be played, the player MUST click the "Draw 2 Cards" button to draw 2 cards, and the requested suit MUST persist.
- **FR-012**: When the draw deck has fewer than 2 cards and a player must draw 2, the system MUST: (a) draw available cards, (b) recycle the play pile (keeping the top card), (c) draw remaining cards from the new deck.
- **FR-013**: If the draw deck is empty and there are no cards to recycle (only the top card remains on the play pile), the system MUST log this anomaly, the player draws 0 cards, and their turn is skipped.
- **FR-014**: The system MUST exclude rank '2' cards when selecting the starting card during game initialization.
- **FR-015**: When a player is forced to draw 2 cards due to a '2' penalty, the system MUST display a notification/message explaining the reason (e.g., "You must draw 2 cards due to [Player]'s '2' card").
- **FR-016**: When a '2' penalty is active, the system MUST display a persistent visual indicator on the game board visible to all players (e.g., badge/icon showing "Draw 2 penalty active").

### Key Entities *(include if feature involves data)*

- **Game**: Represents the overall state of the card game, including the current player, the deck, the pile, and special game state rules (like a draw penalty or requested suit).
- **Player**: Represents a participant in the game, holding a hand of cards.
- **Card**: Represents a playing card, with a suit and a rank (e.g., 2 of Hearts).
- **DrawPenalty**: Represents the active state where the next player must draw a specific number of cards (in this case, 2).

### State Persistence Requirements *(mandatory if feature involves state)*

- **SPR-001**: All game state critical for continuity (e.g., player hands, turn, scores, active penalties) MUST be persisted in the database.
- **SPR-002**: Player progress MUST be recoverable after unexpected disconnections or client changes.


## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of '2' card plays correctly apply the 2-card draw penalty to the next player.
- **SC-002**: 100% of Ace or '2' card plays correctly block or transfer the draw penalty.
- **SC-003**: When multiple '2' cards are played in one turn, the penalty is correctly limited to 2 cards (not additive).
- **SC-004**: The system correctly handles edge cases where the draw deck has fewer than 2 cards by recycling the play pile and completing the draw.
- **SC-005**: 100% of penalty scenarios correctly display the "Draw 2 Cards" button instead of the normal "Draw" button when a '2' penalty is active.
- **SC-006**: The "Draw 2 Cards" button correctly triggers card drawing animation, ends the player's turn automatically, and clears the penalty indicator.
- **SC-007**: Players with blocking cards can successfully choose to either play blocking cards OR click "Draw 2 Cards" to accept the penalty.
- **SC-008**: User session recordings show that players successfully use the '2' card to penalize opponents and use blocking cards (Ace or '2') without errors.

## Assumptions

- The '2' card must match the suit or rank of the top card to be played (standard matching rules apply).
- An Ace card can block a '2' penalty at any time, regardless of the Ace's suit. When an Ace blocks a '2' penalty, it does NOT trigger suit selection; instead, the suit or rank of the most recent '2' card becomes the active matching requirement for subsequent plays (next player must match either suit or rank of that '2').
- Another '2' card can block a '2' penalty by transferring it to the next player (the penalty remains 2 cards, not cumulative).
- When a player successfully blocks a '2' penalty with another '2', the blocking '2' becomes the new top card and the penalty is transferred (not cleared).
- When a player blocks a '2' penalty with an Ace, the penalty is cleared entirely (not transferred).
- When a '2' penalty is active, the normal "Draw" button is replaced with a "Draw 2 Cards" button, requiring explicit user action to accept the penalty.
- Players facing a '2' penalty can choose to click the "Draw 2 Cards" button even if they have blocking cards (Ace or '2'), allowing strategic decisions about when to use blocking cards.
- After a player clicks "Draw 2 Cards" and draws the penalty cards, their turn ends automatically after the drawing animation completes. They cannot play any of the drawn cards in the same turn.
- If a requested suit is active (from a previous Ace), the '2' card must match that suit to be played. Playing a valid '2' clears the requested suit and applies the draw penalty.
