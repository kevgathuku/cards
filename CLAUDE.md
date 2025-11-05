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

**⚠️ WARNING: Avoid running destructive database commands during development**

- **DO NOT** run `mix ecto.reset` when working on tasks or making verifications
- **DO NOT** run `mix ecto.drop` or similar destructive commands
- The local database may contain important development data
- Use test database for destructive operations: `MIX_ENV=test mix ecto.reset`
- For verifying features, use test suite or create temporary data programmatically

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

## Development Guidelines

### Database Safety

- **Never reset or drop the development database** when working on tasks
- Development database may contain important user data
- For testing destructive operations:
  - Use the test suite: `mix test`
  - Use test environment: `MIX_ENV=test mix ecto.reset`
  - Create temporary data programmatically in scripts
- Verification should be done through:
  - Running existing tests
  - Adding new test cases
  - Creating temporary test data in isolated transactions

### Code Changes

- Make minimal, surgical changes to accomplish the task
- Run tests after changes: `mix test`
- Use git pre-commit hooks to ensure formatting
- Follow existing patterns in the codebase

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

## Active Technologies

- Elixir 1.14+ (OTP 25+) + Phoenix 1.7, Phoenix LiveView, Ecto 3.x (002-randomize-player-cards)
- PostgreSQL (via Ecto) - `deck_cards` table with `order_index` column (002-randomize-player-cards)
