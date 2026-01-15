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

```bash
# Start REPL with nREPL for editor connection
clj -M:repl
```

```clojure
;; In REPL
(require '[kadi.game :as game])
(require '[kadi.db :as db])

;; Initialize database
(db/init!)

;; Create and manipulate game state (pure functions)
(def g (game/new-game {:id 1 :short-code "TEST" :created-by 1}))
(def g (game/add-player g {:id 1 :name "Alice"}))
(def g (game/add-player g {:id 2 :name "Bob"}))
(def g (game/start-game g {}))

;; Play cards
(game/apply-action g {:type :play-cards :player-id 1 :cards [...]})
```

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
src/kadi/
├── core.clj        # Application entry point
├── game.clj        # Pure game state & transitions
├── cards.clj       # Card representation & utilities
├── validation.clj  # Play validation (pure)
├── db.clj          # SQLite persistence
├── server.clj      # HTTP server
├── routes.clj      # API routes
└── handlers.clj    # Request handlers

test/kadi/
└── game_test.clj   # Pure function tests (no DB needed)

docs/
└── CLOJURE_BOOTSTRAP_BRIEF.md  # Complete game specification
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
