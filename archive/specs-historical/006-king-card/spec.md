# Feature Specification: King Card Reversal (Kickback)

**Feature Branch**: `006-king-card`  
**Created**: 2025-11-07  
**Status**: Draft  
**Input**: User description: "implement the functionality for cards with the K / King. In this game, they mean kickback. These are the rules: The K card played has to match the suit or number of the last played card in the played stack. The K card reverses the direction of the game when played. If the game direction was clockwise, it becomes anticlockwise and vice versa. For now it can only be played one at a time. It is not valid to play 2 separate K cards in one hand. In the edge case of a 2 player game, playing the K card has no real impact on the direction of the gameplay. The turn advances to the next player as normal and the game direction continues as normal"

## Clarifications

### Session 2025-11-07

- Q: What should happen if a player cannot play any King card (none match) AND the deck is empty (no cards to draw)? → A: Game triggers deck recycling from played stack automatically
- Q: When a player plays a King as their last card and wins, does the direction reversal still take effect for the game record/history, or is it skipped since the game ends immediately? → A: Direction reverses and the player doesn't win but goes into a special state - cardless. They can draw a card when their turn comes up again
- Q: When a cardless player's turn comes up, are they REQUIRED to draw (automatic), or can they choose to draw or remain cardless? → A: Must draw automatically (no choice)
- Q: After a King is played and direction reverses, can the very next player (now in the reversed direction) immediately play another King card? → A: Yes, if it matches the last played card
- Q: After a cardless player automatically draws a card, can they play that card immediately on the same turn, or does their turn end after the draw? → A: Turn ends after draw (play next turn)
- Q: When deck recycling occurs, does the most recently played King card remain as the "current card" on top of the played stack, or does it get shuffled back into the deck? → A: King remains on top (not recycled)
- Q: Can multiple players be in "cardless" state simultaneously, or does entering cardless state trigger an immediate win check? → A: Yes, multiple cardless players allowed
- Q: In a 2-player game, if one player is cardless and the other player is in normal play, does the cardless player's automatic draw still occur on their turn, or does the game have special handling? → A: Cardless draw works same as multi-player
## Clarifications

### Session 2025-11-06

- Q: If a King somehow becomes the start card (e.g., due to a bug or future rule change), should the system actively prevent it or handle it gracefully? → A: Allow it (no direction change on start)
- **Update (2025-11-08)**: This clarification has been implemented. Kings are now explicitly allowed as start cards in `select_start_card/1`. The original feature 001-deal-start-card has been updated to reflect this change.
- Q: After recycling, if no drawable cards remain (extremely unlikely), what happens to the player required to draw? → A: Log anomaly and skip (pass turn)
- Q: For the rare case where, after recycling, no drawable cards remain and the player is skipped, what player-facing notification should be shown? → A: Non-blocking info banner to all players: "Deck exhausted. Skipping <Player> this turn."
- Q: What level of event logging granularity should we use for King-related actions and anomalies? → A: Structured events: direction_change, cardless_entered, anomaly_skip with metadata (game_id, player_id, timestamp, context)
- Q: How should the direction change be communicated in the UI when a King is played? → A: Ephemeral toast + persistent indicator update (arrow/text)
- Q: What accessibility design should the persistent direction indicator follow? → A: Icon + text label ("Clockwise"/"Counter-clockwise") with WCAG AA contrast
- Q: What localization approach should we take for new King-related user-facing strings (direction toast, anomaly banner)? → A: Add i18n keys now; ship English-only initially
- Q: PII policy for King feature operational events? → A: IDs only; no PII (no names/emails)
- Q: How should we rate-limit notifications for rapid consecutive direction changes (multiple Kings quickly)? → A: Coalesce within 2s window (single toast updated)
- Q: Should the cardless representation remain a boolean or evolve into a player status enum for future extensibility? → A: Use status enum ("normal","cardless") persisted on game_session_players
- Q: Will this feature expose an external HTTP API, or is LiveView the only client? → A: LiveView only; no external API planned

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Play King Card to Reverse Game Direction (Priority: P1)

