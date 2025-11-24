# Research & Analysis for Ace Card Feature

**Date**: 2025-11-10  
**Updated**: 2025-11-13 (suit persistence clarifications)  
**Feature**: Ace Card Special Action

This document outlines the findings from analyzing the existing codebase to determine the implementation strategy for the Ace card feature, with updated decisions based on clarified suit persistence requirements.

## 1. Core Logic and State Management

### Findings

- **Game Logic Context**: The primary business logic for gameplay resides in `Kadi.CardGames`. This module orchestrates all major game actions, including playing cards, drawing cards, and advancing turns.
- **Game State Schema**: The state of a game is stored in the `game_sessions` table, represented by the `Kadi.Games.GameSession` Ecto schema. This schema currently tracks `status`, `direction`, `current_turn_player_id`, and `top_card_id`.
- **State Management**: The game flow is managed through function calls within the `Kadi.CardGames` context. There is no evidence of a separate state machine library; the state is passed through functions and updated in the database.

### Decision

- The core logic for handling the Ace card's effect will be implemented within the `Kadi.CardGames` module.
- A new function, `select_suit/3`, will be added to `Kadi.CardGames` to handle the action of a player choosing a suit after playing an Ace.
- The `Kadi.Games.GameSession` schema will be modified to include a new field to track the requested suit.

## 2. Play Validation

### Findings

- **Validation Module**: Card play validation is handled by the pure functions in `Kadi.Games.PlayValidator`. The main function is `valid_play?/2`.
- **Existing Logic**: The module already has specific clauses for "king" and "jack" cards, making it easy to extend for the "ace".

### Decision

- A new function clause for `valid_play?/2` will be added to handle plays where the `cards_to_play` list contains an Ace. An Ace can be played at any time, so this validation will always return `true`.
- The main `valid_play?/2` function will be modified to check for a `requested_suit` on the game session. If a `requested_suit` is present, the played card must match that suit (unless it's another Ace).
- **Combo Validation**: When a requested suit is enforced, only the lead (first) card in a combo needs to match the requested suit. This follows the existing game pattern where combo validation checks if the lead card meets requirements. Example: if Clubs is requested, playing [4♣, 4♥] is valid.

## 3. User Interface (LiveView)

### Findings

- **Game UI**: The main game interface is managed by `KadiWeb.GameLive`.
- **Event Handling**: It uses `handle_event` to manage player actions like `"play_cards"` and `"draw_card"`.
- **State Updates**: The UI is updated in near real-time via Phoenix PubSub broadcasts on the `game:<game_id>` topic.

### Decision

- When a player plays an Ace, the server will not immediately advance the turn. Instead, it will broadcast an update indicating that the game is awaiting a suit selection from that player.
- The `GameLive` template (`.heex`) will be updated to conditionally render four suit-selection buttons when the game is in this state.
- A new event handler, `handle_event("select_suit", %{"suit" => suit}, socket)`, will be added to `GameLive`. This handler will call the new `Kadi.CardGames.select_suit/3` function.

## 4. Data Model

### Findings

- **Primary Schema**: `Kadi.Games.GameSession` is the correct place to store game-wide state.
- **Database Docs**: `docs/database-relationships.md` provides clear guidance on schema conventions.
- **Existing Fields**: Migration `20251110192017_add_action_fields_to_game_sessions.exs` already added `action_type` and `action_suit` fields.

### Decision

- Use existing `action_suit` field (already in `game_sessions` table) to track the requested suit.
- **NO NEW MIGRATION NEEDED** - the field exists but wasn't fully activated in gameplay logic.
- The `Kadi.Games.GameSession` schema already includes `action_suit` with proper validation.
- **Key Implementation Change (2025-11-13)**: The `action_suit` field will persist across turns and only be cleared when:
  1. A player successfully plays a card matching the requested suit (in `execute_play/3`), OR
  2. A player plays an Ace and sets a new suit (in `select_suit/3`)
- **DO NOT clear** `action_suit` in `draw_card_from_deck/2` - this allows the requirement to persist when players draw.

---

## 5. Suit Persistence Strategy (Updated 2025-11-13)

### Findings from Clarifications

- **Session 2025-11-13 Clarification**: "The requested suit persists across multiple turns until either (1) a player successfully plays a card matching the requested suit, or (2) a player plays an Ace and sets a new suit."
- **Draw Behavior**: "The requested suit persists after a player draws (their turn ends but the suit requirement remains active for the next player)."

### Decision

**Persistence Lifecycle**:
```
NULL (no requirement)
  ↓ [Ace played + suit selected in select_suit/3]
"hearts"|"diamonds"|"clubs"|"spades"
  ↓ [Player draws via draw_card_from_deck/2 - NO CHANGE]
"hearts"|"diamonds"|"clubs"|"spades" (persists)
  ↓ [Multiple players may draw in sequence]
"hearts"|"diamonds"|"clubs"|"spades" (still persists)
  ↓ [Matching suit played in execute_play/3 OR new Ace]
NULL (requirement cleared)
```

**Implementation Points**:
- `select_suit/3`: Sets `action_suit` to chosen suit
- `execute_play/3`: Clears `action_suit` to `nil` when non-Ace card matching suit is played
- `draw_card_from_deck/2`: **Does NOT modify** `action_suit` (previous implementation incorrectly cleared it)
- `PlayValidator.valid_play?/3`: Checks `action_suit` parameter on every validation

**Rationale**:
- Creates strategic depth - players cannot bypass requirement by drawing
- Prevents degenerate "draw until requirement expires" strategy
- Matches traditional card game mechanics where special effects persist until resolved
- Guarantees eventual resolution through deck recycling (played cards shuffle back into deck)

---

## 6. Edge Case: Multiple Consecutive Draws

### Scenario

What if all players must draw because none have the required suit?

### Decision

- Requirement persists through all draws until resolution
- Deck recycling (when empty) ensures cards re-enter circulation
- Eventually a player will draw the required suit or an Ace
- This creates game tension and strategic value

**Example Flow**:
1. Player A plays Ace, requests Hearts
2. Player B draws (no Hearts) → Hearts requirement persists
3. Player C draws (no Hearts) → Hearts requirement persists  
4. Player D draws (no Hearts) → Hearts requirement persists
5. Back to Player A → still must play Hearts or draw
6. Continue until someone draws a Heart (plays it next turn) or draws an Ace (overrides)

**Deck Empty Handling** (from spec):
- Recycle played cards except top card
- Shuffled deck includes various suits
- Increases probability of resolution

