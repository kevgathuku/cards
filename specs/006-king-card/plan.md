# Implementation Plan: King Card Reversal (Kickback)

**Branch**: `006-king-card` | **Date**: 2025-11-07 | **Spec**: `specs/006-king-card/spec.md`
**Input**: Feature specification from `specs/006-king-card/spec.md`

## Summary

Implement King (K) card reversal mechanic with direction tracking, player status enum handling (non-winning last-K play), deck recycling preserving top card, anomaly skip handling, structured telemetry events, accessible + localized UI notifications, and rate-limited direction change toasts. Technical approach: add `direction` string field to `game_sessions`, add `status` string enum to `game_session_players`, extend validation in existing `Kadi.Games.PlayValidator`, and enforce play authorization via `current_turn_player_id` (reject non-turn plays). Emit Telemetry events consumed by Logger, and integrate LiveView UI updates with ephemeral + persistent indicators.

## Technical Context

**Language/Version**: Elixir 1.17 + OTP 28 (Phoenix 1.7.21)  
**Primary Dependencies**: Phoenix, Phoenix LiveView, Ecto 3.10+, PostgreSQL, Telemetry, Logger  
**Storage**: PostgreSQL (existing schemas: game_sessions, deck_cards, etc.)  
**Testing**: ExUnit + existing DataCase/ConnCase; add targeted rule tests & LiveView tests  
**Target Platform**: Server-rendered web (Phoenix + LiveView)  
**Project Type**: Web application (backend + LiveView front-end under `lib/kadi_web`)  
**Performance Goals**: SC-001/SC-003/SC-009 imply <1–2s user-visible propagation; internal target: direction reversal processing <50ms server-side  
**Constraints**: Must not break existing gameplay flows; maintain backwards compatibility with prior features; avoid blocking UI  
**Scale/Scope**: Support 100+ concurrent games (constitution scalability requirement); feature localized strings but English only initial; extensible player status enum

### Derived Components / Modules
- `Kadi.Games.GameSession`: add `direction` ("clockwise" | "counter_clockwise")
- `Kadi.Games.GameSessionPlayer`: add `status` string (enum validated) default "normal" (values: "normal","cardless")
- `Kadi.Games.PlayValidator`: extend or add function `validate_king_play/3`
- New rule module (optional): `Kadi.Games.Rules.King` for composability (NEEDS CLARIFICATION—merge into existing validator or separate?)
- Telemetry event emission (namespace: `:kadi, :king, :direction_change` etc.)
- LiveView event/messages contract (no external REST API)

### Open Questions (Resolved)
1. Separate dedicated King rules module vs extending existing `PlayValidator`? → RESOLVED (extend validator)
2. Concurrency: prevent simultaneous King plays by rejecting non-turn player actions (no optimistic lock) → RESOLVED
3. Representation of `direction`: string + CHECK constraint → RESOLVED
4. Player status persistence: string enum field → RESOLVED
5. Telemetry vs custom logging wrapper: Telemetry → RESOLVED
6. Validation placement: server authoritative with optional client hint → RESOLVED
7. Top card integrity guard: runtime invariant + future trigger Phase 2 → RESOLVED

## Constitution Check (Initial Pre-Design Gate)

| Principle Section | Status | Notes |
|-------------------|--------|-------|
| 1.6 Schema Verification | PASS | Read core schemas; `direction` + `cardless` absent → planned migrations |
| 1.7 DRY / duplication | PASS | Plan reuses PlayValidator; no new parallel context |
| Context boundaries | PASS | Logic stays in Games context; LiveView only invokes context APIs |
| Error handling tuples | PASS | Will return `{:ok, state}` / `{:error, reason}` from new functions |
| Testing standards | PASS (planned) | Add unit tests for validator & integration LiveView tests |
| Accessibility | PASS (specified via FR-022/SC-010) |
| Observability | PASS (FR-020 events) |
| Privacy / PII | PASS (FR-024) |
| Performance | PASS (targets within constitution baselines) |

No blocking violations. Proceed to Phase 0 once unknowns resolved.

### Post-Design Re-Check

| Principle | Status | Adjustment |
|-----------|--------|-----------|
| Schema Verification | PASS | Migrations specified in data-model.md |
| DRY | PASS | Reuse PlayValidator; no duplicate rule modules |
| Error Handling | PASS | Plan defines tuple returns; turn gating prevents concurrent plays |
| Observability | PASS | Telemetry events defined & namespaced |
| Privacy | PASS | PII exclusion enforced (FR-024) |
| Accessibility | PASS | Indicator & toast specs (FR-022/SC-010) |
| Performance | PASS | Targets within constitution limits |
| Testing Coverage | PASS (planned) | Unit + integration + LiveView + telemetry tests listed |

All gates satisfied; Phase 2 task decomposition may proceed next.

## Project Structure

### Documentation (feature directory)
```text
specs/006-king-card/
├── spec.md
├── plan.md
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/           # Phase 1 (OpenAPI + events doc)
└── tasks.md             # Phase 2 (future)
```

### Source Code (relevant existing paths)
```text
lib/
  kadi/games/game_session.ex
  kadi/games/game_session_player.ex
  kadi/games/deck_card.ex
  kadi/games/card.ex
  kadi/games/play_validator.ex
  kadi/games/supervisor.ex
  kadi/utils.ex
  kadi_web/live/game_live.ex (assumed)
```

**Structure Decision**: Extend existing Games context; no new context introduced. Add migrations and, if separation chosen, a small `kadi/games/rules/king.ex` module.

## Complexity Tracking

Currently no constitution violations requiring justification.
