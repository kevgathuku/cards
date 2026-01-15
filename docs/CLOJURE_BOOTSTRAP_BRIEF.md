# Kadi Card Game - Clojure Implementation Bootstrap Brief

> A comprehensive specification for rebuilding the Kadi card game in Clojure, incorporating all lessons learned from the Elixir/Phoenix/LiveView implementation.

## 1. Project Overview

**Kadi** (also known as "Poker" in Kenya) is a multiplayer turn-based card game. The game uses a standard 52-card deck where players take turns playing cards that match by suit or rank, with special cards introducing mechanics like skipping players, reversing direction, forcing draws, and asking "questions."

### Core Philosophy for Clojure Rewrite

```
Game state should be a pure value.
State transitions should be pure functions: (state, action) -> state
Side effects (persistence, broadcasting) should happen at the edges.
```

---

## 2. Game Rules - Complete Specification

### 2.1 Card Types and Effects

#### Regular Cards (4, 5, 6, 7, 9, 10)
- **Play Rule**: Must match top card by suit OR rank
- **Combo**: Multiple cards of same rank allowed (first must match top card)
- **Effects**: None
- **Can Start Game**: Yes

#### King (K)
- **Play Rule**: Must match top card by suit OR rank
- **Combo**: NOT allowed (single King only per turn)
- **Effects**: Reverses play direction (clockwise ↔ counter-clockwise)
- **2-Player Note**: Direction reversal has no practical effect (still alternates between same two players)
- **Triggers Cardless**: Yes (if last card in hand)
- **Can Start Game**: Yes (no direction reversal on start)

#### Jack (J)
- **Play Rule**: Must match top card by suit OR rank
- **Combo**: Allowed (all Jacks, first must match top)
- **Effects**: Skip N players where N = number of Jacks played
  - 1 Jack → skip 1 player
  - 2 Jacks → skip 2 players
  - 3 Jacks → skip 3 players
- **Triggers Cardless**: Yes (if last card in hand)
- **Can Start Game**: NO

#### Ace (A)
- **Play Rule**: Can ALWAYS be played (ignores all matching requirements)
- **Combo**: Multiple Aces allowed
- **Effects**:
  - Pauses game for suit selection
  - Selected suit becomes mandatory for next player
  - Can block ANY penalty (2 or 3)
- **Penalty Blocking**: When Ace blocks a penalty, record the blocked card's suit for chaining rules
- **Triggers Cardless**: No (game pauses for suit selection)
- **Can Start Game**: Yes (no suit selection on start)

#### 2 (Penalty Card)
- **Play Rule**: Must match top card by suit OR rank
- **Combo**: Multiple 2s allowed (creates single "draw 2" penalty, NOT additive)
- **Effects**: Next player must draw 2 cards OR block
- **Blocking**: Can only be blocked by another 2 or an Ace
- **Cross-Block Prevention**: 2 CANNOT block a 3 penalty
- **Triggers Cardless**: Yes (penalty still applies to next player)
- **Can Start Game**: NO

#### 3 (Penalty Card)
- **Play Rule**: Must match top card by suit OR rank
- **Combo**: Multiple 3s allowed (creates single "draw 3" penalty, NOT additive)
- **Effects**: Next player must draw 3 cards OR block
- **Blocking**: Can only be blocked by another 3 or an Ace
- **Cross-Block Prevention**: 3 CANNOT block a 2 penalty
- **Triggers Cardless**: Yes (penalty still applies to next player)
- **Can Start Game**: NO

#### Queen (Q) - Question Card
- **Play Rule**: Must match top card by suit OR rank
- **Combo**: Can combine with other Queens and 8s
- **Effects**: Asks a "question" - requires an answer card
- **Answer Required**: Non-question card matching the last question by suit/rank
- **Incomplete Question**: If played without answer, player must draw (turn does NOT advance until draw)
- **Triggers Cardless**: No
- **Can Start Game**: Yes (no question effect on start)

