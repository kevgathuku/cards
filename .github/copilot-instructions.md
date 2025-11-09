# GitHub Copilot Instructions for Kadi

This repository contains **Kadi**, a multiplayer online card game platform built with **Elixir 1.14+** and **Phoenix LiveView 1.7**, implementing "Poker" (Kadi), a popular Kenyan card game. The project uses a **database-driven architecture** with PostgreSQL for persistent game state management.

## Repository Overview

- **Size**: ~50 Elixir source files, ~2,100 lines of code
- **Language**: Elixir (with embedded HTML via .heex templates)
- **Framework**: Phoenix 1.7 with LiveView for real-time UI
- **Database**: PostgreSQL via Ecto 3.x
- **Runtime**: Elixir 1.14+ with OTP 25+
- **Build Tool**: Mix (Elixir's build tool)
- **Key Dependencies**: Phoenix LiveView, Ecto, bcrypt_elixir, Tailwind CSS, esbuild

## Setup and Installation

### Prerequisites
- **Elixir 1.14+** with **OTP 25+** installed
- **PostgreSQL** running locally (default: localhost:5432)
- **Git** for version control
- Hex package manager (install with `mix local.hex --force`)
- Rebar (install with `mix local.rebar --force`)

### Initial Setup
**Always run these commands in order:**

```bash
# 1. Install Hex and Rebar (if not already installed)
mix local.hex --force
mix local.rebar --force

# 2. Run full setup (gets deps, creates DB, runs migrations, builds assets)
mix setup

# 3. (Optional but recommended) Install git hooks for auto-formatting
.githooks/install.sh
```

**Important**: The `mix setup` alias runs: `deps.get` → `ecto.setup` → `assets.setup` → `assets.build`

### Database Configuration
- **Development DB**: `kadi_dev` (user: postgres, password: postgres)
- **Test DB**: `kadi_test` (user: postgres, password: postgres)
- Database config in `config/dev.exs` and `config/test.exs`

## Build Commands

### Running the Application
```bash
# Start Phoenix server (available at http://localhost:4000)
mix phx.server

# Start with interactive Elixir console (preferred for debugging)
iex -S mix phx.server
```

### Testing
**Always run tests before committing code changes:**

```bash
# Run all tests (takes ~10-30 seconds)
mix test

# Run specific test file
mix test test/kadi/card_games_test.exs

# Run specific test at line number
mix test test/kadi/card_games_test.exs:42

# Run with warnings as errors
mix test --warnings-as-errors
```

**Test Setup**: Tests use Ecto Sandbox with `:manual` mode. The test alias automatically creates and migrates the test database before running tests.

### Code Formatting
**Always format code before committing:**

```bash
# Format all Elixir/Phoenix files
mix format

# Check if files need formatting (for CI)
mix format --check-formatted
```

The pre-commit hook (installed via `.githooks/install.sh`) automatically formats staged `.ex`, `.exs`, and `.heex` files.

### Database Operations
**⚠️ CRITICAL: NEVER run destructive database commands during development without explicit permission.**

```bash
# Safe operations:
mix ecto.create       # Create database (safe, only if it doesn't exist)
mix ecto.migrate      # Run pending migrations
mix run priv/repo/seeds.exs  # Seed database with 52 standard cards

# DESTRUCTIVE operations (use ONLY in test environment):
MIX_ENV=test mix ecto.reset   # Reset test database
MIX_ENV=test mix ecto.drop    # Drop test database

# NEVER run these in development:
# mix ecto.reset  ❌ (drops and recreates dev database)
# mix ecto.drop   ❌ (destroys dev database)
```

### Assets
Assets are managed by esbuild and Tailwind:

```bash
# Build assets (production)
mix assets.build

# Deploy assets (minified)
mix assets.deploy
```

Assets are automatically watched and rebuilt during development via `mix phx.server`.

## Project Structure

### Directory Layout
```
/home/runner/work/cards/cards/
├── .github/
│   └── workflows/
│       └── elixir.yml          # CI pipeline (runs tests on PRs)
├── .githooks/
│   ├── pre-commit              # Auto-formats code on commit
│   └── install.sh              # Installs git hooks
├── assets/
│   ├── css/app.css             # Tailwind CSS
│   ├── js/app.js               # JavaScript entry point
│   └── tailwind.config.js      # Tailwind configuration
├── config/
│   ├── config.exs              # Application configuration
│   ├── dev.exs                 # Development config (DB: kadi_dev)
│   ├── test.exs                # Test config (DB: kadi_test)
│   ├── prod.exs                # Production config
│   └── runtime.exs             # Runtime configuration
├── docs/
│   └── database-relationships.md  # Database schema documentation
├── lib/
│   ├── kadi/
│   │   ├── accounts.ex         # Player authentication context
│   │   ├── card_games.ex       # Main game logic context (22K LOC)
│   │   ├── games/
│   │   │   ├── card.ex         # Card schema (52 shared cards)
│   │   │   ├── deck.ex         # Deck schema (one per game)
│   │   │   ├── deck_card.ex    # Card locations (deck/hand/played)
│   │   │   ├── game_session.ex # Game session schema
│   │   │   ├── game_session_player.ex  # Join table
│   │   │   ├── play_validator.ex       # Validates card plays
│   │   │   ├── utils.ex        # Game utilities
│   │   │   └── poker/          # Poker-specific logic
│   │   ├── application.ex      # OTP application
│   │   ├── repo.ex             # Ecto repository
│   │   └── registry.ex         # Process registry
│   └── kadi_web/
│       ├── live/
│       │   ├── game_live.ex    # Main game UI
│       │   ├── lobby_live.ex   # Game list
│       │   └── player_*.ex     # Authentication LiveViews
│       ├── components/         # Phoenix components
│       ├── controllers/        # HTTP controllers
│       ├── router.ex           # Route definitions
│       └── endpoint.ex         # Phoenix endpoint
├── priv/
│   ├── repo/
│   │   ├── migrations/         # 15 database migrations
│   │   └── seeds.exs           # Seeds 52 cards
│   └── static/                 # Static assets
├── test/
│   ├── kadi/                   # Context tests
│   ├── kadi_web/               # Web layer tests
│   └── test_helper.exs         # Test configuration
├── mix.exs                     # Project configuration & dependencies
├── .formatter.exs              # Code formatting rules
├── CLAUDE.md                   # Claude AI instructions
└── README.md                   # Project documentation
```

### Key Configuration Files
- **mix.exs**: Project config, dependencies, aliases (setup, test, ecto.*)
- **.formatter.exs**: Auto-formatting config (imports Phoenix/Ecto styles)
- **config/dev.exs**: Dev environment, DB settings, watchers
- **config/test.exs**: Test environment, Ecto Sandbox settings

## Architecture

### Database-Driven State Management
**All game state is persisted in PostgreSQL, not in-memory.**

#### Core Schemas:
- **`players`**: User accounts (authentication via bcrypt)
- **`game_sessions`**: Game instances (status: "lobby" → "live" → "complete")
- **`game_session_players`**: Join table for players in games
- **`decks`**: One deck per game session
- **`cards`**: 52 shared cards (suits × ranks), never deleted
- **`deck_cards`**: Tracks card locations with `location_type`:
  - `"deck"` - Cards in draw pile (ordered by `order_index`, lowest = top)
  - `"player_hand"` - Cards in player's hand (`order_index` is NULL)
  - `"played_stack"` - Played cards (ordered by `order_index`, highest = top/visible)

#### Critical Database Relationships:
- Players are **protected** from deletion via `:restrict` constraints
- Game sessions cascade delete: `game_session` → `decks` → `deck_cards` → `game_session_players`
- Cards (52 shared resources) use `:restrict` to prevent deletion
- Full documentation: `docs/database-relationships.md`

### Key Modules and Contexts

#### Contexts (Business Logic)
- **`Kadi.CardGames`** (lib/kadi/card_games.ex): Main game operations
  - `create_game_session/2` - Create new game
  - `join_game_session/2` - Add player to game
  - `start_game/1` - Deal cards, transition to "live"
  - `draw_card_from_deck/2` - Draw card for player
  - `play_card/3` - Play card from hand
  - `recycle_played_stack/1` - Shuffle played cards back to deck
- **`Kadi.Accounts`** (lib/kadi/accounts.ex): Player authentication/registration
- **`Kadi.Games.PlayValidator`**: Validates card plays per game rules
- **`Kadi.Games.Utils`**: Game utilities (deck shuffling, hand validation)

#### Web Layer (Phoenix LiveView)
- **`KadiWeb.GameLive`**: Real-time game UI (card hands, turns, actions)
- **`KadiWeb.LobbyLive`**: Game session list
- **`KadiWeb.Router`**: Three live_session scopes:
  - `:public` - Redirects authenticated users
  - `:authenticated` - Requires authentication
  - `:confirm_email` - Email confirmation flow

All game interactions happen through LiveView events, **not REST APIs**.

### Real-time Updates
- Phoenix PubSub broadcasts game state changes
- LiveView handles WebSocket connections
- Subscriptions in LiveViews: `Phoenix.PubSub.subscribe(Kadi.PubSub, "game:#{id}")`

## Common Workflows

### Game Flow
1. Player registers → `Kadi.Accounts.register_player/1`
2. Player creates game → `Kadi.CardGames.create_game_session/2` (status: "lobby")
3. Other players join → `Kadi.CardGames.join_game_session/2`
4. Host starts game → `Kadi.CardGames.start_game/1` (deals 4 cards each, status: "live")
5. Players take turns → `draw_card_from_deck/2` or `play_card/3`
6. Game ends when player plays last card

### Testing Patterns
Tests use Ecto Sandbox for isolation:

```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Kadi.Repo)
  # Most tests can be async: true
end
```

Common test helpers in `test/support/`:
- `DataCase`: Database test helpers
- `ConnCase`: Controller/LiveView test helpers
- `FixturesFactory`: Test data fixtures

## GitHub Actions CI

### Workflow: `.github/workflows/elixir.yml`
**Runs on**: Push to `main`, all pull requests

**Steps**:
1. Checkout code
2. Setup Elixir 1.17.3 + OTP 27.0 (via `erlef/setup-beam`)
3. Cache dependencies (speeds up builds)
4. Install dependencies: `mix deps.get`
5. Run tests: `mix test`

**Services**: PostgreSQL 12 (port 5432, password: postgres)

**Expected duration**: 2-5 minutes

**To replicate CI locally**:
```bash
mix deps.get
mix test
```

## Common Pitfalls and Workarounds

### Database Issues
**Problem**: "Database already exists" error during `mix ecto.create`
- **Solution**: Database already created, safe to proceed with `mix ecto.migrate`

**Problem**: "relation does not exist" error during tests
- **Solution**: Run `MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate`

**Problem**: "Connection refused" to PostgreSQL
- **Solution**: Ensure PostgreSQL is running: `pg_isready` or start service

### Dependency Issues
**Problem**: "Could not find Hex" error
- **Solution**: Run `mix local.hex --force && mix local.rebar --force`

**Problem**: Stale dependencies
- **Solution**: `rm -rf deps _build && mix deps.get`

### Asset Build Issues
**Problem**: Assets not updating in browser
- **Solution**: Assets are watched automatically; if stuck, restart `mix phx.server`

**Problem**: Tailwind CSS not building
- **Solution**: Run `mix assets.setup` to reinstall asset tools

### Test Failures
**Problem**: Tests fail with database errors
- **Solution**: Ensure test database exists: `MIX_ENV=test mix ecto.create`

**Problem**: "Connection is already checked out" error
- **Solution**: Remove `async: true` from test that uses database transactions

## Development Best Practices

### Code Style
- **Always run `mix format`** before committing (or install git hooks)
- Follow existing patterns in the codebase
- Use `@doc` and `@moduledoc` for public functions
- Add typespecs (`@spec`) for function signatures

### DRY Principle (From CLAUDE.md)
**Before adding new code**:
1. Search for existing functions: `grep -rn "def function_name" lib/`
2. Check module documentation
3. Avoid creating wrapper functions with no added value
4. Reuse existing functions instead of duplicating

**Before adding tests**:
1. Search existing tests: `grep -n "describe \"function_name" test/`
2. Don't duplicate test scenarios
3. Unit tests should test functions directly once
4. Integration tests should test unique interactions

### Database Safety
- **Never reset dev database** unless explicitly required
- Use test database for destructive operations: `MIX_ENV=test mix ecto.reset`
- Verify changes through tests, not by resetting databases
- Database may contain important development data

### Making Changes
1. Make minimal, surgical changes to accomplish the task
2. Run `mix test` after each change
3. Format code with `mix format`
4. Check for compilation warnings: `mix compile --warnings-as-errors`
5. Ensure CI passes before merging

## Validation Steps

Before finalizing changes, **always**:
1. ✅ Run `mix format --check-formatted` (formatting)
2. ✅ Run `mix compile --warnings-as-errors` (no warnings)
3. ✅ Run `mix test` (all tests pass)
4. ✅ Verify CI pipeline passes on GitHub
5. ✅ Check that no development database was modified destructively

## Additional Resources

- **README.md**: Comprehensive project documentation with examples
- **CLAUDE.md**: Detailed guidelines for AI assistants
- **docs/database-relationships.md**: Database schema and cascade behavior
- **Phoenix LiveView**: https://hexdocs.pm/phoenix_live_view
- **Ecto**: https://hexdocs.pm/ecto
- **Elixir**: https://elixir-lang.org/docs.html

## Trust These Instructions

These instructions have been carefully validated. **Only search for additional information if**:
- These instructions are incomplete for your specific task
- You encounter an error not documented here
- The instructions are found to be incorrect or outdated

For most development tasks, the commands and patterns documented here are sufficient and proven to work.

## Active Technologies
- Elixir 1.17+ with OTP 25+ + Phoenix 1.7, Phoenix LiveView, Ecto 3.x (007-jack-card)
- PostgreSQL (via Ecto) - existing game_sessions, game_session_players, deck_cards tables (007-jack-card)

## Recent Changes
- 007-jack-card: Added Elixir 1.17+ with OTP 25+ + Phoenix 1.7, Phoenix LiveView, Ecto 3.x
