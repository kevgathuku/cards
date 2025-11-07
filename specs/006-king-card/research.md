# Phase 0 Research: King Card Reversal

Date: 2025-11-07
Branch: 006-king-card
Spec: specs/006-king-card/spec.md

## Unknowns Resolved

### 1. Separate King Rules Module vs Extend `PlayValidator`
- Decision: Extend existing `Kadi.Games.PlayValidator` with King-specific clauses.
- Rationale: Avoid premature fragmentation; keeps rule validation centralized; complies with DRY (Constitution 1.7).
- Alternatives considered: New `Kadi.Games.Rules.King` (adds indirection), Behaviour-based pluggable rule system (over-engineered for single special card).

### 2. Concurrency Strategy for Simultaneous King Plays
- Decision: Prevention via authoritative turn gating — only `current_turn_player_id` may initiate a play; other attempts rejected immediately. No optimistic lock needed for King reversal.
- Rationale: Single-turn ownership eliminates simultaneous valid King plays; reduces complexity (no retry/backoff) and aligns with existing turn model.
- Alternatives considered: Optimistic locking (unnecessary given strict turn ownership), `SELECT FOR UPDATE` (overkill), process serialization (adds coupling without benefit).

### 3. Representation of `direction` Constraint
- Decision: Plain string field validated in changeset + database CHECK constraint (`direction IN ('clockwise','counter_clockwise')`).
- Rationale: Enforces integrity at DB layer; string easier than enum types across environments.
- Alternatives: Application-only validation (risk of drift), PostgreSQL enum (harder to evolve, migration overhead).

### 4. Player Status Persistence (Enum)
- Decision: Persist `status` enum (as validated string) on `game_session_players` with allowed values {"normal","cardless"}, default "normal"; set to "cardless" when last card is King; reset to "normal" after forced draw.
- Rationale: Extensible for future statuses beyond cardless; keeps querying simple and LiveView responsive.
- Alternatives: Boolean flag (not extensible), derived from events (heavier infra), transient process memory (volatile).

### 5. Telemetry vs Custom Logging Wrapper
- Decision: Emit Telemetry events (`[:kadi, :king, :direction_change]`, `[:kadi, :king, :cardless_entered]`, `[:kadi, :king, :anomaly_skip]`). Logger handler formats as structured JSON.
- Rationale: Composable, testable, integrates with existing ecosystem; decouples producers from logging sink.
- Alternatives: Direct Logger calls (less flexible), custom PubSub topic (redundant with Telemetry).

### 6. Validation Placement (Client vs Server)
- Decision: All authoritative validation server-side; optional client pre-check (non-blocking) may show early affordances but not relied upon.
- Rationale: Prevents cheating/spoofing; ensures canonical rule enforcement.
- Alternatives: Partial client enforcement (security hole), fully pessimistic server-only with no client hints (worse UX).

### 7. Top Card Integrity Guard
- Decision: Runtime invariant check in play transaction: ensure `top_card_id` matches newly played card & update `deck_cards` ordering atomically. Add DB partial unique index: highest `order_index` for `played_stack` must correspond to `game_sessions.top_card_id` (enforced indirectly by trigger later—deferred Phase 2 improvement).
- Rationale: Lightweight initial safeguard; avoids complex trigger upfront.
- Alternatives: Database trigger immediate (higher complexity), no guard (risk of divergence).

## Additional Findings / Best Practices

| Topic | Best Practice | Notes |
|-------|--------------|-------|
| Turn Gating | Enforce single-authoritative player per turn | Eliminates need for optimistic lock currently |
| Telemetry Testing | Assert via `:telemetry.attach/4` in test | Capture emitted metadata maps |
| LiveView Toast Rate Limiting | Use assign timestamp + debounce via `Process.send_after` | Cancel previous timer on new direction within window |
| Accessibility | Use `role="status"` with `aria-live="polite"` for toast | Ensure auto-dismiss doesnt remove focus unexpectedly |
| i18n Keys | Namespace: `game.direction.reversed`, `game.anomaly.deck_exhausted` | Single source for future locales |

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