#### 8 - Question Card
- **Identical to Queen** - can be mixed with Queens in combos
- **Can Start Game**: Yes (no question effect on start)

### 2.2 Valid Play Rules

```clojure
;; Pseudo-code for validation logic

(defn valid-play? [cards top-card game-state]
  (let [first-card (first cards)
        penalty-active? (get-in game-state [:penalty :active])
        action-suit (get-in game-state [:action-suit])]
    (cond
      ;; Aces can always be played
      (all-aces? cards) true

      ;; During active penalty, only matching penalty cards or Aces allowed
      penalty-active? (or (ace? first-card)
                          (valid-penalty-block? cards game-state))

      ;; With action-suit set (from Ace), must match that suit
      action-suit (matches-suit? first-card action-suit)

      ;; Standard matching: suit or rank
      :else (or (matches-suit? first-card top-card)
                (matches-rank? first-card top-card)))))
```

### 2.3 Turn Order and Direction

```clojure
(defn next-player-index [current-index player-count direction skip-count]
  (let [offset (case direction
                 :clockwise skip-count
                 :counter-clockwise (- skip-count))]
    (mod (+ current-index offset player-count) player-count)))
```

**Key Insight**: Direction is stored even in 2-player games (for consistency), but telemetry should note it as "neutral" since it has no practical effect.

### 2.4 Penalty System

```clojure
;; Penalty state structure
{:active true/false
 :type :two/:three/nil  ; NOT the count, just the type
 :target-player-id int/nil  ; INTEGER foreign key
 :blocked-suit nil/:hearts/:diamonds/:clubs/:spades}

;; Key lesson: Penalties are NOT additive
;; Multiple 2s = still draw 2 cards
;; Multiple 3s = still draw 3 cards
```

**Penalty Resolution Flow**:
1. Player's turn begins with active penalty targeting them
2. Player can: block with matching penalty card, block with Ace, or accept
3. If accepted: auto-draw N cards, clear penalty, advance turn
4. If blocked with Ace: clear penalty, set blocked-suit for chaining rules
5. If blocked with matching card: transfer penalty to next player

### 2.5 Question Card Flow

```clojure
;; Question detection
(defn question-cards? [cards]
  (every? #(#{"Q" "8"} (:rank %)) cards))

(defn complete-question? [cards]
  (let [questions (take-while #(#{"Q" "8"} (:rank %)) cards)
        answers (drop (count questions) cards)]
    (and (seq questions)
         (seq answers)
         (not (question-cards? answers)))))

;; Incomplete question: turn does NOT advance
;; Player must draw one card to "answer"
;; After draw, turn advances
```

### 2.6 Cardless State

**Critical Lesson**: Cardless is NOT a winning condition!

- Triggered by: Playing K, J, 2, or 3 as last card
- NOT triggered by: Regular cards, Aces, Q, 8 (these require follow-up actions)
- Effect: Player marked as "cardless", game continues
- Reset: When cardless player draws a card, status returns to normal

### 2.7 Starting Card Selection

```clojure
(def invalid-starting-ranks #{"J" "2" "3"})

(defn valid-starting-card? [card]
  (not (invalid-starting-ranks (:rank card))))

;; Valid starters: 4-10, K, A, Q, 8
;; Invalid starters: J, 2, 3 (would cause effects on empty game state)
```

### 2.8 Deck Recycling

When deck is empty and player needs to draw:
1. Take all cards from played stack EXCEPT the top card
2. Shuffle these cards
3. Return them to deck
4. Draw proceeds normally

**Edge Case - Anomaly Skip**:
- If only 1 card in played stack (top card), cannot recycle
- Player is "skipped" due to inability to draw
- Turn advances to next player
- Broadcast anomaly notification to all players

---

## 3. Data Model

### 3.1 Core State Shape (Immutable)

