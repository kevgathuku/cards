# Research & Analysis for Ace Card Feature

**Date**: 2025-11-10
**Feature**: Ace Card Special Action

This document outlines the findings from analyzing the existing codebase to determine the implementation strategy for the Ace card feature.

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

### Decision

- A new nullable field, `requested_suit`, will be added to the `game_sessions` table.
- A new migration will be created to add this column.
- The `Kadi.Games.GameSession` Ecto schema and changeset will be updated to include the new field. The changeset will validate that the value is one of the four valid suits or `nil`.
