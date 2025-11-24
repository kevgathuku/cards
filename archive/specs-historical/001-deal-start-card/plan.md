# Implementation Plan: Deal Start Card (Final Revision)

**Feature Branch**: `001-deal-start-card`
**Feature Spec**: [spec.md](./spec.md)
**Status**: In Progress

## 1. Technical Context

Based on the feature requirements and the architecture defined in `GEMINI.md`, the following technical approach will be used:

-   **Frontend**: Phoenix LiveView and Tailwind CSS.
-   **Backend**: Elixir, with core logic in the `Kadi.CardGames` context.
-   **Database**: Ecto and PostgreSQL. The implementation will use the existing schema without modification. Game state and card locations will be managed by updating the `location_type` field (`"deck"`, `"player_hand"`, `"played_stack"`) in the `deck_cards` join table.
-   **Real-time Communication**: `Phoenix.PubSub` will broadcast game state changes.
-   **Architecture**: All interactions will be handled via LiveView events, with business logic delegated to the `Kadi.CardGames` context. No database migrations are required.

## 2. Constitution Check

This revised plan has been validated against the Speckit Constitution.

-   [X] **Code Quality**: The plan now correctly adheres to the existing data model and context boundaries.
-   [X] **Testing**: New logic will be tested to verify correct `location_type` updates.
-   [X] **User Experience**: The approach fully supports real-time updates.
-   [X] **Performance**: Using the existing indexed tables is the correct, performant approach.
-   [X] **All other principles**: The plan remains in compliance.

**Result**: The final, corrected plan is in full compliance with the constitution.

## 3. Implementation Phases

### Phase 0: Research & Decisions

*   **Artifact**: [research.md](./research.md) (Revised)
*   **Summary**: Confirms the correct architectural approach using the `deck_cards.location_type` field, as guided by `GEMINI.md`.

### Phase 1: Design & Contracts

*   **Artifacts**:
    *   [data-model.md](./data-model.md) (Revised)
    *   [contracts/live_view_contracts.md](./contracts/live_view_contracts.md)
    *   [quickstart.md](./quickstart.md) (Revised)
*   **Summary**: Defines the implementation strategy based on the existing data model, with no schema changes required.

### Phase 2: Implementation Tasks (Next Step)

*   **Summary**: This phase will break down the implementation into concrete tasks via the `/speckit.implement` command.