# Plan: Fix Gaps 1-4 (Cardless Enforcement, Deck Recycling, Anomaly Skip, Real-Time Updates)

## Context

The Clojure Kadi implementation has all core card mechanics working, but 4 gaps remain compared to the Elixir spec. Cardless players aren't forced to draw, the deck doesn't auto-recycle on draw, the game can get stuck when the deck is exhausted, and the game play page has no real-time updates (players must manually reload).

---

## Phase 1: Schema Fix + Deck Recycling + Anomaly Skip (GAPs 2 & 3)

### 1a. Add `:cardless` to PlayerStatus enum
**File**: `src/kadi/schema.clj:34-35`

`:cardless` is used by `check-cardless` but is missing from the `PlayerStatus` enum. This can cause schema normalization to strip or reject cardless values.

```
[:enum :normal :penalty :skip :selecting-suit :kadi]
→ [:enum :normal :penalty :skip :selecting-suit :kadi :cardless]
```

### 1b. Remove hard deck-empty rejection from `validate-draw`
**File**: `src/kadi/game.clj:402-408`

Remove the `(empty? deck) → error` check. The command layer will handle recycling.

### 1c. Update `draw-card-cmd` to recycle before drawing
**File**: `src/kadi/game.clj:410-417`

Follow the same pattern as `answer-question-cmd` (line 487-497):
- If deck empty → `recycle-played-stack`
- If still empty → skip turn (anomaly), no draw, but still advance turn and return `{:ok ...}`

### 1d. Update `accept-penalty` to recycle during penalty draws
**File**: `src/kadi/game.clj:343-356`

Each card draw in the penalty loop should try recycling if deck is empty before drawing. This prevents partial penalty draws when the deck runs out mid-penalty.

### 1e. Update `apply-action :draw-card` for event replay consistency
**File**: `src/kadi/game.clj:562-566`

Add recycle-before-draw logic to match the command path, so event replay produces identical state.

### 1f. Tests
- Draw from empty deck triggers recycle and succeeds
- Draw when deck empty AND played stack has only 1 card → anomaly skip (turn advances, no draw, no error)
- Accept-penalty recycles mid-draw if needed

---

## Phase 2: Cardless Auto-Draw Enforcement (GAP 1)

### 2a. Reject plays from cardless players
**File**: `src/kadi/validation.clj:148-213` (`validate-play`)

Add early check in the `cond` chain (after turn check, before card checks): if player status is `:cardless`, return `{:valid? false :reason "You must draw a card first (cardless)"}`.

The player status is available via `(:players state)` — find the player by `player-id` and check `:status`.

### 2b. Skip cardless players in Jack skip counting
**File**: `src/kadi/game.clj:129-139` (`next-player-index`)

The current implementation uses simple modular arithmetic. Per the Jack card spec (line 24): "Cardless players are excluded from skip counting to prevent soft-locks."

Replace with a loop that steps through players one at a time, skipping cardless players without decrementing the skip counter. Include a max-iterations safety guard to prevent infinite loops if all players are cardless.

### 2c. Cardless UI in game play page
**File**: `src/kadi/views.clj` (`game-play-page`, lines 445-535)

When it's a cardless player's turn:
- Show a prominent "You are cardless — you must draw" message
- Show only the Draw Card button (hide play form / other action buttons)
- Add a "Cardless" badge in the player list (alongside the existing KADI badge)

### 2d. Tests
- Cardless player's play attempt is rejected with error message
- Cardless player can draw and returns to `:normal`
- Jack skip skips over cardless players in 3-player game
- Cardless player draw resets status to `:normal`

---

## Phase 3: Real-Time Updates via HTMX Polling (GAP 4)

### 3a. Extract game content into a fragment function
**File**: `src/kadi/views.clj`

Create `game-play-content` that renders all game play UI (top card, players, hand, effects, actions) **without** the layout wrapper. The function returns an HTML string.

The root element uses `hx-swap="outerHTML"` so it replaces itself including HTMX attributes:
```clojure
[:div {:id "game-content"
       :hx-get (when should-poll? (str "/games/" code "/state"))
       :hx-trigger (when should-poll? "every 2s")
       :hx-swap "outerHTML"}
 ;; ... all game content ...]
```

**Only poll when it's NOT the current player's turn** — this prevents resetting card selection state while the player is interacting. When the player submits an action (POST → redirect), the fresh page load will resume polling if it's now the opponent's turn.

### 3b. Refactor `game-play-page` to use fragment
**File**: `src/kadi/views.clj`

`game-play-page` becomes:
```clojure
(layout {:title ... :player ...}
  (raw-string (game-play-content ctx)))
```

### 3c. Add fragment handler
**File**: `src/kadi/handlers.clj`

New handler `get-game-state-fragment` that returns `game-play-content` HTML fragment (200 with `text/html`).

### 3d. Add route
**File**: `src/kadi/routes.clj`

Add `["/:code/state" {:get handler}]` alongside existing game routes.

### 3e. Manual testing
Start the app, open 2 browser windows as different players, verify that moves appear within ~2 seconds on the opponent's screen without manual refresh. Verify polling stops when game is finished.

---

## Critical Files

| File | Changes |
|------|---------|
| `src/kadi/schema.clj` | Add `:cardless` to PlayerStatus |
| `src/kadi/game.clj` | `validate-draw`, `draw-card-cmd`, `accept-penalty`, `next-player-index`, `apply-action :draw-card` |
| `src/kadi/validation.clj` | Add cardless check to `validate-play` |
| `src/kadi/views.clj` | Extract `game-play-content`, cardless UI, HTMX polling |
| `src/kadi/handlers.clj` | Add `get-game-state-fragment` handler |
| `src/kadi/routes.clj` | Add `/:code/state` route |
| `test/kadi/game_test.clj` | Tests for recycling, anomaly skip, cardless enforcement |
| `test/kadi/validation_test.clj` | Test cardless play rejection |

## Verification

1. `clj -M:test` — all existing + new tests pass
2. Manual: start app, create 2-player game, verify:
   - Play K/J/2/3 as last card → cardless → forced to draw on next turn
   - Draw from empty deck → auto-recycles → draw succeeds
   - Opponent moves appear within ~2s without refresh
   - Game finished → polling stops
