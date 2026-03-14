# Malli Schema Normalization

## Overview

The application uses [Malli](https://github.com/metosin/malli) for schema validation and normalization of domain objects. This ensures **consistent data types** throughout the application, regardless of whether data comes from:

- Event sourcing (rebuild-state-from-events)
- Database JSON deserialization
- Direct API input

## Schema Inventory

All schemas live in `src/kadi/schema.clj`.

### Game Domain

| Schema | Description | Used for |
|--------|-------------|----------|
| `Game` | Core game state (status, players, zones, effects) | Normalization, validation |
| `GameRow` | Database row wrapping Game state | DB result normalization |
| `Player` | In-game player (id, name, status) | Part of Game |
| `Card` | Suit + rank | Normalization of event data |
| `Zones` | Deck, played-stack, hands | Part of Game |
| `Effect` | Union of effect types (penalty, suit-selected, etc.) | Part of Game |
| `GameStatus` | `:lobby`, `:live`, `:finished` | Enum in Game |
| `PlayerStatus` | `:normal`, `:penalty`, `:skip`, etc. | Enum in Player |
| `Direction` | `:clockwise`, `:counter-clockwise` | Enum in Game |
| `Suit` | `:hearts`, `:diamonds`, `:clubs`, `:spades` | Enum in Card/Effect |
| `Rank` | `"2"` through `"A"` | Enum in Card |

### Auth Domain

| Schema | Description | Used for |
|--------|-------------|----------|
| `Email` | Regex-validated email string | `valid-email?`, part of auth schemas |
| `AuthToken` | DB auth_tokens row | `valid-token?` validation |
| `DbPlayer` | DB players row (id, name, email, created_at) | Defined, not yet enforced |
| `SigninEmailRequest` | Input to `send-signin-email!` | Input validation |

## Custom Transformers

### `string->keyword-transformer`
Coerces string values to keywords for keyword fields (status, direction, suit, etc.)

### `json-transformer`
Composite transformer for JSON roundtrip normalization:
- Converts strings to appropriate types via `mt/string-transformer`
- Applies `string->keyword-transformer` for enum fields

## Current Usage

### Normalization (decode)

Used at database read boundaries to fix types after JSON deserialization:

- **`normalize-game`** — `m/decode` with `json-transformer`, plus `fix-hands-keys` for integer player-id map keys and manual effect field normalization
- **`normalize-game-row`** — wraps `normalize-game` for DB rows
- **`normalize-cards`** — normalizes card sequences from event data

Called in `kadi.db`: `get-game-by-code`, `list-games`, `ensure-fresh-state`, `get-player-games`.

### Validation (validate)

- **`validate-game` / `validate-game!`** — validate full game state against `Game` schema
- **`auth/valid-email?`** — delegates to `m/validate schema/Email`
- **`auth/valid-token?`** — validates DB record against `schema/AuthToken` before checking expiry/used
- **`auth/send-signin-email!`** — validates input against `schema/SigninEmailRequest`

## Pending Enforcement

See [Pending Malli Enforcement Plan](#pending-enforcement-plan) below.

---

## Pending Enforcement Plan

### Status

Malli is currently used for **normalization** (decode after JSON roundtrip) and **selective validation** (game state, auth email/token). Several boundaries still lack schema enforcement.

### Priority 1: Handler Input Validation

**Problem:** Handlers in `kadi.handlers` parse form params with string manipulation but don't validate against schemas. Invalid input falls through to game logic, which either silently misbehaves or produces unclear errors.

**Where:**

| Handler | Input | Schema to validate |
|---------|-------|--------------------|
| `send-signin-link` | email from form | Already uses `auth/valid-email?` (done) |
| `play-cards` | `ordered-cards` CSV, `declare-kadi` checkbox | New: `PlayCardsInput` |
| `select-suit` | `suit` string from form | Validate against `Suit` enum |
| `draw-card` | `maintain-kadi` checkbox | Simple boolean, low priority |
| `join-game-by-code` | `code` string from form | New: `ShortCode` (non-empty, uppercase) |

**Proposed schemas:**

```clojure
(def ShortCode
  "Game short code — non-empty uppercase alphanumeric."
  [:re #"^[A-Z0-9]+$"])

(def PlayCardsInput
  [:map
   [:player-id int?]
   [:cards [:sequential Card]]
   [:declare-kadi? boolean?]])

(def SelectSuitInput
  [:map
   [:suit Suit]])
```

**Approach:** Validate parsed input in handlers, return user-friendly flash error on failure. Don't throw — redirect with message.

### Priority 2: Event Data Validation

**Problem:** `db/append-event!` accepts arbitrary `event-data` maps. There's no schema enforcement on what goes into the event log. If a handler constructs bad event data, it gets persisted and replayed forever.

**Where:** Every handler that calls `db/append-event!`.

**Proposed schemas (one per event type):**

```clojure
(def GameCreatedEvent
  [:map
   [:player [:map [:id int?] [:name string?]]]
   [:short-code string?]
   [:event-id string?]
   [:timestamp inst?]])

(def JoinGameEvent
  [:map
   [:player [:map [:id int?] [:name string?]]]
   [:timestamp inst?]])

(def PlayCardsEvent
  [:map
   [:player-id int?]
   [:cards [:sequential Card]]
   [:declare-kadi? boolean?]
   [:hand-size-before int?]
   [:timestamp inst?]])

;; etc. for :start-game, :draw-card, :select-suit, :accept-penalty, :answer-question
```

**Approach:** Add a `validate-event-data!` function that dispatches on event type. Call it in `append-event!` (or in each handler before appending). Throw on invalid — this is a programming error, not a user error.

### Priority 3: DB Return Value Assertions

**Problem:** DB functions return raw JDBC result maps. If a column is added/removed/renamed, consumers silently get nil values. The `DbPlayer` schema is defined but not enforced anywhere.

**Where:**

| Function | Returns | Schema |
|----------|---------|--------|
| `db/get-player` | player row | `DbPlayer` |
| `db/get-player-by-email` | player row | `DbPlayer` |
| `db/create-player!` | player row | `DbPlayer` |
| `db/get-auth-token` | token row | `AuthToken` |

**Approach:** Add a `coerce-db-result` helper that validates (in dev) or decodes. For game rows this already happens via `normalize-game-row`. For player/token rows, it's missing.

**Note:** `valid-token?` in auth already validates the token record against `AuthToken`. The gap is `get-player` and friends.

### Priority 4: Game State Transition Assertions (Dev-Only)

**Problem:** `apply-action` returns new game state but doesn't validate it. A bug in an action handler could produce invalid state that only surfaces much later.

**Where:** `kadi.game/apply-action` (the multimethod).

**Approach:** Wrap `apply-action` in dev mode with post-condition validation:

```clojure
;; In dev mode, validate after every state transition
(defn apply-action-validated [state action]
  (let [result (apply-action state action)]
    (when (and result (dev-mode?))
      (schema/validate-game! result))
    result))
```

**Trade-off:** Adds overhead per action. Only enable in dev/test, not production. Could alternatively be a test-only middleware.

### Not Planned

- **Coercion on write** — Game state is always produced by pure functions from normalized input, so it's already correctly typed when serialized. Validating output is sufficient.
- **OpenAPI generation** — No JSON API; the app is server-rendered HTML with HTMX.
- **Schema evolution / versioning** — Event schemas are append-only. Old events have `apply-action` backward-compat aliases. No need for formal versioning yet.

### Implementation Order

1. **Handler input validation** — highest user-facing impact, catches bad form data early
2. **Event data validation** — prevents bad data from being permanently persisted
3. **DB return assertions** — catches schema drift, especially after migrations
4. **Dev-only state assertions** — safety net for game logic bugs
