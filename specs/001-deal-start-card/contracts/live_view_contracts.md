# LiveView Contracts: Deal Start Card

**Status**: Completed

This document defines the communication contract for the `GameLive` view, including socket assigns and key events.

## 1. `GameLive` Socket Assigns

The following keys will be present in the `socket.assigns` and used to render the game state. The frontend template (`game_live.html.heex`) will depend on this structure.

| Assign Key        | Data Type                | Description                                                                 |
|-------------------|--------------------------|-----------------------------------------------------------------------------|
| `@game_session`   | `%Kadi.Games.GameSession{}` | The full game session Ecto struct.                                          |
| `@current_player` | `%Kadi.Accounts.Player{}`   | The currently logged-in player.                                             |
| `@player_hand`    | `list(String.t())`       | A list of card identifiers (e.g., `["H2", "SK"]`) for the current player. |
| `@played_pile`    | `list(String.t())`       | A list of card identifiers in the played pile. The last card is the top.    |
| `@deck_size`      | `integer()`              | The number of cards remaining in the draw deck.                             |

## 2. Real-time Updates (PubSub)

When the game state changes, the backend will broadcast an event using `Phoenix.PubSub`. The `GameLive` view will be subscribed to these events and will update its state accordingly.

-   **Topic**: `"game:" <> game_session_id`
-   **Event Name**: `"game_updated"`
-   **Payload**: `%{game_session: game_session}`

`GameLive` will implement a `handle_info/2` function to catch this event. Upon receiving it, it will re-calculate the assigns (`@player_hand`, `@played_pile`, `@deck_size`) based on the new `game_session` state and update the socket, causing the frontend to re-render with the new state for all connected players.

## 3. Player Actions (Events)

While this feature is primarily about visualizing the start of the game, it lays the groundwork for future player actions.

-   **Event Type**: `phx-click`
-   **Event Name**: A future event like `"play_card"` will be handled by `handle_event/3` in `GameLive`.
-   **Payload**: `%{ "card" => "H7" }`

This contract ensures a clear separation of concerns:

1.  The backend (`CardGames` context) is the source of truth for game state.
2.  The `GameLive` module is responsible for fetching state, handling user input, and displaying data.
3.  `Phoenix.PubSub` is the transport layer for broadcasting state changes to all clients.
