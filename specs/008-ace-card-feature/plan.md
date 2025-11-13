# Implementation Plan: Ace Card Special Action

**Branch**: `008-ace-card-feature` | **Date**: 2025-11-10 | **Updated**: 2025-11-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-ace-card-feature/spec.md`

**Note**: This plan documents the implementation of the Ace card feature, which allows players to change the required suit for subsequent plays. **Updated 2025-11-13** to reflect clarified suit persistence requirements.

## Summary

Implements the Ace card special ability: players can play an Ace at any time (regardless of top card suit/rank), then select a suit that subsequent players must follow. **The suit requirement persists across multiple turns** until either (1) a player successfully plays a card matching the requested suit, or (2) a player plays an Ace and sets a new suit. Players who cannot match the required suit must draw; their turn ends but the requirement persists for the next player. The implementation uses database-driven state management with the existing `action_suit` field on `game_sessions` table.

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

### Initial Check (2025-11-10) ✅

✅ **Code Quality**: Uses pure functions in `PlayValidator`, database context in `CardGames`  
✅ **Context Boundaries**: Changes isolated to `Kadi.CardGames` and `Kadi.Games.GameSession`  
✅ **Error Handling**: Uses `{:ok, result}` / `{:error, reason}` pattern throughout  
✅ **Feature Reuse**: Extends features 005 (basic gameplay) and 006/007 (King/Jack special cards)  
✅ **Schema Verification**: Migration `20251110192017_add_action_fields_to_game_sessions.exs` adds `action_type` and `action_suit` fields  
✅ **DRY Principle**: Tests moved to `Kadi.CardGames.SpecialCardsAceTest` to avoid duplication  
✅ **Test Coverage**: Comprehensive unit tests for Ace gameplay, suit selection, and validation

### Post-Phase 1 Check (2025-11-13) ✅

✅ **Section 1.1 (Elixir Idioms)**: Pattern matching used for state transitions; pure functions in PlayValidator  
✅ **Section 1.2 (Context Boundaries)**: All game logic in `Kadi.CardGames` context; LiveView calls context functions only  
✅ **Section 1.5 (Feature Reuse)**: Extends existing `PlayValidator.valid_play?/3`; reuses PubSub broadcast pattern  
✅ **Section 1.6 (Schema Verification)**: Verified `action_suit` field exists in schema before designing persistence logic  
✅ **Section 1.7 (DRY Principle)**: No duplicate functions; extends existing validation rather than creating new validators  
✅ **Section 2.1-2.4 (Testing)**: Test suite covers persistence scenarios, edge cases (multiple draws), integration with King/Jack  
✅ **Section 3.1 (LiveView Patterns)**: Broadcast-only updates; UI indicator for persistent suit requirement  
✅ **Section 6.4 (Database Safety)**: All verification via tests; no destructive operations on dev database

**Key Design Validation**:
- Suit persistence implementation aligns with clarified requirements (Sessions 2025-11-10 and 2025-11-13)
- State transitions documented in data-model.md match database-driven architecture
- PlayValidator extension maintains backward compatibility with existing card types

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
| N/A | No violations | All constitution gates pass |

---

## Phase 0: Research Complete ✅

**Status**: Complete (2025-11-13)  
**Output**: [research.md](./research.md)

**Key Research Decisions**:
1. **Suit Persistence Strategy**: Persistent suit requirement that clears only on matching play or new Ace
2. **Database State Management**: Use existing `game_sessions.action_suit` field with explicit lifecycle
3. **PlayValidator Extension**: Pass `action_suit` as optional parameter through validation chain
4. **UI/UX**: Persistent purple banner with suit symbol (♥♦♣♠) visible to all players
5. **Edge Case Handling**: Multiple consecutive draws supported; deck recycling prevents deadlock
6. **Special Card Integration**: King/Jack must respect `action_suit` when active (already implemented)

**Rationale**: All decisions documented in research.md with alternatives considered and risks mitigated.

---

## Phase 1: Design & Contracts Complete ✅

**Status**: Complete (2025-11-13)  
**Outputs**: 
- [data-model.md](./data-model.md) - Schema details and state transitions
- [contracts/live_view_events.md](./contracts/live_view_events.md) - Client-server event contracts
- [quickstart.md](./quickstart.md) - Setup and testing guide
- `.github/copilot-instructions.md` - Updated agent context

**Key Design Artifacts**:
1. **State Transition Diagram**: Documents action_suit lifecycle with persistence rules
2. **Context Functions**: `select_suit/3`, modified `draw_card_from_deck/2`, modified `execute_play/3`
3. **Validation Extension**: `PlayValidator.valid_play?/3` with `action_suit` parameter
4. **LiveView Contracts**: Event handlers for `select_suit` and UI indicators for persistent requirement
5. **Agent Context**: Updated with Elixir 1.17+, Phoenix 1.7, LiveView 1.7, Ecto 3.x, PostgreSQL

**Constitution Re-check**: All gates pass ✅ (see Post-Phase 1 Check above)

---

## Next Steps

**Phase 2**: Task decomposition via `/speckit.tasks` command

The implementation is ready to be broken down into granular tasks. All design decisions are documented and validated against constitution principles.
