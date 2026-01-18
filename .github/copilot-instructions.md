# GitHub Copilot Instructions for Kadi

This repository contains **Kadi**, a multiplayer online card game built with **Clojure 1.12**, implementing "Poker" (Kadi), a popular Kenyan card game. The project uses a **pure functional core with side effects at the edges** architecture, with SQLite for persistence.

## Repository Overview

- **Size**: ~1,800 lines of Clojure code (10 source files, 2 test files)
- **Language**: Clojure 1.12
- **Runtime**: Java 17+ (tested with OpenJDK 17)
- **Build Tool**: Clojure CLI (`clojure` or `clj` command)
- **Framework**: Ring + Reitit (HTTP), Hiccup (HTML templating), Sente (WebSockets)
- **Database**: SQLite (single file: `kadi.db`, no migrations needed)
- **Testing**: Kaocha test runner
- **Key Dependencies**: ring, reitit, hiccup, next.jdbc, sqlite-jdbc, sente, jsonista, malli

## Core Architecture Philosophy

```
Game state is a pure value (immutable map).
State transitions are pure functions: (state, action) -> state
Side effects (persistence, broadcasting) happen at the edges.
```

## Setup and Installation

### Prerequisites
- **Java 17+** (OpenJDK recommended)
- **Clojure CLI 1.11+** ([install guide](https://clojure.org/guides/install_clojure))
- **Git** for version control

### Initial Setup
**Always run commands in this order:**

```bash
# 1. Download all dependencies (takes ~30-60 seconds on first run)
clojure -P

# 2. Initialize database (creates kadi.db)
clojure -M:dev -m kadi.db

# 3. (Optional) Download test dependencies
clojure -M:test -P
```

**Important**: `clojure -P` (or `clj -P`) is the "prepare" command that downloads dependencies from Maven Central and Clojars. Run this after any changes to `deps.edn`.

### Database
- SQLite database: `kadi.db` (created automatically by `kadi.db/init!`)
- Schema defined in `kadi.db/schema` (runs `CREATE TABLE IF NOT EXISTS`)
- No migration files - schema is idempotent
- To reset database: `rm kadi.db && clojure -M:dev -m kadi.db`

## Build Commands

### Running the Application
```bash
# Start server at http://localhost:3000 (takes ~3-5 seconds)
clojure -M:run

# Start REPL with nREPL server (for editor integration)
clojure -M:repl

# Start dev REPL with auto-start server
clojure -M:dev-repl
```

**Server startup**: Initializes database, starts Jetty on port 3000 (configurable via first argument: `clojure -M:run 8080`)

### Testing
**Always run tests before committing code changes:**

```bash
# Run all tests with Kaocha (takes ~2-5 seconds)
clojure -M:test

# Run specific test suite
clojure -M:test --focus :unit

# Tests are pure - no database setup required
```

**Important**: Tests in `test/kadi/game_test.clj` are **pure function tests** that don't require database setup. Tests in `test/kadi/routes_auth_test.clj` test HTTP routes and may use temporary databases.

### REPL Development
REPL-driven development is the **primary workflow** for Clojure. Common REPL commands:

```clojure
;; Initialize database
(require '[kadi.db :as db])
(db/init!)

;; Create and manipulate game state (pure functions, no DB)
(require '[kadi.game :as game])
(def g (game/new-game {}))
(def g (game/add-player g {:id 1 :name "Alice"}))
(def g (game/add-player g {:id 2 :name "Bob"}))
(def g (game/start-game g {}))

;; Apply actions (pure)
(game/apply-action g {:type :play-cards :player-id 1 :cards [...]})

;; Check card predicates
(require '[kadi.cards :as cards])
(cards/ace? {:suit :hearts :rank "A"})  ;; => true

;; Start/stop server programmatically
(require '[kadi.server :as server])
(server/start! {:port 3000})
(server/stop!)
```

### Code Formatting
Clojure code is typically formatted by your editor (cljfmt, Calva, Cursive). No pre-commit hooks are configured.

## Project Structure

### Directory Layout
```
/home/runner/work/cards/cards/
├── .github/
│   └── workflows/
│       └── clojure.yml         # CI: Java 21 + Clojure CLI + clojure -M:test
├── .claude/                    # Claude AI custom prompts/agents
├── deps.edn                    # Dependencies and aliases (:dev, :test, :run, :repl)
├── tests.edn                   # Kaocha test runner config
├── dev/
│   └── user.clj                # REPL utilities (start-server, stop-server, restart-server)
├── docs/
│   ├── CLOJURE_BOOTSTRAP_BRIEF.md  # Complete game rules and design decisions
│   └── *.md                    # Feature specifications
├── resources/
│   └── migrations/
│       └── 001_initial.sql     # Schema reference (executed via kadi.db/init!)
├── src/kadi/
│   ├── core.clj                # -main entry point
│   ├── game.clj                # Pure game state & transitions (300 LOC)
│   ├── cards.clj               # Card predicates & utilities (100 LOC)
│   ├── validation.clj          # Play validation rules (pure, 160 LOC)
│   ├── db.clj                  # SQLite persistence (200 LOC)
│   ├── auth.clj                # Email magic link authentication (100 LOC)
│   ├── server.clj              # Ring/Jetty server (50 LOC)
│   ├── routes.clj              # Reitit route definitions (150 LOC)
│   ├── handlers.clj            # HTTP request handlers (200 LOC)
│   └── views.clj               # Hiccup HTML views (270 LOC)
└── test/kadi/
    ├── game_test.clj           # Pure function tests (200 LOC)
    └── routes_auth_test.clj    # HTTP route tests (40 LOC)
```

### Key Configuration Files
- **deps.edn**: Project dependencies, paths, and aliases (`:dev`, `:test`, `:run`, `:repl`, `:dev-repl`)
- **tests.edn**: Kaocha config (test paths, color output, fail-fast)
- **dev/user.clj**: REPL helper functions (auto-loaded in REPL sessions with `:dev` alias)

## Architecture

### Pure Core, Effects at Edges

**Pure Core** (No side effects):
- **`kadi.game`**: All state transitions via `apply-action` multimethod
  - `new-game`, `add-player`, `start-game`, `advance-turn`, `reverse-direction`
  - `apply-action` handles: `:play-cards`, `:draw-card`, `:select-suit`, `:answer-question`
- **`kadi.cards`**: Card predicates (`ace?`, `king?`, `jack?`, `question-card?`, `penalty-card?`)
- **`kadi.validation`**: `validate-play` returns `{:valid? bool :reason string}`

**Effects at Edges**:
- **`kadi.db`**: SQLite operations (games, players, auth tokens, events)
  - Event sourcing: `append-event!` and `get-events` for full game history
  - Game CRUD: `create-game!`, `update-game!`, `get-game-by-short-code`
- **`kadi.auth`**: Token generation (`create-signin-token!`), email sending (stubbed for dev)
- **`kadi.handlers`**: HTTP handlers that read DB, apply pure functions, persist results
- **`kadi.views`**: Server-rendered Hiccup HTML (HTMX for partial updates)

### Database Schema (SQLite, INTEGER PKs)

Tables:
- **`games`**: `id`, `short_code`, `state` (JSON), `state_sequence` (links to events), `created_at`, `updated_at`
- **`players`**: `id`, `name`, `email` (unique), `created_at` - **No passwords** (email magic links only)
- **`auth_tokens`**: `id`, `email`, `token`, `expires_at`, `used`, `created_at`
- **`game_players`**: `id`, `game_id` (FK), `player_id` (FK), `joined_at`, `status`, UNIQUE(game_id, player_id)
- **`game_events`**: `id`, `game_id` (FK), `sequence_number`, `event_type`, `event_data` (JSON), `created_at`

Indexes:
- Games: `short_code`, `json_extract(state, '$.status')`
- Events: `game_id`
- Tokens: `token`, `email`

**Inspect DB**:
```bash
sqlite3 kadi.db ".tables"
sqlite3 kadi.db "SELECT id, short_code, json_extract(state, '$.status') FROM games;"
```

### Game Rules Quick Reference
See `docs/CLOJURE_BOOTSTRAP_BRIEF.md` for **complete** specification. Key points:

| Rank | Match Rule | Combo | Effect | Can Start |
|------|------------|-------|--------|-----------|
| 2    | Suit/Rank  | Yes   | Draw 2 penalty | No |
| 3    | Suit/Rank  | Yes   | Draw 3 penalty | No |
| 4-7,9,10 | Suit/Rank | Yes | None | Yes |
| 8    | Suit/Rank  | Q,8   | Question | Yes |
| J    | Suit/Rank  | J only | Skip N players | No |
| Q    | Suit/Rank  | Q,8   | Question | Yes |
| K    | Suit/Rank  | No    | Reverse direction | Yes |
| A    | Always     | A only | Suit selection | Yes |

**Critical Rules**:
- Aces can **always** be played (ignore suit/rank matching)
- Penalties (2/3) can only be blocked by same rank or Ace
- Question cards (Q/8) require "answer" card (same suit/rank, non-question)
- Playing K/J/2/3 as last card triggers "cardless" state (not a win)

## Common Workflows

### Development Workflow
1. Start REPL: `clojure -M:repl`
2. Connect editor (nREPL port printed on startup)
3. Evaluate code in editor
4. Test changes with `(require '[kadi.game-test] :reload)` and `(clojure.test/run-tests 'kadi.game-test)`
5. Run full test suite: `clojure -M:test`

### Adding New Card Effects
1. Add predicate to `kadi.cards` if needed (e.g., `special-card?`)
2. Add validation rule to `kadi.validation/validate-play`
3. Add effect handling to `kadi.game/apply-card-effects`
4. Write pure function tests in `test/kadi/game_test.clj`

### Testing Patterns
Tests are **pure** - no database or server required:

```clojure
(deftest my-test
  (let [game (-> (game/new-game {})
                 (game/add-player {:id 1 :name "Alice"})
                 (game/start-game {}))]
    (is (= :live (:status game)))
    (is (= 4 (count (get-in game [:players 0 :hand]))))))
```

## GitHub Actions CI

### Workflow: `.github/workflows/clojure.yml`
**Runs on**: Push to `main`, all pull requests

**Steps**:
1. Checkout code
2. Setup Java 21 (Temurin distribution)
3. Install Clojure CLI (latest)
4. Cache dependencies (`~/.m2/repository`, `~/.gitlibs`, `~/.deps.clj`)
5. Run tests: `clojure -M:test`

**Expected duration**: 1-2 minutes (with cache hit)

**To replicate CI locally**:
```bash
clojure -M:test
```

## Common Pitfalls and Workarounds

### Dependency Issues
**Problem**: `org.eclipse.aether.resolution.ArtifactDescriptorException` or network errors
- **Solution**: Some networks block Maven Central or Clojars. Try: (1) different network, (2) configure Maven mirror, or (3) use cached deps from CI

**Problem**: "Could not find artifact" error
- **Solution**: Run `clojure -P` to download dependencies. Check `deps.edn` for typos.

**Problem**: Stale dependencies after updating `deps.edn`
- **Solution**: Delete cache: `rm -rf ~/.clojure/.cpcache` and re-run `clojure -P`

### REPL Issues
**Problem**: REPL hangs on startup
- **Solution**: Check if port 3000 or nREPL port (printed on startup) is already in use

**Problem**: "No such namespace" error in REPL
- **Solution**: Use `(require '[namespace] :reload)` to reload changed namespaces

### Database Issues
**Problem**: SQLite "database is locked" error
- **Solution**: Ensure no other process has `kadi.db` open. SQLite uses WAL mode for better concurrency.

**Problem**: Schema changes not reflected
- **Solution**: Delete `kadi.db` and re-run `clojure -M:dev -m kadi.db` (destructive - only for development)

### Test Failures
**Problem**: Tests fail after code changes
- **Solution**: Tests are pure - if they fail, it's a logic error in pure functions. Use REPL to debug: `(require '[kadi.game-test] :reload)` and run individual tests.

## Development Best Practices

### Code Style
- Follow Clojure style guide: https://guide.clojure.style/
- Use descriptive names (`add-player`, not `ap`)
- Keep functions small and focused
- Prefer pure functions over side effects

### DRY Principle
**Before adding code**:
1. Search existing functions: `grep -rn "defn function-name" src/`
2. Check if `kadi.game` or `kadi.cards` already has what you need
3. Avoid duplicating validation or state transition logic

**Before adding tests**:
1. Search existing tests: `grep -n "deftest" test/`
2. Tests should be pure and fast - no database or HTTP mocking needed

### Making Changes
1. Make minimal, focused changes
2. Run tests after each change: `clojure -M:test`
3. Test interactively in REPL before finalizing
4. Ensure CI passes before merging

## Validation Steps

Before finalizing changes, **always**:
1. ✅ Run `clojure -M:test` (all tests pass)
2. ✅ Verify CI pipeline passes on GitHub
3. ✅ Test manually in REPL if adding new features
4. ✅ Check that `kadi.db` is in `.gitignore` (never commit database file)

## Additional Resources

- **README.md**: Quick start guide with API examples
- **CLAUDE.md**: Detailed development guidelines for AI assistants
- **docs/CLOJURE_BOOTSTRAP_BRIEF.md**: Complete game specification and design decisions
- **Clojure Docs**: https://clojure.org/reference/documentation
- **Ring**: https://github.com/ring-clojure/ring
- **Reitit**: https://cljdoc.org/d/metosin/reitit

## Trust These Instructions

These instructions are based on actual project structure and tested commands. **Only search for additional information if**:
- These instructions are incomplete for your specific task
- You encounter an error not documented here
- Project structure has changed significantly

For most development tasks, the commands and patterns documented here are sufficient and proven to work.
