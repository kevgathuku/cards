---
inclusion: always
---

# Project Structure

## Top-Level Organization

```
lib/
├── kadi/              # Business logic contexts
└── kadi_web/          # Web interface layer
test/                  # Test files (mirrors lib/ structure)
priv/
├── repo/migrations/   # Database migrations
└── static/            # Static assets
config/                # Application configuration
assets/                # Source assets (JS, CSS)
```

## Context Boundaries

### `lib/kadi/` - Business Logic

- **`accounts.ex`**: Player authentication, registration, session management
- **`card_games.ex`**: Core game state management (sessions, players, decks, cards)
- **`games/`**: Game-specific logic and schemas
- **`repo.ex`**: Ecto repository for database access
- **`application.ex`**: OTP application supervisor tree

**Rule**: Only context modules interact with Ecto. LiveViews and controllers call context functions.

### `lib/kadi_web/` - Web Interface

- **`live/`**: Phoenix LiveView modules for real-time UI
  - `game_live.ex`: In-game interface
  - `lobby_live.ex`: Game session list
- **`components/`**: Reusable UI components
- **`controllers/`**: HTTP request handlers
- **`router.ex`**: Route definitions with live_session scopes
- **`player_auth.ex`**: Authentication plugs and helpers

**Rule**: No business logic in LiveViews. Delegate to context modules.

## Database Schema

Key tables:
- `game_sessions`: Game state, status, current turn
- `game_session_players`: Players in games (join table)
- `decks`: One deck per game session
- `cards`: 52 standard playing cards (shared across games)
- `deck_cards`: Tracks card locations (deck/played_stack/player_hand)

See `priv/repo/migrations/` for schema definitions.

## Test Organization

Tests mirror the `lib/` structure:
- `test/kadi/` - Context tests
- `test/kadi_web/` - LiveView and controller tests
- `test/support/` - Test helpers and fixtures

Use Ecto Sandbox (`:manual` mode) for database isolation.

## Configuration

- `config/config.exs`: Shared configuration
- `config/dev.exs`: Development environment
- `config/test.exs`: Test environment
- `config/prod.exs`: Production environment
- `config/runtime.exs`: Runtime configuration (secrets, env vars)