```clojure
(def initial-game-state
  {:id 1                ; INTEGER primary key (auto-increment)
   :short-code "ABC123"
   :status :lobby       ; :lobby | :live

   ;; Players (ordered by join time for turn order)
   :players [{:id 1              ; INTEGER primary key
              :name "Player 1"
              :status :normal    ; :normal | :cardless
              :hand []}]

   ;; Turn management
   :current-player-index 0
   :direction :clockwise  ; :clockwise | :counter-clockwise

   ;; Card locations
   :deck []           ; cards in draw pile (ordered)
   :played-stack []   ; cards played (last = top card)

   ;; Special states
   :action {:type nil          ; :select-suit | nil
            :suit nil}         ; required suit from Ace play
   :penalty {:active false
             :type nil         ; :two | :three
             :target-player-id nil  ; INTEGER reference
             :blocked-suit nil} ; for penalty chaining after Ace block

   ;; For question cards
   :awaiting-answer false      ; player must draw to answer

   ;; Timestamps
   :created-at (instant)
   :updated-at (instant)})
```

**ID Strategy**: Use INTEGER with auto-increment for all primary keys. SQLite's `INTEGER PRIMARY KEY` is an alias for the rowid and auto-increments. Only use BIGINT if you expect >2 billion records (unlikely for a card game).

### 3.2 Card Representation

```clojure
(def suits #{:hearts :diamonds :clubs :spades})
(def ranks #{"2" "3" "4" "5" "6" "7" "8" "9" "10" "J" "Q" "K" "A"})

(defn make-card [suit rank]
  {:suit suit :rank rank})

;; 52 unique cards, can be referenced by [suit rank] tuple
;; No need for card IDs if using value equality
```

### 3.3 Event/Action Types

```clojure
;; All state transitions as data
(def action-types
  #{:join-game
    :start-game
    :play-cards       ; {:player-id, :cards}
    :draw-card        ; {:player-id}
    :answer-question  ; {:player-id} - draw one card to answer
    :select-suit      ; {:player-id, :suit} - after Ace play
    :accept-penalty}) ; {:player-id} - accept and draw penalty cards
```

---

## 4. State Transition Functions (Pure)

### 4.1 Core Reducer Pattern

```clojure
(defmulti apply-action (fn [state action] (:type action)))

(defmethod apply-action :play-cards [state {:keys [player-id cards]}]
  (let [validated (validate-play state player-id cards)]
    (if (:valid? validated)
      (-> state
          (remove-cards-from-hand player-id cards)
          (add-cards-to-played cards)
          (apply-card-effects cards)
          (maybe-advance-turn cards))
      (assoc state :error validated))))

(defmethod apply-action :draw-card [state {:keys [player-id]}]
  (-> state
      (draw-top-deck-card player-id)
      (advance-turn)))

;; etc.
```

### 4.2 Effect Application (Lesson: Order Matters)

```clojure
(defn apply-card-effects [state cards]
  (let [ranks (map :rank cards)]
    (cond-> state
      (some #{"K"} ranks) (reverse-direction)
      (some #{"J"} ranks) (calculate-skip (count (filter #{"J"} ranks)))
      (some #{"A"} ranks) (set-awaiting-suit-selection)
      (some #{"2"} ranks) (create-penalty :two)
      (some #{"3"} ranks) (create-penalty :three)
      (question-without-answer? cards) (set-awaiting-answer))))
```

---

## 5. Architectural Lessons Learned

### 5.1 What Worked Well (Keep These)

1. **Database as source of truth** for multiplayer consistency
   - All players see same state
   - Survives server restarts
   - No split-brain issues

2. **Broadcast-only UI updates**
   - Don't mutate local state on action
   - Wait for server confirmation broadcast
   - All clients stay synchronized

3. **Atomic transactions for state changes**
   - All-or-nothing updates
   - No partial states visible
   - Use database transactions or STM

4. **Pure validation functions**
   - `PlayValidator` was entirely pure
   - Easy to test with no setup
   - Reusable across contexts

