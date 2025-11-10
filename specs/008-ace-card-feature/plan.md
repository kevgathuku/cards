# Implementation Plan: Ace Card Special Action

**Branch**: `008-ace-card-feature` | **Date**: 2025-11-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-ace-card-feature/spec.md`

## Summary

This plan outlines the technical implementation for the "Ace Card Special Action" feature. The feature allows a player to play an Ace at any time to change the required suit for the next turn. The implementation involves modifying the core game logic in `Kadi.CardGames`, updating the `GameSession` data model to track the requested suit, and enhancing the `GameLive` view to handle the new user interaction for selecting a suit.

## Technical Context

**Language/Version**: Elixir 1.15+ (based on project files)
**Primary Dependencies**: Phoenix 1.7+, Ecto 3.9+
**Storage**: PostgreSQL
**Testing**: ExUnit
**Target Platform**: Web
**Project Type**: Phoenix Web Application (Monolith)
**Performance Goals**: LiveView updates should be broadcast and rendered in < 100ms.
**Constraints**: The implementation must not block the `GameLive` process and should handle the intermediate state (awaiting suit selection) gracefully.
**Scale/Scope**: The changes are scoped to the existing `Kadi.CardGames` context and the `KadiWeb.GameLive` view.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **[PASS]** 1. Code Quality: The plan adheres to Elixir idioms, respects context boundaries, and proposes adding documentation.
- **[PASS]** 2. Testing Standards: New logic will require new unit and integration tests.
- **[PASS]** 3. UX Consistency: The plan uses existing LiveView patterns for user interaction.
- **[PASS]** 4. Performance: The proposed changes are lightweight and should not impact performance.
- **[PASS]** 5. Security: The plan relies on existing server-side validation within the `CardGames` context.
- **[PASS]** 6. Git Workflow: All work is being done on a feature branch.
- **[PASS]** 7. Documentation: New artifacts (`data-model.md`, `contracts/`, etc.) are being created.

**Result**: All gates pass.

## Project Structure

### Documentation (this feature)

```text
specs/008-ace-card-feature/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── live_view_events.md
└── tasks.md             # Phase 2 output (NOT created by this command)
```

### Source Code (repository root)

```text
lib/
├── kadi/
│   ├── card_games.ex
│   └── games/
│       ├── game_session.ex
│       └── play_validator.ex
└── kadi_web/
    └── live/
        └── game_live.ex

priv/
└── repo/
    └── migrations/
        └── <timestamp>_add_action_fields_to_game_sessions.exs

test/
├── kadi/
│   └── card_games_test.exs
└── kadi_web/
    └── live/
        └── game_live_test.exs
```

**Structure Decision**: The implementation will modify existing files within the standard Phoenix project structure. No new top-level directories are required. This aligns with the principle of integrating with existing contexts.

## Complexity Tracking

No constitutional violations were identified that require justification.