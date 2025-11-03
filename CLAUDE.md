# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kadi is a multiplayer online card game platform built with Elixir and Phoenix LiveView, focused on implementing "Poker" (a card game popular in Kenya, also known as "Kadi"). The architecture is designed to support multiple card games.

## Development Commands

### Setup
```bash
mix setup    # Full setup: deps, database, assets
```

### Running the Application
```bash
mix phx.server          # Start server at localhost:4000
iex -S mix phx.server   # Start with IEx console for debugging
```

### Testing
```bash
mix test                      # Run all tests
mix test test/path/to/test.exs:42  # Run specific test at line 42
```

### Database
```bash
mix ecto.reset   # Drop, recreate, migrate, and seed database
```

## Architecture

### Database-Driven Game State

The application uses a persistent database approach for managing game state:

**`Kadi.CardGames`** context (lib/kadi/card_games.ex):
- PostgreSQL database via Ecto
- Manages GameSessions, Players, Decks, and Cards
- Handles player joins, card dealing, session management
- Game status transitions: "lobby" → "live"

**Database Schema:**
- `game_sessions`: Core game session records with status field
- `game_session_players`: Join table for players in games
- `decks`: One deck per game session
- `cards`: 52 unique cards shared across all games
- `deck_cards`: Tracks card locations (deck/played_stack/player_hand)

### Key Modules

- **`Kadi.CardGames`**: Database context for persistent game sessions
- **`Kadi.Utils`**: Game logic utilities (deck creation, hand validation with complex Q/A combination rules)
- **`Kadi.Accounts`**: Player authentication and registration
- **`KadiWeb.GameLive`**: LiveView for game UI (lib/kadi_web/live/game_live.ex)
- **`KadiWeb.LobbyLive`**: LiveView for game session list

## Testing

Tests use Ecto Sandbox (`:manual` mode) for database isolation. Most tests are async-capable where appropriate.

## Phoenix LiveView Integration

- Server-side rendering with WebSocket updates
- Authentication via `on_mount` hooks in router live_sessions
- Three live_session scopes: public (redirect_if_authenticated), authenticated (require_authenticated), and confirm_email
- No REST API for game actions - all interactions through LiveView events

## Card Representation

Cards are stored in the database using the `Kadi.Games.Card` schema:
```elixir
%Kadi.Games.Card{suit: "hearts", rank: "5"}
```

Card locations are tracked through the `deck_cards` join table with a `location_type` field.
