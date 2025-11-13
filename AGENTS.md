# AGENTS.md

This file provides guidance to AI agents (including Gemini, GitHub Copilot, and others) when working with code in this repository.

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

### DRY Principle - Avoid Duplication

**CRITICAL: Always check for existing functionality before implementing new features or tests.**

#### Before Writing New Code:

1. **Search for existing functions**:
   ```bash
   # Search for similar function names
   grep -rn "def function_name" lib/

   # Search for related functionality
   grep -rn "keyword" lib/
   ```

2. **Check module documentation**:
   - Read module @doc and function @doc comments
   - Look for related functions in the same module
   - Check if the functionality exists in a different form

3. **Ask yourself**:
   - Does this functionality already exist?
   - Can I reuse an existing function instead of creating a wrapper?
   - Is this a 1:1 wrapper with no added value?

#### Before Writing New Tests:

1. **Search for existing tests**:
   ```bash
   # Find all describe blocks for a function
   grep -n "describe \"function_name" test/

   # Search for similar test scenarios
   grep -rn "test \"scenario" test/
   ```

2. **Check test coverage**:
   - Read existing test suites for the module
   - Look for tests in related features
   - Identify integration tests vs unit tests

3. **Avoid duplicate test scenarios**:
   - **Unit tests** should test the direct function once
   - **Integration tests** should test unique interactions
   - Don't test the same behavior through different paths
   - If existing tests cover the scenario, reference them instead

#### Example: Feature 005 (Basic Gameplay)

**Original Plan**: Create `draw_card/2` wrapper + 5 new tests

**After DRY Analysis**:
- ❌ Removed `draw_card/2` - Was 1:1 wrapper of existing `draw_card_from_deck/2`
- ❌ Removed 4 duplicate tests - Already tested in features 003 & 004
- ✅ Kept 1 unique gameplay-specific test
- **Result**: No code duplication, 6 fewer tests, same coverage

#### Test Organization Strategy:

- **Feature tests** (e.g., feature 003): Test the direct function thoroughly
- **Integration tests** (e.g., feature 004): Test interaction between features
- **User story tests**: Only test unique gameplay-specific behaviors
- **Don't test**: Same scenario through different call paths

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
- **Check for existing implementations before creating new functions**
- **Search for existing tests before writing new test cases**
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

- Elixir 1.17+ (OTP 25+) + Phoenix 1.7, Phoenix LiveView, Ecto 3.x
- PostgreSQL (via Ecto) - `deck_cards` table with `order_index` and `location_type` columns

## Player Actions & Turn Management

The game implements turn-based gameplay where players can:
- **Draw a card from deck**: Players can draw one card during their turn, which automatically advances the turn to the next player
- **Play cards from hand**: Play valid card combinations onto the played pile
- Turn order is determined by join time (`game_session_players.inserted_at`), wrapping around from last to first player

## Key Implementation Patterns

### Broadcast-Only Updates
LiveView handlers often do NOT update socket state directly. Instead:
1. Handler calls context function (e.g., `CardGames.draw_card_from_deck/2`)
2. Context function performs database transaction
3. Context broadcasts `game_updated` event via PubSub
4. LiveView `handle_info` receives broadcast and updates socket
5. This ensures all connected players receive updates simultaneously

Example:
```elixir
def handle_event("draw_card", _params, socket) do
  case CardGames.draw_card_from_deck(game_session, player_id) do
    {:ok, _updated} -> {:noreply, socket}  # Don't update - wait for broadcast
    {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
  end
end

def handle_info({:game_updated, game_session}, socket) do
  {:noreply, assign_game_state(socket, game_session)}  # Update from broadcast
end
```

### Atomic Transactions
Game state changes use `Ecto.Multi` for atomicity:
```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:card, card_changeset)
|> Ecto.Multi.update(:game_session, session_changeset)
|> Repo.transaction()
```

### Turn Order Calculation
- Players ordered by `game_session_players.inserted_at ASC`
- Helper function `get_next_player/2` wraps around using `rem/2`
- Turn stored in `game_sessions.current_turn_player_id`