5. **Telemetry for observability**
   - Track all game events
   - Useful for debugging and analytics
   - Can replay games from event log

### 5.2 What to Improve (Clojure Opportunity)

1. **Explicit state transitions**
   - Elixir: State changes scattered across Ecto changesets
   - Clojure: Single reducer function, all transitions visible

2. **Time-travel debugging**
   - Keep history of states: `(atom [initial-state state-2 state-3 ...])`
   - Trivial to implement with persistent data structures

3. **Speculative execution**
   - Test "what if" scenarios without database
   - Useful for AI opponents
   - Just call pure functions on hypothetical state

4. **Simplified testing**
   - No database sandbox needed
   - Pure functions test with plain data
   - Property-based testing natural fit

5. **Event sourcing as default**
   - Store actions, derive state
   - Perfect audit trail built-in
   - Replay any point in game history

### 5.3 Anti-Patterns to Avoid

1. **Don't mix validation with persistence**
   - Validation should be pure
   - Persistence is a side effect at the edge

2. **Don't make penalties additive**
   - Multiple 2s = draw 2 (not 4, 6, 8...)
   - This was a design decision, not obvious from rules

3. **Don't forget 2-player edge cases**
   - Direction reversal is meaningless
   - Skip-1 returns to same player
   - Mark these as "neutral" in telemetry

4. **Don't advance turn on incomplete questions**
   - Q/8 without answer keeps player's turn active
   - Only advance after draw-to-answer

5. **Don't treat cardless as winning**
   - Game continues
   - Player can draw back cards
   - Need separate end-game logic (not implemented yet)

6. **Don't allow cross-blocking penalties**
   - 2 blocks only 2
   - 3 blocks only 3
   - Ace blocks any

---

## 6. Real-Time Requirements

### 6.1 Events to Broadcast

```clojure
(def broadcast-events
  #{:player-joined
    :game-started
    :cards-played
    :card-drawn
    :direction-changed
    :player-skipped
    :penalty-created
    :penalty-blocked
    :penalty-accepted
    :suit-selected
    :question-asked
    :question-answered
    :player-cardless
    :deck-recycled
    :anomaly-skip})
```

### 6.2 Recommended Architecture

```
                    ┌─────────────────┐
                    │   HTTP/WS API   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Command Handler │
                    │  (side effects)  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
    ┌─────────▼─────┐ ┌──────▼──────┐ ┌─────▼─────┐
    │   Validate    │ │   Apply     │ │  Persist  │
    │   (pure)      │ │   (pure)    │ │  (effect) │
    └───────────────┘ └─────────────┘ └───────────┘
                             │
                    ┌────────▼────────┐
                    │    Broadcast    │
                    │    (effect)     │
                    └─────────────────┘
```

### 6.3 Client State

Minimal client state - derive everything from server broadcasts:

```clojure
;; Client only needs to track:
{:game-id 123        ; INTEGER
 :player-id 456      ; INTEGER
 :selected-cards #{}}  ; local UI selection state

;; Everything else comes from server
```

---

## 7. Testing Strategy

### 7.1 Unit Tests (Pure Functions)

```clojure
(deftest play-king-reverses-direction
  (let [state (-> (new-game)
                  (add-players ["A" "B" "C"])
                  (start-game))
        king {:suit :hearts :rank "K"}
        result (apply-action state {:type :play-cards
                                    :player-id (current-player-id state)
                                    :cards [king]})]
    (is (= :counter-clockwise (:direction result)))))

;; No database, no setup, just data
```

### 7.2 Property-Based Tests

```clojure
(defspec playing-ace-always-valid 100
  (prop/for-all [game-state gen-game-state
                 ace gen-ace]
    (let [result (validate-play game-state (:current-player-id game-state) [ace])]
      (:valid? result))))
```

### 7.3 Integration Tests