A player wants to play a King card from their hand to reverse the turn order, making the game flow in the opposite direction from the current play direction.

**Why this priority**: This is the core mechanic of the King card feature - the ability to reverse game direction. Without this, the King card would have no special behavior and would be just like a regular card.

**Independent Test**: Can be fully tested by having a player play a King card during their turn and verifying that the turn order reverses, delivering immediate tactical gameplay value for players wanting to disrupt turn flow.

**Acceptance Scenarios**:

1. **Given** a game with 4 players (Player A, B, C, D) in clockwise order and Player B has a King of Hearts in their hand, **When** Player B plays the King of Hearts on their turn (and it matches the last played card's suit or rank), **Then** the game direction reverses to counter-clockwise and Player A becomes the next player (instead of Player C)

2. **Given** a game in counter-clockwise direction and Player C has a King of Spades, **When** Player C plays the King of Spades (matching the last played card), **Then** the game direction reverses to clockwise and the next player after Player C in clockwise order gets the next turn

3. **Given** a 2-player game (Player A and Player B) and Player A has a King card, **When** Player A plays the King card, **Then** the turn advances to Player B as normal (direction reversal has no practical effect with only 2 players)

4. **Given** Player D plays a King card as their last card, **When** Player D's turn comes around again, **Then** Player D automatically draws one card from the deck, enters normal play state, and their turn ends (they cannot play the drawn card immediately)

---

### User Story 2 - King Card Validation (Priority: P1)

The system must validate that a King card can only be played when it matches the suit or rank of the last played card, and only one King can be played at a time.

**Why this priority**: Validation is critical to maintain game rule integrity. Without proper validation, players could cheat or the game could enter invalid states.

**Independent Test**: Can be fully tested by attempting to play King cards in various valid and invalid scenarios and verifying the system accepts or rejects them appropriately, ensuring game rules are enforced correctly.

**Acceptance Scenarios**:

1. **Given** the last played card is a 5 of Hearts and a player has a King of Hearts, **When** the player attempts to play the King of Hearts, **Then** the play is accepted (suits match) and the direction reverses

2. **Given** the last played card is a King of Diamonds and a player has a King of Clubs, **When** the player attempts to play the King of Clubs, **Then** the play is accepted (ranks match) and the direction reverses

3. **Given** the last played card is a 7 of Spades and a player has a King of Hearts, **When** the player attempts to play the King of Hearts, **Then** the play is rejected with an error message (neither suit nor rank matches)

4. **Given** a player has two King cards in their hand, **When** the player attempts to play both King cards in a single turn, **Then** the play is rejected with an error message (only one King allowed per turn)

---

### User Story 3 - Track Game Direction State (Priority: P2)

The system must maintain and expose the current game direction state so players and observers can understand the flow of turns.

**Why this priority**: While direction tracking is necessary for the feature to work, it's a supporting requirement rather than directly user-facing. The primary value is in the reversal mechanic itself.

**Independent Test**: Can be fully tested by starting a game, playing King cards, and querying the game state to verify the direction is correctly stored and updated, providing visibility into the game flow state.

**Acceptance Scenarios**:

1. **Given** a new game is started, **When** the game state is queried, **Then** the default direction is clockwise

2. **Given** a game in clockwise direction, **When** a player plays a King card, **Then** the game direction changes to counter-clockwise and this is reflected in the game state

3. **Given** a game in counter-clockwise direction, **When** a player plays another King card, **Then** the game direction changes back to clockwise

---

### Edge Cases

- What happens when a King is the first card in the played stack (start card)? **Updated as of 2025-11-08**: Kings are now ALLOWED as start cards. When a King is the start card, it does NOT trigger a direction reversal. The game starts in default clockwise direction and the King acts as a normal reference card for matching. This change modifies the original feature 001-deal-start-card specification to allow Kings in the start card selection pool.
- What happens when a player plays a King as their last card? The direction reverses and the player enters a "cardless" state (does NOT win). When their turn comes around again, they automatically draw a card from the deck (no choice), and their turn ends immediately after the draw
- What happens if a cardless player draws another King card? Their turn ends after the draw. On their next turn, they can play the King if it matches the last played card (normal rules apply)
- What happens if multiple Kings are played in consecutive turns? Each King reverses the direction, so the direction toggles with each King played. The next player can immediately play another King if it matches the last played card (no waiting period or restrictions)
- How does the system calculate the next player in a 2-player game when a King is played? The turn simply advances to the other player (direction reversal has no practical effect). Cardless state mechanics work identically in 2-player games as in multi-player games
- What happens when a player has only King cards remaining and none match the last played card? The player must draw a card (standard game rules apply). If the deck is empty, the system automatically triggers deck recycling from the played stack before the draw
- What happens during deck recycling if the last played card is a King? The King remains on top of the played stack as the current reference card (it is not shuffled back into the deck). All other cards from the played stack are shuffled to form the new deck
- Can multiple players be in "cardless" state at the same time? Yes, multiple players can be cardless simultaneously. Each cardless player will automatically draw a card when their turn comes around
- What happens if, after recycling, no cards are available to draw (only the top reference card remains)? System logs an anomaly and the affected player’s turn is skipped (pass) to avoid deadlock
- What UX should accompany the rare post-recycle no-draw scenario? Show a non-blocking info banner to all players: "Deck exhausted. Skipping <Player> this turn."
- When multiple Kings are played in quick succession, show a single coalesced toast updated within a 2s window while the persistent direction indicator updates on every change

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow a player to play a King card during their turn if the King's suit OR rank matches the last played card in the played stack
- **FR-002**: System MUST reverse the game direction (clockwise ↔ counter-clockwise) immediately when a King card is successfully played
- **FR-003**: System MUST NOT reverse direction if a King card is the start card (first card in played stack)
- **FR-004**: System MUST reject attempts to play a King card when it does not match the suit or rank of the last played card
- **FR-005**: System MUST reject attempts to play multiple King cards in a single turn
- **FR-006**: System MUST persist the current game direction state (clockwise or counter-clockwise) as part of the game session data
- **FR-007**: System MUST initialize new games with a default direction of clockwise
- **FR-008**: System MUST calculate the next player based on the current direction after a King card reverses it
- **FR-009**: System MUST handle King card plays in 2-player games by advancing the turn normally without direction change effect (since there are only 2 players)
- **FR-010**: System MUST allow King cards to be played as the last card in a player's hand, but the player enters a "cardless" state instead of winning
- **FR-011**: System MUST place a player in "cardless" state when they play their last card and it is a King card
- **FR-012**: System MUST automatically draw a card for a cardless player when their turn comes around again (no player choice involved)
- **FR-013**: System MUST end a cardless player's turn immediately after they draw a card (they cannot play the drawn card on the same turn)
- **FR-014**: System MUST allow multiple players to be in "cardless" state simultaneously (no automatic win triggered)
- **FR-015**: System MUST broadcast the direction change to all players in the game session when a King is played
- **FR-016**: System MUST automatically trigger deck recycling from the played stack when a player needs to draw a card but the deck is empty
- **FR-017**: System MUST preserve the top card of the played stack (including King cards) during deck recycling and shuffle only the remaining cards to form the new deck
- **FR-018**: System MUST, if after recycling no drawable cards exist (only immutable top card remains), log an anomaly event and skip (pass) the current player's draw action, advancing turn as normal
- **FR-019**: System MUST display a non-blocking info banner to all players when the post-recycle no-draw anomaly occurs, with text: "Deck exhausted. Skipping <Player> this turn."
- **FR-020**: System MUST emit structured operational events for King-related actions with metadata: 
	- direction_change: {game_id, player_id, previous_direction, new_direction, card_id, timestamp}
	- cardless_entered: {game_id, player_id, reason: "king_last_card", card_id, timestamp}
	- anomaly_skip: {game_id, player_id, deck_state, timestamp}
	Events MUST be logged in a structured format suitable for analytics and debugging
- **FR-021**: System MUST display an ephemeral toast (non-blocking) announcing the direction change (e.g., "Direction reversed: now counter-clockwise") AND update a persistent UI indicator (icon/arrow + text) within the same update cycle (<1s)
- **FR-022**: The persistent direction indicator MUST be accessible: include both icon and visible text label ("Clockwise" / "Counter-clockwise"), avoid color-only cues, meet WCAG 2.1 AA contrast, and expose an accurate accessible name/aria-label for screen readers
- **FR-023**: All new user-facing strings for this feature (direction toast text, anomaly banner, direction indicator labels) MUST use i18n keys with English default translations; infrastructure MUST allow later locale additions without code changes
- **FR-024**: Structured King feature events MUST NOT include personally identifiable information beyond stable internal IDs (player_id, game_id, card_id). No player names/emails/usernames in logs. Adding new identity fields requires privacy review.
- **FR-025**: Notification rate limiting: Coalesce rapid direction changes within a 2s window into a single (updated) toast; update the persistent direction indicator on every change; if changes continue, extend/refresh the toast within the window; changes outside the window produce a new toast
- **FR-026**: System MUST persist a player `status` field with allowed values {"normal","cardless"}; set to "cardless" when a King is played as last card by that player; reset to "normal" automatically after forced draw; reject invalid status transitions
- **FR-027**: System MUST reject any King (or card) play attempt from a player who is not the current turn player (authoritative turn gating) and return an appropriate error

### Key Entities

- **Game Session**: Represents an active game, now requires a `direction` attribute to track whether the game flows clockwise or counter-clockwise (default: clockwise)
- **King Card**: A special card (rank "K") that, when played matching the last card's suit or rank, reverses the game direction
- **Turn Order**: The sequence of players taking turns, which is determined by the game direction and player join order
- **Player State**: Tracks whether a player is in normal play or "cardless" state (when they play a King as their last card)
	- Implemented as a `status` enum-like string field on `game_session_players` with allowed values {"normal","cardless"}; future statuses can be added via spec & migration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Players can successfully play a King card when it matches the last played card, and the game direction reverses within 1 second
- **SC-002**: 100% of invalid King card plays (non-matching suit/rank or multiple Kings) are rejected with clear error messages
- **SC-003**: All players in a game session receive direction change notifications within 2 seconds of a King card being played
- **SC-004**: In 2-player games, King card plays advance turns correctly without causing turn calculation errors
- **SC-005**: Game state correctly reflects the current direction after any number of Kings are played in sequence
- **SC-006**: Players who play a King as their last card enter cardless state correctly and can draw a card on their next turn within 2 seconds
- **SC-007**: When the post-recycle no-draw anomaly occurs, the info banner appears to all players within 2 seconds and does not block interaction
- **SC-008**: For King-related actions, 100% of direction_change, cardless_entered, and anomaly_skip events are recorded with required metadata and available in logs within 5 seconds
- **SC-009**: Direction change toast appears for all players within 1 second of King play and persistent indicator reflects new direction; toast auto-dismisses in <=5 seconds
- **SC-010**: Direction indicator label has contrast ratio ≥ 4.5:1 against its background and is perceivable without color; screen readers announce the change within 2 seconds via polite live region or equivalent
- **SC-011**: 100% of King feature UI strings are sourced via i18n keys (no hardcoded literals in templates/components other than the translation key references)
- **SC-012**: 0 occurrences of player display names/emails in King-related structured event logs under standard operation (validated via automated log scan)
- **SC-013**: During bursts with ≥2 direction changes within 2 seconds, at most one toast is displayed (updated), while the persistent indicator reflects each change within 1 second
