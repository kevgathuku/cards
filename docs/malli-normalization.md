# Malli Schema Normalization

## Overview

The application now uses [Malli](https://github.com/metosin/malli) for schema validation and normalization of domain objects. This ensures **consistent data types** throughout the application, regardless of whether data comes from:

- Event sourcing (rebuild-state-from-events)
- Database JSON deserialization  
- Direct API input

## Key Benefits

### 1. Type Consistency

**Before:** Status could be either keyword or string depending on source
```clojure
;; From events
{:status :live}  ; keyword

;; From database (after JSON roundtrip)
{:status "live"} ; string
```

**After:** Always normalized to keywords
```clojure
;; Both sources now return
{:status :live}  ; keyword (normalized)
```

### 2. Self-Documenting Schemas

```clojure
(def Game
  [:map
   [:status [:enum :lobby :live :finished]]
   [:players [:sequential Player]]
   [:turn Turn]
   [:zones Zones]
   ...])
```

### 3. Validation at Boundaries

```clojure
;; Validate game state
(schema/validate-game game)
;; => {:valid? true}

;; Or throw on invalid
(schema/validate-game! game)
;; => ExceptionInfo if invalid
```

## Usage Examples

### Normalizing Game State

```clojure
(require '[kadi.schema :as schema])

;; From database (strings)
(def db-game
  {:status "live"
   :players [{:id 1 :name "Alice" :status "normal"}]
   :turn {:direction "clockwise" :current-player-index 0}
   ...})

;; Normalize to keywords
(schema/normalize-game db-game)
;; => {:status :live
;;     :players [{:id 1 :name "Alice" :status :normal}]
;;     :turn {:direction :clockwise :current-player-index 0}
;;     ...}
```

### Automatic Normalization in DB Layer

All database functions now return normalized data:

```clojure
;; Get game by code
(db/get-game-by-code "ABC123")
;; => {:id 1 
;;     :short_code "ABC123"
;;     :state {:status :live  ; <- normalized keyword
;;             :players [...]
;;             ...}
;;     :state_sequence 5}

;; List games
(db/list-games)
;; => [{:state {:status :lobby ...}} ...]  ; <- all normalized

;; Create game
(db/create-game! {:player {...}})
;; => {:state {:status :lobby ...}}  ; <- normalized from event sourcing
```

## Schema Definitions

Located in `src/kadi/schema.clj`:

- **Game** - Core game state
- **Player** - Player data with status
- **Card** - Suit and rank
- **Turn** - Current player and direction
- **Zones** - Deck, played stack, hands
- **GameRow** - Database row with metadata

## Custom Transformers

### `string->keyword-transformer`
Coerces string values to keywords for enum-like fields (status, direction, suit, rank, etc.)

### `json-transformer`
Composite transformer for JSON roundtrip normalization:
- Strips extra keys
- Converts strings to appropriate types  
- Applies string->keyword transformation

## Integration Points

### Database Layer (`kadi.db`)
- `get-game-by-code` - Normalizes after fetch
- `list-games` - Normalizes all results
- `ensure-fresh-state` - Normalizes rebuilt state
- `create-game!` - Normalizes initial state
- `get-player-games` - Normalizes all player games

### Event Sourcing
- `rebuild-state-from-events` output is normalized before persistence

## Testing

Tests have been updated to expect normalized (keyword) values:

```clojure
;; Before
(is (= "lobby" (get-in game [:state :status])))  ; string comparison

;; After  
(is (= :lobby (get-in game [:state :status])))   ; keyword comparison
```

## Future Enhancements

1. **Input validation** - Validate API inputs before processing
2. **Coercion on write** - Ensure data going to DB is properly formatted
3. **Schema evolution** - Version schemas for backwards compatibility
4. **OpenAPI generation** - Generate API docs from Malli schemas
