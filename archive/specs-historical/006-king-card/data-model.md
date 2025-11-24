# Data Model: King Card Reversal

## Overview
Extends existing schemas to support direction tracking, player status enum (incl. cardless), and structured event emission (non-persistent). No new persistent event table Phase 1.

**Implementation Guide**: See `quickstart.md` for step-by-step instructions.  
**Contract Details**: See `contracts/events.md` for event schemas.  
**Existing Schemas**: 
- `lib/kadi/games/game_session.ex` (lines 1-30)
- `lib/kadi/games/game_session_player.ex` (lines 1-20)

## Entities

### game_sessions (existing)
**File**: `lib/kadi/games/game_session.ex`  
**Migration**: See quickstart.md §1.1

| Field | Type | Notes |
|-------|------|-------|
| id | pk | PK |
| short_code | string | Unique game join code |
| status | string | {"lobby","live"} existing; future: "finished" (Phase 2) |
| direction | string | **NEW**; {"clockwise","counter_clockwise"}, default "clockwise" |
| lock_version | integer | (Optional/dormant) retained only if broader concurrent mutation patterns emerge; **not required for King turn gating** |
| created_by_id | fk -> players | existing |
| current_turn_player_id | fk -> players | updated atomically on King play |
| top_card_id | fk -> cards | updated when King played |
| inserted_at/updated_at | utc_datetime | existing |

**Validation additions** (see quickstart.md §2.1):
- `validate_inclusion(:direction, ["clockwise","counter_clockwise"])`
- Migration adds CHECK constraint: `direction IN ('clockwise','counter_clockwise')`

**Note**: Turn gating via `validate_current_turn/2` (lib/kadi/card_games.ex:715) prevents simultaneous conflicting writes, eliminating need for optimistic locking.

### game_session_players (existing)
**File**: `lib/kadi/games/game_session_player.ex`  
**Migration**: See quickstart.md §1.2

| Field | Type | Notes |
|-------|------|-------|
| id | pk | |
| game_session_id | fk -> game_sessions | |
| player_id | fk -> players | |
| status | string/enum | **NEW**; allowed {"normal","cardless"}, default "normal"; set to "cardless" when last card is King; reset to "normal" after forced draw |
| inserted_at/updated_at | timestamps | |

**Validation** (see quickstart.md §2.2):
- `validate_inclusion(:status, ["normal", "cardless"])`

### deck_cards (existing)
No structural change Phase 1. Invariant enforced by logic: highest `order_index` with location_type=played_stack corresponds to `game_sessions.top_card_id`.

### cards (existing)
Contains rank "king"; unchanged.

### (Virtual) Events
**Not persisted in database** - emitted via Telemetry only.  
**Full contract**: See `contracts/events.md` for complete metadata schemas and examples.

Emitted events:
- `[:kadi, :king, :direction_change]` - When King reverses direction
- `[:kadi, :king, :cardless_entered]` - When player plays King as last card
- `[:kadi, :king, :anomaly_skip]` - When deck exhaustion forces skip

**Example metadata structure** (see events.md §3 for full details):
```elixir
%{
  game_id: game_session.id,
  player_id: acting_player.id,
  previous_direction: "clockwise",
  new_direction: "counter_clockwise",
  card_id: king_card.id,
  neutral: false,  # true for 2-player games (FR-009)
  timestamp: DateTime.utc_now()
}
```

**Implementation**: See quickstart.md §5 for telemetry helper functions.

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
**Detailed implementation**: See quickstart.md §1 for complete migration code.  
**Migration directory**: `priv/repo/migrations/`  
**Naming convention**: `YYYYMMDDHHMMSS_description.exs` (see existing migrations for pattern)

1. **Migration A**: Add `direction` field to `game_sessions`
   - File: `YYYYMMDDHHMMSS_add_direction_to_game_sessions.exs`
   - Fields: `direction` (string, default 'clockwise', NOT NULL)
   - Constraint: CHECK `direction IN ('clockwise','counter_clockwise')`
   - Template: See `priv/repo/migrations/20251107172808_add_top_card_to_game_sessions.exs`

2. **Migration B**: Add `status` field to `game_session_players`
   - File: `YYYYMMDDHHMMSS_add_status_to_game_session_players.exs`
   - Fields: `status` (string, default 'normal', NOT NULL)
   - Constraint: CHECK `status IN ('normal','cardless')`
   - Template: See `priv/repo/migrations/20251029211040_add_status_to_game_sessions.exs`

**Note**: `lock_version` field is optional/dormant - not included in Phase 1 migrations since turn gating prevents concurrent King plays.

## Validation & Error Modes
**Error atoms defined in**: `contracts/events.md` "Error Payloads" table  
**Implementation**: See quickstart.md §3 for validation logic

- Play attempt invalid: return `{:error, :invalid_play}` with reason atoms for granular UI messaging:
  - `:mismatch` - Card doesn't match suit/rank (see events.md line 48)
  - `:multiple_kings` - Multiple Kings in single play (FR-005)
  - `:cardless_wait` - Cardless player tried to play before draw (see events.md line 50)
- Turn gating failure: `{:error, :not_your_turn}` - enforced by `validate_current_turn/2` (lib/kadi/card_games.ex:715)
- Anomaly (no drawable cards after recycle): emit `anomaly_skip` event; UI banner; return `{:ok, :skipped}` (see quickstart.md §9)

## Future (Phase 2 Considerations)
- Add finished status to game_sessions.
- DB trigger / materialized view for top card integrity.
- Persistent event audit table if fairness metrics required.
