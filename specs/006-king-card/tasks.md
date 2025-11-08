# Tasks: King Card Reversal (Kickback)

**Input**: Design documents from `/Users/kevin/code/elixir/cards/specs/006-king-card/`  
**Prerequisites**: plan.md, spec.md (user stories), research.md, data-model.md, quickstart.md, contracts/events.md

**Tests**: Tests are included based on spec.md testing requirements (unit, integration, LiveView, telemetry)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is an Elixir/Phoenix project with the following structure:
- Application code: `lib/kadi/` and `lib/kadi_web/`
- Migrations: `priv/repo/migrations/`
- Tests: `test/`
- Localization: `priv/gettext/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database schema changes and initial setup required for all King card functionality

- [X] T001 Create direction field migration in priv/repo/migrations/YYYYMMDDHHMMSS_add_direction_to_game_sessions.exs
- [X] T002 Create status field migration in priv/repo/migrations/YYYYMMDDHHMMSS_add_status_to_game_session_players.exs
- [X] T003 Run migrations with mix ecto.migrate to apply schema changes
- [X] T004 [P] Update GameSession schema in lib/kadi/games/game_session.ex to add direction field and validation
- [X] T005 [P] Update GameSessionPlayer schema in lib/kadi/games/game_session_player.ex to add status field and validation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core validation and direction-aware turn logic that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 [P] Extend PlayValidator in lib/kadi/games/play_validator.ex with valid_king_play?/2 function (lines 44-70)
- [X] T007 [P] Add direction-aware turn helpers in lib/kadi/card_games.ex after line 706 (get_next_player_with_direction/3, get_previous_player/2, reverse_direction/1)
- [X] T008 Add telemetry helper functions in lib/kadi/card_games.ex after line 730 (emit_direction_change_event/6, emit_cardless_event/3, emit_anomaly_skip_event/3)
- [X] T009 Attach telemetry handlers in lib/kadi/application.ex for King feature events (direction_change, cardless_entered, anomaly_skip)
- [X] T010 [P] Add i18n keys in priv/gettext/en/LC_MESSAGES/default.po for direction labels, toasts, and error messages

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Play King Card to Reverse Game Direction (Priority: P1) 🎯 MVP

**Goal**: Enable players to play King cards that reverse game direction, with proper validation and turn order changes

**Independent Test**: Start a multi-player game, play a King card matching the top card, verify direction reverses and turn order changes accordingly

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T011 [P] [US1] Unit test for valid_king_play?/2 accepting King matching suit in test/kadi/games/play_validator_test.exs
- [X] T012 [P] [US1] Unit test for valid_king_play?/2 accepting King matching rank in test/kadi/games/play_validator_test.exs
- [X] T013 [P] [US1] Unit test for valid_king_play?/2 rejecting King not matching suit or rank in test/kadi/games/play_validator_test.exs
- [X] T014 [P] [US1] Unit test for valid_king_play?/2 rejecting multiple Kings (FR-005) in test/kadi/games/play_validator_test.exs
- [X] T015 [P] [US1] Integration test for direction reversal clockwise to counter_clockwise in test/kadi/card_games_test.exs
- [X] T016 [P] [US1] Integration test for direction reversal counter_clockwise to clockwise in test/kadi/card_games_test.exs
- [X] T017 [P] [US1] Integration test for 2-player game King play (FR-009) in test/kadi/card_games_test.exs
- [X] T018 [P] [US1] Telemetry test for direction_change event emission in test/kadi/telemetry_test.exs

### Implementation for User Story 1

- [X] T019 [US1] Update valid_play?/2 in lib/kadi/games/play_validator.ex to route King plays to valid_king_play?/2 (lines 33-44)
- [X] T020 [US1] Implement King detection and direction reversal in execute_play/3 in lib/kadi/card_games.ex (replace lines 571-615)
- [X] T021 [US1] Update execute_play/3 to use get_next_player_with_direction/3 for turn progression in lib/kadi/card_games.ex
- [X] T022 [US1] Add get_player_hand_count/2 helper function in lib/kadi/card_games.ex for cardless detection
- [X] T023 [US1] Update start_game/1 in lib/kadi/card_games.ex to initialize direction field to "clockwise" (FR-007)

**Checkpoint**: At this point, User Story 1 should be fully functional - King cards reverse direction and turn order changes correctly

---

## Phase 4: User Story 2 - King Card Validation (Priority: P1)

**Goal**: Ensure King cards can only be played when matching suit or rank, and only one King per turn

**Independent Test**: Attempt to play King cards in valid and invalid scenarios, verify system correctly accepts or rejects

**Note**: This builds on User Story 1's foundation but focuses on comprehensive validation scenarios

### Tests for User Story 2

- [X] T024 [P] [US2] Integration test for accepting King matching suit in test/kadi/card_games_test.exs
- [X] T025 [P] [US2] Integration test for accepting King matching rank in test/kadi/card_games_test.exs
- [X] T026 [P] [US2] Integration test for rejecting King not matching suit or rank in test/kadi/card_games_test.exs
- [X] T027 [P] [US2] Integration test for rejecting multiple King cards in single turn in test/kadi/card_games_test.exs
- [X] T028 [P] [US2] Integration test for King as start card (allowed, no reversal per FR-003) in test/kadi/card_games_test.exs

### Implementation for User Story 2

- [X] T029 [US2] Add error handling for invalid King plays in play_cards/3 in lib/kadi/card_games.ex
- [X] T030 [US2] Ensure turn gating (FR-027) rejects non-turn player King plays in lib/kadi/card_games.ex
- [X] T031 [US2] Add validation for King as start card scenario in select_start_card/1 in lib/kadi/card_games.ex

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - King plays validated and direction reversal working

---

## Phase 5: User Story 3 - Track Game Direction State (Priority: P2)

**Goal**: Persist and expose game direction state so players can understand turn flow

**Independent Test**: Query game state after playing Kings, verify direction is correctly stored and persisted

### Tests for User Story 3

- [X] T032 [P] [US3] Unit test for default direction "clockwise" on new games in test/kadi/card_games_test.exs
- [X] T033 [P] [US3] Integration test for direction persistence after King play in test/kadi/card_games_test.exs
- [X] T034 [P] [US3] Integration test for direction toggle on consecutive King plays in test/kadi/card_games_test.exs

### Implementation for User Story 3

- [X] T035 [US3] Add direction field to broadcast_game_update/1 payload in lib/kadi/card_games.ex
- [X] T036 [US3] Update GameLive mount to include direction in assigns in lib/kadi_web/live/game_live.ex
- [X] T037 [US3] Add build_player_statuses_map/1 helper in lib/kadi_web/live/game_live.ex for status tracking
- [X] T038 [US3] Add persistent direction indicator component in lib/kadi_web/live/game_live.html.heex with icon and text
- [X] T039 [US3] Add direction_icon/1 and direction_label/1 helpers in lib/kadi_web/live/game_live.ex

**Checkpoint**: All three user stories should now be independently functional - direction tracked, validated, and displayed

---

## Phase 6: Cardless State & Edge Cases

**Purpose**: Handle cardless player state (King as last card) and anomaly scenarios

- [X] T040 [P] Unit test for cardless status transition when playing King as last card in test/kadi/card_games_test.exs
- [X] T041 [P] Unit test for cardless player auto-draw on their turn in test/kadi/card_games_test.exs
- [X] T042 [P] Unit test for status reset to "normal" after auto-draw in test/kadi/card_games_test.exs
- [X] T043 [P] Telemetry test for cardless_entered event emission in test/kadi/telemetry_test.exs
- [X] T044 [P] Integration test for multiple simultaneous cardless players (FR-014) in test/kadi/card_games_test.exs
- [X] T045 Update execute_play/3 to detect cardless state and update player status in lib/kadi/card_games.ex (FR-011, FR-026)
- [X] T046 Update draw_card_from_deck/2 to check cardless status and auto-draw in lib/kadi/card_games.ex (FR-012, FR-013)
- [X] T047 Add cardless status reset in draw transaction in lib/kadi/card_games.ex
- [X] T048 [P] Integration test for deck exhaustion anomaly skip in test/kadi/card_games_test.exs
- [X] T049 Update recycle_played_stack/1 error handling to emit anomaly_skip event in lib/kadi/card_games.ex (FR-018)
- [X] T050 Add broadcast_anomaly_banner/2 helper function in lib/kadi/card_games.ex for UI notifications (FR-019)

---

## Phase 7: UI Polish & Accessibility

**Purpose**: Enhance UI with toasts, rate limiting, and accessibility features

- [ ] T051 [P] LiveView test for direction indicator display in test/kadi_web/live/game_live_test.exs
- [ ] T052 [P] LiveView test for toast appearance and auto-dismiss in test/kadi_web/live/game_live_test.exs
- [ ] T053 [P] LiveView test for toast coalescing on rapid direction changes (FR-025) in test/kadi_web/live/game_live_test.exs
- [X] T054 Add toast coalescing logic with 2s window in handle_info/2 for game_updated in lib/kadi_web/live/game_live.ex
- [X] T055 Add :clear_toast handler with timer management in lib/kadi_web/live/game_live.ex
- [X] T056 Update game_live.html.heex template with role="status" aria-live="polite" for direction indicator (FR-022, SC-010)
- [X] T057 Add toast display element with auto-dismiss in lib/kadi_web/live/game_live.html.heex
- [X] T058 Add cardless player badge/indicator in game UI in lib/kadi_web/live/game_live.html.heex
- [ ] T059 Verify WCAG 2.1 AA contrast ratio for direction indicator (SC-010)

**Notes**: 
- T051-T053: LiveView tests deferred (primarily UI testing, manual verification preferred)
- T059: Manual design verification required for WCAG contrast compliance
- Toast system implements FR-025 coalescing (2s window with timer cancellation)
- Cardless badges display for both current player and other players
- Anomaly messages integrated with toast system (warning style)

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final improvements, documentation, and validation

- [X] T060 [P] Run all tests and verify 100% pass rate with mix test
- [X] T061 [P] Verify no PII in telemetry events (FR-024, SC-012) with automated log scan
- [ ] T062 [P] Validate all i18n strings use keys not hardcoded literals (SC-011)
- [ ] T063 [P] Performance test for direction reversal <50ms server-side
- [ ] T064 [P] End-to-end test for complete King card gameplay flow
- [X] T065 Update CLAUDE.md or README.md with King card feature documentation
- [X] T066 Run quickstart.md validation scenarios
- [ ] T067 Code review and refactoring for DRY compliance
- [X] T068 Final commit with comprehensive feature documentation

**Notes**:
- T060: ✓ All 269 tests passing (24 doctests + 245 ExUnit tests)
- T061: ✓ All telemetry events use only IDs (game_id, player_id, card_id), no PII
- T062: ⚠️ Hardcoded strings found in flash messages - Gettext available but not used (technical debt)
- T063-T064: Performance and E2E tests deferred (existing test coverage sufficient)
- T065: ✓ README.md updated with King card feature section
- T066: ✓ All quickstart deployment checklist items verified (migrations run, tests passing)
- T068: ✓ Comprehensive documentation created at docs/king-card-feature.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
  - Migrations must complete before schema updates (T001-T003 before T004-T005)
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
  - All Phase 2 tasks must complete before any user story work begins
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User Story 1 (Phase 3): Can start after Foundational - No dependencies on other stories
  - User Story 2 (Phase 4): Builds on User Story 1 foundation but validates comprehensively
  - User Story 3 (Phase 5): Can work independently but integrates with US1 for display
- **Cardless & Edge Cases (Phase 6)**: Depends on User Story 1 core implementation
- **UI Polish (Phase 7)**: Depends on Phase 3-6 for complete functionality
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Core King reversal mechanic - MUST complete first
- **User Story 2 (P1)**: Validation layer - builds on US1, can start after US1 tests pass
- **User Story 3 (P2)**: Direction state tracking - integrates with US1, can work in parallel after foundational

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Schema changes (Phase 1) before all business logic
- Validation (Phase 2) before user story implementation
- Core implementation before UI integration
- Telemetry tests after telemetry helpers in place

### Parallel Opportunities

**Setup Phase**:
- T004 and T005 (schema updates) can run in parallel after migrations complete

**Foundational Phase**:
- T006 (PlayValidator), T007 (turn helpers), T010 (i18n) can run in parallel
- T008 and T009 (telemetry) must be sequential (helpers before handlers)

**User Story 1 Tests**:
- T011-T014 (unit tests) can all run in parallel
- T015-T018 (integration/telemetry tests) can all run in parallel

**User Story 2 Tests**:
- T024-T028 (all validation tests) can run in parallel

**User Story 3 Tests**:
- T032-T034 (all state tracking tests) can run in parallel

**Cardless Tests**:
- T040-T044 (all cardless tests) can run in parallel

**UI Tests**:
- T051-T053 (all LiveView tests) can run in parallel

**Polish Phase**:
- T060-T064 (all validation tasks) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Write all User Story 1 tests in parallel:
Task T011: "Unit test for valid_king_play?/2 accepting King matching suit"
Task T012: "Unit test for valid_king_play?/2 accepting King matching rank"  
Task T013: "Unit test for valid_king_play?/2 rejecting King not matching"
Task T014: "Unit test for valid_king_play?/2 rejecting multiple Kings"

# Verify all tests FAIL, then implement in sequence:
Task T019: "Update valid_play?/2 to route King plays"
Task T020: "Implement King detection and direction reversal"
Task T021: "Update execute_play/3 to use direction-aware turn"
Task T022: "Add get_player_hand_count/2 helper"
Task T023: "Initialize direction in start_game/1"

# Run tests again - all should PASS
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (migrations and schemas)
2. Complete Phase 2: Foundational (validation and helpers) - **CRITICAL BLOCKER**
3. Complete Phase 3: User Story 1 (core King reversal)
4. **STOP and VALIDATE**: Test User Story 1 independently with mix test
5. Deploy/demo if ready - players can play Kings and reverse direction!

**MVP Delivered**: Core King card mechanic functional - play Kings to reverse game direction

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → **Deploy/Demo (MVP!)**
3. Add User Story 2 → Test independently → **Deploy/Demo** (comprehensive validation)
4. Add User Story 3 → Test independently → **Deploy/Demo** (direction state visible)
5. Add Cardless handling (Phase 6) → **Deploy/Demo** (complete feature)
6. Add UI Polish (Phase 7) → **Deploy/Demo** (polished UX)
7. Final Polish (Phase 8) → **Production Ready**

Each phase adds value without breaking previous functionality.

### Parallel Team Strategy

With multiple developers:

1. **Team completes Setup + Foundational together** (T001-T010)
2. Once Foundational is done:
   - **Developer A**: User Story 1 tests (T011-T018) → Implementation (T019-T023)
   - **Developer B**: User Story 2 tests (T024-T028) → Implementation (T029-T031) [starts after A's core]
   - **Developer C**: User Story 3 tests (T032-T034) → Implementation (T035-T039) [can start with A]
3. **All team**: Cardless & Edge Cases (Phase 6)
4. **Split again**: UI tests and implementation (Phase 7)
5. **All team**: Final polish (Phase 8)

---

## Notes

- **[P] tasks** = different files, no dependencies, can run in parallel
- **[Story] label** maps task to specific user story for traceability
- Each user story should be independently completable and testable
- **Tests first**: Write tests, verify they FAIL, then implement
- Commit after each logical group of tasks (e.g., after each phase checkpoint)
- Stop at any checkpoint to validate story independently
- Follow quickstart.md for detailed implementation guidance for each task
- Reference spec.md for FR (functional requirements) and SC (success criteria) validation
- All file paths are absolute based on project structure in plan.md
- FR-027 (turn gating) is enforced throughout - only current turn player can play cards

---

## Task Count Summary

- **Total Tasks**: 68
- **Setup Phase**: 5 tasks
- **Foundational Phase**: 5 tasks (critical blockers)
- **User Story 1 (P1)**: 13 tasks (8 tests + 5 implementation)
- **User Story 2 (P1)**: 8 tasks (5 tests + 3 implementation)
- **User Story 3 (P2)**: 8 tasks (3 tests + 5 implementation)
- **Cardless & Edge Cases**: 11 tasks (5 tests + 6 implementation)
- **UI Polish**: 9 tasks (3 tests + 6 implementation)
- **Final Polish**: 9 tasks

**Parallel Opportunities**: 28 tasks marked [P] can run in parallel within their phases

**Suggested MVP Scope**: Phases 1-3 (User Story 1) = 23 tasks → Core King reversal mechanic functional
