# Phase 0 Research: King Card Reversal

Date: 2025-11-07
Branch: 006-king-card
Spec: specs/006-king-card/spec.md

## Unknowns Resolved

### 1. Separate King Rules Module vs Extend `PlayValidator`
**Decision**: Extend existing `Kadi.Games.PlayValidator` with King-specific clauses.  
**File**: `lib/kadi/games/play_validator.ex` (current: lines 1-107)  
**Implementation**: Add `valid_king_play?/3` function after line 44 (see quickstart.md §3.1)  
**Rationale**: Avoid premature fragmentation; keeps rule validation centralized; complies with DRY (Constitution 1.7).  
**Alternatives considered**: 
- New `Kadi.Games.Rules.King` module (adds indirection)
- Behaviour-based pluggable rule system (over-engineered for single special card)

### 2. Concurrency Strategy for Simultaneous King Plays
**Decision**: Prevention via authoritative turn gating — only `current_turn_player_id` may initiate a play; other attempts rejected immediately. No optimistic lock needed for King reversal.  
**Existing Implementation**: `validate_current_turn/2` at `lib/kadi/card_games.ex:715`  
**Usage**: Called in `play_cards/3` around line 432 (see quickstart.md §3.3)  
**Rationale**: Single-turn ownership eliminates simultaneous valid King plays; reduces complexity (no retry/backoff) and aligns with existing turn model.  
**Alternatives considered**: 
- Optimistic locking (unnecessary given strict turn ownership)
- `SELECT FOR UPDATE` (overkill)
- Process serialization (adds coupling without benefit)

### 3. Representation of `direction` Constraint
**Decision**: Plain string field validated in changeset + database CHECK constraint (`direction IN ('clockwise','counter_clockwise')`).  
**Schema File**: `lib/kadi/games/game_session.ex` (modify lines 5-30, see quickstart.md §2.1)  
**Migration**: See quickstart.md §1.1 and data-model.md §2.1  
**Rationale**: Enforces integrity at DB layer; string easier than enum types across environments.  
**Alternatives**: 
- Application-only validation (risk of drift)
- PostgreSQL enum (harder to evolve, migration overhead)

### 4. Player Status Persistence (Enum)
**Decision**: Persist `status` enum (as validated string) on `game_session_players` with allowed values {"normal","cardless"}, default "normal"; set to "cardless" when last card is King; reset to "normal" after forced draw.  
**Schema File**: `lib/kadi/games/game_session_player.ex` (modify lines 4-20, see quickstart.md §2.2)  
**Migration**: See quickstart.md §1.2 and data-model.md §2.2  
**Rationale**: Extensible for future statuses beyond cardless; keeps querying simple and LiveView responsive.  
**Alternatives**: 
- Boolean flag (not extensible)
- Derived from events (heavier infra)
- Transient process memory (volatile)

### 5. Telemetry vs Custom Logging Wrapper
**Decision**: Emit Telemetry events (`[:kadi, :king, :direction_change]`, `[:kadi, :king, :cardless_entered]`, `[:kadi, :king, :anomaly_skip]`). Logger handler formats as structured JSON.  
**Implementation**: 
- Helper functions in `lib/kadi/card_games.ex` after line 730 (see quickstart.md §5.1)
- Handler attachment in `lib/kadi/application.ex` (see quickstart.md §5.2)
- Event schemas in `contracts/events.md` §3  
**Rationale**: Composable, testable, integrates with existing ecosystem; decouples producers from logging sink.  
**Alternatives**: 
- Direct Logger calls (less flexible)
- Custom PubSub topic (redundant with Telemetry)

### 6. Validation Placement (Client vs Server)
**Decision**: All authoritative validation server-side; optional client pre-check (non-blocking) may show early affordances but not relied upon.  
**Server Validation**: 
- Turn gating: `validate_current_turn/2` at `lib/kadi/card_games.ex:715`
- King rules: `valid_king_play?/2` in `lib/kadi/games/play_validator.ex` (see quickstart.md §3.1)  
**Rationale**: Prevents cheating/spoofing; ensures canonical rule enforcement.  
**Alternatives**: 
- Partial client enforcement (security hole)
- Fully pessimistic server-only with no client hints (worse UX)

### 7. Top Card Integrity Guard
**Decision**: Runtime invariant check in play transaction: ensure `top_card_id` matches newly played card & update `deck_cards` ordering atomically. Add DB partial unique index: highest `order_index` for `played_stack` must correspond to `game_sessions.top_card_id` (enforced indirectly by trigger later—deferred Phase 2 improvement).  
**Implementation Location**: `execute_play/3` in `lib/kadi/card_games.ex` (replace lines 571-615, see quickstart.md §3.3)  
**Rationale**: Lightweight initial safeguard; avoids complex trigger upfront.  
**Alternatives**: 
- Database trigger immediate (higher complexity)
- No guard (risk of divergence)

## Additional Findings / Best Practices

| Topic | Best Practice | Implementation Reference |
|-------|--------------|-------------------------|
| Turn Gating | Enforce single-authoritative player per turn | `validate_current_turn/2` at lib/kadi/card_games.ex:715 |
| Telemetry Testing | Assert via `:telemetry.attach/4` in test | See quickstart.md §7.4 for test patterns |
| LiveView Toast Rate Limiting | Use assign timestamp + debounce via `Process.send_after` | See quickstart.md §6.3, spec.md FR-025 |
| Accessibility | Use `role="status"` with `aria-live="polite"` for toast | See quickstart.md §6.2, spec.md FR-022 |
| i18n Keys | Namespace: `game.direction.reversed`, `game.anomaly.deck_exhausted` | See quickstart.md §8, contracts/events.md localization table |
| Direction Helpers | Add `reverse_direction/1`, `get_previous_player/2` | See quickstart.md §3.2 (after line 706) |
| Status Transitions | Atomic updates in Ecto.Multi with telemetry emission | See quickstart.md §3.3 (execute_play) and §4.1 (draw_card) |

## Migration Plan Summary

1. Add migration: add `direction` (string, default "clockwise"), `lock_version` (integer, default 0) to `game_sessions` and CHECK constraint.
2. Add migration: add `status` (string, default "normal", not null) to `game_session_players` with CHECK `status IN ('normal','cardless')`.
3. (Optional Phase 2) Add partial index or trigger for top card integrity.

## Open Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Rapid direction toggles cause UI spam | Medium | Implement 2s coalescing (FR-025) |
| Race condition playing King concurrently | Low | Turn gating prevents non-owner play; validate player match before mutation |
| Event log drift from spec | Debug difficulty | Telemetry event naming test coverage |
| Cardless flag stale after failure | Inconsistent state | Transaction ensures cardless update + draw scheduling atomic |

## Decisions Snapshot

All NEEDS CLARIFICATION items resolved; no remaining blockers for Phase 1 design.
