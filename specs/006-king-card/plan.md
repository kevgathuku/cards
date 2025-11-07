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
- `Kadi.Games.GameSession` (`lib/kadi/games/game_session.ex`): add `direction` field ("clockwise" | "counter_clockwise") → **see data-model.md §2.1**
- `Kadi.Games.GameSessionPlayer` (`lib/kadi/games/game_session_player.ex`): add `status` string enum (default "normal", values: "normal"|"cardless") → **see data-model.md §2.2**
- `Kadi.Games.PlayValidator` (`lib/kadi/games/play_validator.ex`, lines 1-107): extend with `valid_king_play?/3` function → **see quickstart.md §3.1**
- Integration points:
  - `Kadi.CardGames.play_cards/3` (lines 415-465): add turn gating validation → **see quickstart.md §3.3**
  - `Kadi.CardGames.execute_play/3` (lines 571-615): add King detection & direction reversal → **see quickstart.md §3.3**
  - `Kadi.CardGames.draw_card_from_deck/2` (lines 215-285): add cardless auto-draw logic → **see quickstart.md §4.1**
  - `Kadi.CardGames.get_next_player/2` (line 697): refactor to direction-aware → **see quickstart.md §3.2**
- Telemetry event emission: namespace `:kadi, :king, :direction_change` etc. → **see contracts/events.md §3, quickstart.md §5**
- LiveView event/messages contract (`lib/kadi_web/live/game_live.ex`): no external REST API → **see contracts/events.md §1-2**

### Open Questions (All Resolved)
1. ~~Separate dedicated King rules module vs extending existing `PlayValidator`?~~ → **RESOLVED**: Extend validator (see research.md §1)
2. ~~Concurrency: prevent simultaneous King plays~~ → **RESOLVED**: Turn gating via `validate_current_turn/2` at line 715 (see research.md §2)
3. ~~Representation of `direction`~~ → **RESOLVED**: String + CHECK constraint (see research.md §3, data-model.md §2.1)
4. ~~Player status persistence~~ → **RESOLVED**: String enum field (see research.md §4, data-model.md §2.2)
5. ~~Telemetry vs custom logging wrapper~~ → **RESOLVED**: Telemetry (see research.md §5)
6. ~~Validation placement~~ → **RESOLVED**: Server authoritative (see research.md §6)
7. ~~Top card integrity guard~~ → **RESOLVED**: Runtime invariant (see research.md §7)

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
├── spec.md              # Complete requirements & acceptance criteria
├── plan.md              # This file - implementation roadmap
├── research.md          # Phase 0 - Design decisions & rationale
├── data-model.md        # Phase 1 - Schema changes & migrations
├── quickstart.md        # Phase 1 - Step-by-step implementation guide
├── audit.md             # Implementation plan review & cross-references
└── contracts/
    └── events.md        # LiveView & Telemetry event contracts
```

### Source Code (relevant existing paths)
```text
lib/
  kadi/
    games/
      game_session.ex           # Lines 1-30: Add :direction field (§2.1)
      game_session_player.ex    # Lines 1-20: Add :status field (§2.2)
      deck_card.ex              # Unchanged
      card.ex                   # Contains rank "king"
      play_validator.ex         # Lines 1-107: Extend with King logic (§3.1)
      supervisor.ex             # Unchanged
    card_games.ex               # Main context - multiple integration points:
                                # - Lines 215-285: draw_card_from_deck (§4.1)
                                # - Lines 415-465: play_cards (§3.3)
                                # - Lines 571-615: execute_play (§3.3)
                                # - Line 697-706: get_next_player (§3.2)
                                # - Line 715: validate_current_turn (existing)
    utils.ex                    # Unchanged
  kadi_web/
    live/
      game_live.ex              # LiveView updates (§6)
      game_live.html.heex       # Direction indicator template (§6.2)
priv/
  repo/migrations/              # Add two new migrations (§1)
  gettext/en/LC_MESSAGES/       # Add i18n keys (§8)
```

**Structure Decision**: Extend existing Games context; no new context introduced. Add migrations as specified in quickstart.md §1. All cross-references use § notation to reference quickstart.md sections.

## Complexity Tracking

Currently no constitution violations requiring justification.
