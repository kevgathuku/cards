# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kadi is a multiplayer online card game built with Clojure, focused on implementing "Poker" (a card game popular in Kenya, also known as "Kadi"). This is a rewrite from a previous Elixir/Phoenix implementation - see `docs/CLOJURE_BOOTSTRAP_BRIEF.md` for the complete game specification and lessons learned.

### Core Architecture

```
Game state is a pure value (immutable map).
State transitions are pure functions: (state, action) -> state
Side effects (persistence, broadcasting) happen at the edges.
```

## Development Commands

### Setup

```bash
clj -P                    # Download dependencies
clj -M:dev -m kadi.db     # Initialize database (creates kadi.db)
```

### Running the Application

```bash
clj -M:run                # Start server at localhost:3000
clj -M:repl               # Start REPL with nREPL for editor connection
```

### Testing

```bash
clj -M:test               # Run all tests with Kaocha
clj -M:test --focus :unit # Run specific test suite
```

### REPL Development

```clojure
;; In REPL
(require '[kadi.core :as core])
(require '[kadi.game :as game])
(require '[kadi.db :as db])

;; Initialize DB
(db/init!)

;; Create and manipulate game state (pure functions)
(def g (game/new-game {:id 1 :short-code "TEST" :created-by 1}))
(def g (game/add-player g {:id 1 :name "Alice"}))
(def g (game/add-player g {:id 2 :name "Bob"}))
(def g (game/start-game g {}))

;; Apply actions
(game/apply-action g {:type :play-cards :player-id 1 :cards [...]})
```

## Architecture

### Pure Game Logic (No Side Effects)

**`kadi.game`** - Core game state and transitions:
- `new-game`, `add-player`, `start-game`
- `apply-action` multimethod for all state transitions
- All functions are pure: `(state, action) -> state`

**`kadi.cards`** - Card representation and utilities:
- Card predicates: `ace?`, `king?`, `jack?`, `question-card?`, `penalty-card?`
- Matching: `matches-suit?`, `matches-rank?`, `matches?`
- Deck creation and shuffling

**`kadi.validation`** - Play validation (pure):
- `validate-play` returns `{:valid? bool :reason string}`
- All game rules encoded here

### Side Effects (At The Edges)

**`kadi.db`** - SQLite persistence:
- Game CRUD operations
- Event sourcing with `append-event!` and `get-events`
- Player management

**`kadi.server`** / **`kadi.handlers`** - HTTP API:
- Ring + Reitit for routing
- JSON API for game actions

## Database

SQLite with INTEGER primary keys (not UUIDs). Database file: `kadi.db`

**Tables:**
- `games` - state (JSON), state_sequence (links to last event)
- `players` - authentication
- `game_players` - authorization (who can access which game)
- `game_events` - event sourcing (sequence_number, event_type, event_data)

```bash
# View database
sqlite3 kadi.db ".tables"
sqlite3 kadi.db "SELECT id, short_code, state_sequence FROM games"
sqlite3 kadi.db "SELECT json_extract(state, '$.status') FROM games"
```

## Key Design Decisions

### From Elixir Lessons Learned

1. **Pure state transitions** - Unlike Elixir version where state changes were scattered across Ecto changesets, all transitions go through `apply-action`

2. **Event sourcing built-in** - `game_events` table stores all actions; `state_sequence` tracks which event the current state was derived from

3. **Single source of truth** - No duplicate columns; status lives only in state JSON, queried via `json_extract()`

4. **SQLite for simplicity** - Single file, embedded, zero config

5. **INTEGER IDs** - Simpler than UUIDs, SQLite INTEGER is already 64-bit

### Game Rules Quick Reference

| Rank | Match Rule | Combo | Effect | Can Start |
|------|------------|-------|--------|-----------|
| 2 | Suit/Rank | Yes | Draw 2 penalty | No |
| 3 | Suit/Rank | Yes | Draw 3 penalty | No |
| 4-7,9,10 | Suit/Rank | Yes | None | Yes |
| 8 | Suit/Rank | Q,8 | Question | Yes |
| J | Suit/Rank | J | Skip N | No |
| Q | Suit/Rank | Q,8 | Question | Yes |
| K | Suit/Rank | No | Reverse | Yes |
| A | Always | A | Suit select | Yes |

See `docs/CLOJURE_BOOTSTRAP_BRIEF.md` for complete rules.

## Testing Strategy

Tests are pure - no database setup required:

```clojure
(deftest play-king-reverses-direction
  (let [game (make-test-game)
        result (game/apply-action game {:type :play-cards
                                        :player-id 1
                                        :cards [king]})]
    (is (= :counter-clockwise (:direction result)))))
```

## Development Guidelines

### Code Changes

- Game logic changes go in `kadi.game` or `kadi.validation`
- Keep side effects in `kadi.db` and `kadi.handlers`
- Run tests after changes: `clj -M:test`
- All state transitions must go through `apply-action`

### Adding New Card Effects

1. Add predicate to `kadi.cards` if needed
2. Add validation rule to `kadi.validation`
3. Add effect handling to `apply-card-effects` in `kadi.game`
4. Add tests in `test/kadi/game_test.clj`

## Previous Implementation

The Elixir/Phoenix implementation is preserved at:
- Tag: `v1.0-elixir`
- Branch: `archive/elixir-implementation`

```bash
# View old implementation
git show v1.0-elixir:lib/kadi/games/play_validator.ex
```