```clojure
;; Test full game flows
(deftest complete-game-flow
  (let [events [{:type :join-game :player-id p1}
                {:type :join-game :player-id p2}
                {:type :start-game}
                {:type :play-cards :player-id p1 :cards [...]}
                ;; ...
                ]
        final-state (reduce apply-action initial-state events)]
    (is (= expected-state final-state))))
```

### 7.4 What NOT to Test (Learned from Over-Testing)

- Don't test same scenario through multiple paths
- Don't create wrapper functions just for testability
- Don't test framework behavior (database writes work)
- Feature tests should test unique behaviors only

---

## 8. Database Schema (SQLite)

### 8.1 Why SQLite

- **Single file** - no server process, trivial deployment
- **Embedded** - ships with your app, zero configuration
- **Fast enough** - handles thousands of concurrent readers
- **JSON support** - `json()` and `json_extract()` functions built-in
- **WAL mode** - enables concurrent reads during writes

For a turn-based card game with modest write throughput, SQLite is ideal.

### 8.2 Schema

```sql
-- Enable WAL mode for better concurrency
PRAGMA journal_mode=WAL;

-- Games
CREATE TABLE games (
  id INTEGER PRIMARY KEY,  -- Auto-increments in SQLite
  short_code TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL DEFAULT 'lobby',
  state TEXT NOT NULL,  -- JSON string (use json() for validation)
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Players
CREATE TABLE players (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT UNIQUE,
  password_hash TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Game Players (join table)
CREATE TABLE game_players (
  id INTEGER PRIMARY KEY,
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  player_id INTEGER NOT NULL REFERENCES players(id),
  joined_at TEXT NOT NULL DEFAULT (datetime('now')),
  status TEXT NOT NULL DEFAULT 'normal',  -- 'normal' | 'cardless'
  UNIQUE(game_id, player_id)
);

-- Game Events (for event sourcing)
CREATE TABLE game_events (
  id INTEGER PRIMARY KEY,
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  sequence_number INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  event_data TEXT NOT NULL,  -- JSON string
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(game_id, sequence_number)
);

-- Indexes
CREATE INDEX idx_games_short_code ON games(short_code);
CREATE INDEX idx_game_events_game_id ON game_events(game_id);
CREATE INDEX idx_game_players_game_id ON game_players(game_id);
```

### 8.3 SQLite-Specific Notes

- **No JSONB**: Use `TEXT` and `json()` function for validation
- **No BIGINT needed**: INTEGER in SQLite is 64-bit signed (-9223372036854775808 to +9223372036854775807)
- **Timestamps as TEXT**: Use ISO8601 strings, SQLite has no native datetime type
- **Foreign keys**: Must enable with `PRAGMA foreign_keys=ON` per connection
- **Concurrent writes**: Only one writer at a time; use transactions and retry on `SQLITE_BUSY`

### 8.4 Event Sourcing Approach (Recommended)

```clojure
;; Store events, derive state
(defn game-state [game-id]  ; game-id is INTEGER
  (let [events (db/get-events game-id)]
    (reduce apply-action initial-game-state events)))

;; Or cache computed state for performance
(defn game-state-cached [game-id]
  (or (cache/get game-id)
      (let [state (game-state game-id)]
        (cache/put game-id state)
        state)))
```

---

## 9. Technology Recommendations

### 9.1 Core Stack

| Layer | Recommendation | Rationale |
|-------|---------------|-----------|
| Web Server | Ring + Reitit | Simple, composable |
| WebSockets | Sente | Mature, ClojureScript compatible |
| Database | SQLite + next.jdbc | Embedded, zero-config, single file |
| State Management | Atoms + Persistent DS | Natural fit for game state |
| Validation | Malli or Spec | Schema + validation |
| Frontend | ClojureScript + Reagent | Shared code, reactive |
| JSON | Cheshire or jsonista | Fast JSON encoding for SQLite TEXT columns |

### 9.2 SQLite Libraries

