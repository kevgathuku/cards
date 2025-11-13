# Implementation Plan: Ace Card Special Action

**Branch**: `008-ace-card-feature` | **Date**: 2025-11-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-ace-card-feature/spec.md`

**Note**: This plan documents the implementation of the Ace card feature, which allows players to change the required suit for subsequent plays.

## Summary

Implements the Ace card special ability: players can play an Ace at any time (regardless of top card suit/rank), then select a suit that the next player must follow. The implementation uses database-driven state management with two new fields (`action_type` and `action_suit`) on the `game_sessions` table to track the suit-selection workflow and enforce the suit requirement on subsequent plays.

## Technical Context

**Language/Version**: Elixir 1.17+ with OTP 25+  
**Primary Dependencies**: Phoenix 1.7, Phoenix LiveView 1.7, Ecto 3.x  
**Storage**: PostgreSQL via Ecto (database-driven game state)  
**Testing**: ExUnit with Ecto.Sandbox `:manual` mode  
**Target Platform**: Web application (Phoenix LiveView real-time updates)
**Project Type**: Web application (backend + frontend in Phoenix LiveView)  
**Performance Goals**: Real-time updates via WebSocket, <100ms turn processing  
**Constraints**: Database-driven state (no in-memory game servers), backward compatible with features 001-007  
**Scale/Scope**: Multiplayer card game with 2-6 players per session

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

✅ **Code Quality**: Uses pure functions in `PlayValidator`, database context in `CardGames`  
✅ **Context Boundaries**: Changes isolated to `Kadi.CardGames` and `Kadi.Games.GameSession`  
✅ **Error Handling**: Uses `{:ok, result}` / `{:error, reason}` pattern throughout  
✅ **Feature Reuse**: Extends features 005 (basic gameplay) and 006/007 (King/Jack special cards)  
✅ **Schema Verification**: Migration `20251110192017_add_action_fields_to_game_sessions.exs` adds `action_type` and `action_suit` fields  
✅ **DRY Principle**: Tests moved to `Kadi.CardGames.SpecialCardsAceTest` to avoid duplication  
✅ **Test Coverage**: Comprehensive unit tests for Ace gameplay, suit selection, and validation

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
lib/
├── kadi/
│   ├── card_games.ex                    # MODIFIED: Added select_suit/3, updated play_cards
│   └── games/
│       ├── game_session.ex               # MODIFIED: Added action_type, action_suit fields
│       └── play_validator.ex             # MODIFIED: Added valid_play?/3 with action_suit param
├── kadi_web/
│   └── live/
│       ├── game_live.ex                  # MODIFIED: Added select_suit event handler
│       └── game_live.html.heex           # MODIFIED: Added suit selection UI

priv/repo/migrations/
└── 20251110192017_add_action_fields_to_game_sessions.exs  # NEW: Migration

test/
├── kadi/
│   ├── card_games/
│   │   └── special_cards_ace_test.exs    # NEW: Ace card tests (moved from card_games_test.exs)
│   └── games/
│       └── play_validator_test.exs       # MODIFIED: Updated to valid_play?/3
└── kadi_web/
    └── live/
        └── game_live_test.exs            # MODIFIED: Added select_suit tests
```

**Structure Decision**: Phoenix LiveView web application. All changes follow existing Phoenix conventions with context-based architecture (`Kadi.CardGames` context, `Kadi.Games` schemas). Tests mirror source structure and have been reorganized to avoid duplication (Ace tests moved to dedicated file `special_cards_ace_test.exs`).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
