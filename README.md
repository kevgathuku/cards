# Kadi

A multiplayer online card game built with Clojure, implementing "Poker" (a card game popular in Kenya, also known as "Kadi").

> **Note**: This is a rewrite from a previous Elixir/Phoenix implementation. The complete game specification and lessons learned are documented in [`docs/CLOJURE_BOOTSTRAP_BRIEF.md`](docs/CLOJURE_BOOTSTRAP_BRIEF.md).

## Quick Start

### Prerequisites

- [Clojure CLI](https://clojure.org/guides/install_clojure) (version 1.11+)
- Java 17+ (for running Clojure)

### Setup

```bash
# Clone the repo
git clone https://github.com/yourusername/kadi.git
cd kadi

# Download dependencies
clj -P

# Run tests
clj -M:test
```

### Running the Application

```bash
# Start the server
clj -M:run
```

Visit [`localhost:3000`](http://localhost:3000) in your browser.

### REPL Development

For the best development experience, start the REPL with the `:dev` alias to include development tools and the `user` namespace:

```bash
# Start interactive REPL with development tools
clj -M:dev:repl
```

Once the REPL starts, you can manage the application server directly:

```clojure
;; In REPL
(start-server)          ; Starts the server on port 3000 and initializes DB
(stop-server)           ; Stops the running server
(restart-server)        ; Stops, waits, and starts the server again (hot reload)
(start-server 3001)     ; Start on a custom port
```

You can also interact with the game logic directly for debugging:

```clojure
(require '[kadi.game :as game])

;; Create and manipulate game state (pure functions)
(def g (game/new-game {:id 1 :short-code "TEST" :created-by 1}))
(def g (game/add-player g {:id 1 :name "Alice"}))
...
```

For a completely automated startup, use the `:dev-repl` alias:
```bash
clj -M:dev-repl
```
This will start the server and the REPL in one command.

---

## Architecture

### Core Philosophy

```
Game state is a pure value (immutable map).
State transitions are pure functions: (state, action) -> state
Side effects (persistence, broadcasting) happen at the edges.
```

### Project Structure

```
├── deps.edn                        # Project dependencies & aliases
├── tests.edn                       # Kaocha test runner config
│
├── src/kadi/
│   ├── core.clj                    # Application entry point
│   ├── game.clj                    # Pure game state & transitions (apply-action multimethod)
│   ├── cards.clj                   # Card representation & utilities
│   ├── validation.clj              # Play validation rules (pure)
│   ├── schema.clj                  # Malli schemas for game state
│   ├── db.clj                      # SQLite persistence & event sourcing
│   ├── auth.clj                    # Email magic-link authentication
│   ├── server.clj                  # HTTP server (Ring)
│   ├── routes.clj                  # Route definitions (Reitit)
│   ├── handlers.clj                # Request handlers
│   └── views.clj                   # Server-rendered HTML (Hiccup + HTMX)
│
├── test/kadi/
│   ├── game_test.clj               # Core game logic tests
│   ├── play_actions_test.clj       # Card play action tests
│   ├── validation_test.clj         # Validation rule tests
│   ├── db_test.clj                 # Database integration tests
│   └── routes_auth_test.clj        # Auth route tests
│
├── dev/
│   └── user.clj                    # REPL development helpers (start/stop/restart-server)
│
├── resources/
│   └── migrations/
│       └── 001_initial.sql         # Database schema
│
└── docs/
    ├── CLOJURE_BOOTSTRAP_BRIEF.md  # Complete game specification & Elixir lessons
    ├── ARCHITECTURE_PLAN.md        # Architecture decisions
    └── ...                         # Feature specs (ace, jack, king, kadi-finishing, etc.)
```

### Database

SQLite with INTEGER primary keys. Single file: `kadi.db`

```bash
sqlite3 kadi.db ".tables"
sqlite3 kadi.db "SELECT * FROM games"
```

---

## Game Rules

### Card Types

| Rank | Match Rule | Combo | Effect | Can Start |
|------|------------|-------|--------|-----------|
| 2 | Suit/Rank | Yes | Draw 2 penalty | No |
| 3 | Suit/Rank | Yes | Draw 3 penalty | No |
| 4-7,9,10 | Suit/Rank | Yes | None | Yes |
| 8 | Suit/Rank | Q,8 | Question | Yes |
| J | Suit/Rank | J only | Skip N players | No |
| Q | Suit/Rank | Q,8 | Question | Yes |
| K | Suit/Rank | No | Reverse direction | Yes |
| A | Always | A only | Suit selection | Yes |

### Key Rules

- **Matching**: Play cards matching top card by suit OR rank
- **Combos**: Multiple cards of same rank (except King)
- **Aces**: Can always be played, trigger suit selection
- **Penalties**: 2/3 cards force next player to draw (can be blocked)
- **Questions**: Q/8 require an "answer" card or draw
- **Cardless**: Playing K/J/2/3 as last card triggers cardless state (not a win)

See [`docs/CLOJURE_BOOTSTRAP_BRIEF.md`](docs/CLOJURE_BOOTSTRAP_BRIEF.md) for complete rules.

---

## API

### Games

```bash
# List games in lobby
GET /api/games

# Create game
POST /api/games
{"player-id": 1}

# Get game state
GET /api/games/:id

# Join game
POST /api/games/:id/join
{"player-id": 2, "player-name": "Bob"}

# Start game
POST /api/games/:id/start

# Game action
POST /api/games/:id/action
{"type": "play-cards", "player-id": 1, "cards": [...]}
```

---

## Testing

```bash
# Run all tests
clj -M:test

# Run linter
clj -M:lint

# Tests are pure - no database setup required
```

---

## Previous Implementation

The Elixir/Phoenix implementation is preserved:

```bash
# View via tag
git show v1.0-elixir:lib/kadi/games/play_validator.ex

# Or checkout the archive branch
git checkout archive/elixir-implementation
```

---

## Contributing

1. Game logic changes go in `kadi.game` or `kadi.validation`
2. Keep side effects in `kadi.db` and `kadi.handlers`
3. All state transitions must go through `apply-action`
4. Write tests first - they're pure functions, easy to test
5. Run `clj -M:test` before submitting

---

## License

MIT License - see [LICENSE](LICENSE)