```clojure
;; deps.edn
{:deps {com.github.seancorfield/next.jdbc {:mvn/version "1.3.909"}
        org.xerial/sqlite-jdbc {:mvn/version "3.44.1.0"}}}
```

**Connection setup**:
```clojure
(def db-spec {:dbtype "sqlite" :dbname "kadi.db"})

;; Enable foreign keys and WAL mode
(defn init-db! []
  (jdbc/execute! db-spec ["PRAGMA foreign_keys=ON"])
  (jdbc/execute! db-spec ["PRAGMA journal_mode=WAL"]))
```

### 9.3 Hosting Considerations

- **Single instance**: SQLite is best with one writer; scale horizontally only if using read replicas (Litestream) or switching to PostgreSQL later
- **JVM startup**: Consider GraalVM native-image for faster cold starts
- **File location**: Put SQLite file on fast local storage, not network drives
- **Backups**: Simple file copy (or Litestream for continuous replication)
- **Migration path**: Schema is similar enough to PostgreSQL if you outgrow SQLite

---

## 10. Migration Path

### 10.1 Phase 1: Core Game Logic
1. Implement card representation
2. Implement validation functions
3. Implement state transitions (reducer)
4. Write comprehensive tests

### 10.2 Phase 2: Persistence
1. Set up database schema
2. Implement event sourcing
3. Add game session CRUD

### 10.3 Phase 3: Real-Time
1. Add WebSocket support
2. Implement pub/sub for game rooms
3. Build broadcast system

### 10.4 Phase 4: UI
1. ClojureScript frontend
2. Reagent components
3. WebSocket integration

### 10.5 Phase 5: Polish
1. Authentication
2. Error handling
3. Reconnection logic
4. Mobile responsiveness

---

## 11. Quick Reference: Card Rules Table

| Rank | Match Rule | Combo | Effect | Blocks | Cardless | Start |
|------|------------|-------|--------|--------|----------|-------|
| 2 | Suit/Rank | Yes | Draw 2 penalty | 2 only | Yes | No |
| 3 | Suit/Rank | Yes | Draw 3 penalty | 3 only | Yes | No |
| 4-7,9,10 | Suit/Rank | Yes | None | - | No | Yes |
| 8 | Suit/Rank | Q,8 | Question | No | No | Yes |
| J | Suit/Rank | J | Skip N | No | Yes | No |
| Q | Suit/Rank | Q,8 | Question | No | No | Yes |
| K | Suit/Rank | No | Reverse | No | Yes | Yes |
| A | Always | A | Suit select | All | No | Yes |

---

## 12. Appendix: State Transition Diagram

```
     ┌─────────────────────────────────────────────────────┐
     │                                                     │
     ▼                                                     │
  ┌──────┐    start    ┌──────┐                           │
  │Lobby │────────────▶│ Live │◀──────────────────────────┤
  └──────┘             └──┬───┘                           │
                          │                               │
          ┌───────────────┼───────────────┐               │
          │               │               │               │
          ▼               ▼               ▼               │
    ┌──────────┐    ┌──────────┐    ┌──────────┐         │
    │Play Card │    │Draw Card │    │  Accept  │         │
    └────┬─────┘    └────┬─────┘    │ Penalty  │         │
         │               │          └────┬─────┘         │
         │               │               │               │
    ┌────┴────┐          │               │               │
    │         │          │               │               │
    ▼         ▼          ▼               ▼               │
┌───────┐ ┌───────┐ ┌─────────┐    ┌─────────┐          │
│Select │ │Answer │ │Advance  │    │Draw N   │          │
│ Suit  │ │  Q    │ │  Turn   │───▶│ Cards   │──────────┤
└───┬───┘ └───┬───┘ └─────────┘    └─────────┘          │
    │         │          ▲                               │
    │         │          │                               │
    └─────────┴──────────┴───────────────────────────────┘
```

---

*This document captures the complete game specification and architectural lessons from the Elixir/Phoenix/LiveView implementation. Use it as the authoritative reference for the Clojure rewrite.*
