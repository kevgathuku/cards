# Data Model: King Card Reversal

## Overview
Extends existing schemas to support direction tracking, player status enum (incl. cardless), optimistic locking, and structured event emission (non-persistent). No new persistent event table Phase 1.

## Entities

### game_sessions (existing)
| Field | Type | Notes |
|-------|------|-------|
| id | uuid/int (existing) | PK |
| short_code | string | Unique game join code |
| status | string | {"lobby","live"} existing; future: "finished" (Phase 2) |
| direction | string | New; {"clockwise","counter_clockwise"}, default "clockwise" |
| lock_version | integer | (Optional future) retained only if broader concurrent mutation patterns emerge; not required for King turn gating |
| created_by_id | fk -> players | existing |
| current_turn_player_id | fk -> players | updated atomically on King play |
| top_card_id | fk -> cards | updated when King played |
| inserted_at/updated_at | utc_datetime | existing |

Validation additions:
- `validate_inclusion(:direction, ["clockwise","counter_clockwise"])`
- Migration adds CHECK constraint: `direction IN ('clockwise','counter_clockwise')`
*Note*: `optimistic_lock/3` not currently applied; single-player turn gating prevents simultaneous conflicting writes.

### game_session_players (existing)
| Field | Type | Notes |
|-------|------|-------|
| id | pk | |
| game_session_id | fk -> game_sessions | |
| player_id | fk -> players | |
| status | string/enum | New; allowed {"normal","cardless"}, default "normal"; set to "cardless" when last card is King; reset to "normal" after forced draw |
| inserted_at/updated_at | timestamps | |

### deck_cards (existing)
No structural change Phase 1. Invariant enforced by logic: highest `order_index` with location_type=played_stack corresponds to `game_sessions.top_card_id`.

### cards (existing)
Contains rank "king"; unchanged.

### (Virtual) Events
Emitted via Telemetry only; not persisted:
- direction_change
- cardless_entered
- anomaly_skip

Metadata schema (non-DB):
```elixir
%{
  game_id: game_session.id,
  player_id: acting_player.id,
  previous_direction: "clockwise",
  new_direction: "counter_clockwise",
  card_id: king_card.id,
  timestamp: DateTime.utc_now()
}
```

## Relationships
- game_session has many game_session_players
- game_session has one deck; deck has many deck_cards; deck_cards belong to cards
- top_card foreign key references cards (must match played_stack top)

## State Transitions

### Direction
`clockwise` -> `counter_clockwise` on valid King play; toggles again on subsequent valid King.

### Player Status
"normal" -> "cardless" when player plays King as last card; "cardless" -> "normal" after automatic draw transaction completes.

### Turn Progression
Current turn player -> next player according to `direction` unless anomaly_skip; anomaly_skip advances turn without draw.

## Invariants
1. Only one King card processed per turn (`FR-005`).
2. `direction` always one of allowed values.
3. If player status is "cardless" then they have zero cards AND King was last played by them (previous action) until draw occurs.
4. After draw for cardless player, cardless set false and new card added to hand; cannot play drawn card same turn.
5. Top card of played stack remains when deck recycling occurs.

## Migration Summary
1. Migration A: Alter game_sessions add direction (string, default 'clockwise'), (optionally lock_version if future concurrency arises), CHECK constraint.
2. Migration B: Alter game_session_players add status (string) default 'normal' NOT NULL; add CHECK constraint `status IN ('normal','cardless')`.

## Validation & Error Modes
- Play attempt invalid: return `{:error, :invalid_play}` with reason atoms (`:mismatch`, `:multiple_kings`, `:cardless_wait`) for granular UI messaging.
- Optimistic lock failure: retry up to 3 times then `{:error, :conflict}`.
- Anomaly (no drawable cards after recycle): emit anomaly_skip event; UI banner; return `{:ok, :skipped}`.

## Future (Phase 2 Considerations)
- Add finished status to game_sessions.
- DB trigger / materialized view for top card integrity.
- Persistent event audit table if fairness metrics required.
