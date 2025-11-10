# LiveView Event Contracts for Ace Card Feature

**Date**: 2025-11-10
**Feature**: Ace Card Special Action

This document defines the client-server interaction contracts for the Ace card feature, which is implemented using Phoenix LiveView.

## 1. Overview

The feature introduces a new state where the game waits for a player to select a suit. This requires a new client-to-server event and modifications to the data broadcast from the server.

## 2. New Client-to-Server Event

### `select_suit`

- **Description**: Sent by the client when a player clicks one of the suit selection buttons that appear after they have played an Ace.
- **Event Name**: `"select_suit"`
- **Payload**: A map containing the chosen suit.
  ```json
  {
    "suit": "clubs"
  }
  ```
- **Server Handler**: `handle_event("select_suit", %{"suit" => suit}, socket)` in `KadiWeb.GameLive`.
- **Server-Side Logic**:
  1.  The handler will call a new function in the `Kadi.CardGames` context, e.g., `CardGames.select_suit(game_session, current_player, suit)`.
  2.  The context function will validate that the game is in the correct state and that the current player is the one who played the Ace.
  3.  It will update the `game_session.requested_suit` field in the database.
  4.  It will advance the turn to the next player.
  5.  It will broadcast the updated `game_session` to all players via PubSub.

## 3. Modified Server-to-Client Broadcast

### `game_updated`

The payload of the existing `game_updated` broadcast will be implicitly modified by the changes to the `GameSession` state.

- **Topic**: `game:<game_id>`
- **Event Name**: `"game_updated"`
- **Payload**: `%{ game_session: game_session }`

### New State Representation

To enable the UI to show the suit selection buttons, a new field needs to be added to the `game_session` payload to indicate which player needs to select a suit. A simple way to do this is to check for a condition on the server and pass a boolean flag to the client.

A better approach is to add a new field to the `GameSession` schema: `awaiting_suit_selection_from_player_id`.

**Alternative (and better) Data Model Change:**

Instead of just `requested_suit`, the `game_sessions` table should have:
- `action_suit`: `string`, nullable. This will store the suit requested by the player.
- `action_type`: `string`, nullable. This will store the type of action required, e.g., `"select_suit"`.

When an Ace is played:
1. `game_session.action_type` is set to `"select_suit"`.
2. `game_session.current_turn_player_id` remains the same. The turn does not advance yet.
3. The `GameLive` view sees that `action_type == "select_suit"` and the `current_player.id` matches the `current_turn_player_id`, so it renders the selection buttons.

When the player sends the `select_suit` event:
1. The server sets `game_session.action_type` to `nil`.
2. It sets `game_session.action_suit` to the chosen suit.
3. It advances the `current_turn_player_id` to the next player.
4. It broadcasts the update.

When the next player plays a card:
1. The validator checks `game_session.action_suit`.
2. If the play is valid, `game_session.action_suit` is reset to `nil`.

This is a more robust way to handle the intermediate state. The `data-model.md` should be updated to reflect this more detailed design.

**Final Contract:**

- **`play_cards` with an Ace**:
  - Server sets `game_session.action_type` to `"select_suit"`.
  - Server broadcasts `game_updated`.
- **Client UI**:
  - If `socket.assigns.game_session.action_type == "select_suit"` and it's the current user's turn, show suit selection buttons.
- **`select_suit` event**:
  - Client sends `%{ "suit": "spades" }`.
  - Server sets `action_type` to `nil`, sets `action_suit` to `"spades"`, advances the turn, and broadcasts `game_updated`.
- **Next `play_cards` event**:
  - Server validator uses `action_suit` to check for validity.
  - On valid play, server sets `action_suit` to `nil`.
