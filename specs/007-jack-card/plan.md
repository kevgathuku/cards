# Implementation Plan: Jack Card (Jump/Skip Functionality)

**Branch**: `007-jack-card` | **Date**: 2025-11-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-jack-card/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement Jack card as a "Jump" card that skips N players in turn order, where N equals the number of Jacks played. When played as the last card, player enters cardless state instead of winning. Jack follows standard matching rules (suit or rank) and can be played as combo. Starting Jack cards have no skip effect.

## Technical Context

**Language/Version**: Elixir 1.17+ with OTP 25+  
**Primary Dependencies**: Phoenix 1.7, Phoenix LiveView, Ecto 3.x  
**Storage**: PostgreSQL (via Ecto) - existing game_sessions, game_session_players, deck_cards tables  
**Testing**: ExUnit with Ecto.Adapters.SQL.Sandbox (`:manual` mode)  
**Target Platform**: Web (Phoenix LiveView for real-time multiplayer)  
**Project Type**: Phoenix web application with LiveView  
**Performance Goals**: Database queries <50ms, LiveView updates <100ms  
**Constraints**: Must integrate with existing King card direction reversal, cardless state system  
**Scale/Scope**: Extends existing card game system with 1 new special card type, ~16 functional requirements

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Code Quality Principles
- ✅ **Pattern matching first**: Will use pattern matching for Jack detection and validation
- ✅ **Context boundaries**: Changes isolated to `Kadi.CardGames` context and `PlayValidator` module
- ✅ **Error handling**: Will return `{:ok, result}` / `{:error, reason}` tuples consistently
- ✅ **Feature reuse**: Extends existing King card pattern (direction reversal, telemetry, cardless state)
- ✅ **Schema verification**: Reviewed `game_session.ex`, `game_session_player.ex` - no schema changes needed
- ✅ **DRY principle**: Will reuse `get_next_player_with_direction/3`, cardless transition logic, validation patterns

### Testing Standards
- ✅ **Test coverage**: Will achieve 100% coverage for Jack-specific logic (validation, skip calculation, cardless transition)
- ✅ **Edge cases**: Spec identifies wrap-around, 2-player games, combo scenarios, starting card behavior
- ✅ **Isolation**: Tests will use Ecto Sandbox `:manual` mode consistent with existing tests

### Database Safety
- ✅ **No schema changes required**: Existing tables support Jack implementation
- ✅ **No development database reset**: Tests will create temporary data

### Documentation
- ✅ **Module docs**: Will document `valid_jack_play?/2` and skip calculation logic
- ✅ **Function docs**: Public functions will have `@doc` with examples

**Status**: ✅ PASSED - All gates satisfied, ready for Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
lib/kadi/
├── card_games.ex           # MODIFY: Add Jack skip logic to execute_play/3
├── games/
│   ├── play_validator.ex   # MODIFY: Add valid_jack_play?/2 function
│   ├── game_session.ex     # NO CHANGE: Existing fields support Jack
│   └── game_session_player.ex  # NO CHANGE: Cardless status already exists

lib/kadi_web/
└── live/
    └── game_live.ex        # NO CHANGE: Existing event handlers support any card play

test/kadi/
├── card_games_test.exs     # MODIFY: Add Jack-specific test suite
└── games/
    └── play_validator_test.exs  # MODIFY: Add Jack validation tests

priv/repo/
└── seeds.exs               # NO CHANGE: 52 cards including 4 Jacks already seeded

specs/007-jack-card/
├── plan.md                 # This file
├── research.md             # Phase 0 output
├── data-model.md           # Phase 1 output
└── quickstart.md           # Phase 1 output
```

**Structure Decision**: Phoenix web application structure. All changes are additions/modifications to existing modules. No new tables, schemas, or migrations required. Jack integrates into existing play_cards/3 flow using the same pattern as King card (special card detection → effect application → turn advancement).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
