# Tasks: Ace Card Special Action

**Input**: Design documents from `/specs/008-ace-card-feature/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md, contracts/  
**Branch**: `008-ace-card-feature`  
**Updated**: 2025-11-13 (suit persistence requirements)  
**Estimated Total Time**: 8-12 hours

**Tests**: Tests are included as this is a core gameplay feature requiring comprehensive coverage.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**CRITICAL UPDATE (2025-11-13)**: Suit persistence behavior clarified - `action_suit` must persist across draws and multiple turns until matching suit played or new Ace overrides.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Core logic**: `lib/kadi/` and `lib/kadi/games/`
- **Web layer**: `lib/kadi_web/`
- **Tests**: `test/kadi/` and `test/kadi_web/`
- **Migrations**: `priv/repo/migrations/`
- **Specs**: `specs/008-ace-card-feature/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify prerequisites and environment

**Estimated Time**: 15-30 minutes

- [X] T001 Verify all tests pass on main branch: `mix test`
- [X] T002 Confirm feature branch `008-ace-card-feature` exists and is checked out
- [X] T003 [P] Verify PostgreSQL running and database `kadi_dev` accessible
- [X] T004 [P] Review existing King and Jack card implementation patterns in lib/kadi/card_games.ex
- [X] T005 [P] Review validation patterns in lib/kadi/games/play_validator.ex

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database schema and validation infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

**Estimated Time**: 1.5-2 hours

### Database Migration

- [X] T006 Create migration to add action fields to game_sessions table in priv/repo/migrations/
- [X] T007 Run migration: `mix ecto.migrate`
- [X] T008 Verify migration rollback works: `mix ecto.rollback`, then re-run migrate

### Schema Updates

- [X] T009 Update GameSession schema in lib/kadi/games/game_session.ex with action_type and action_suit fields
- [X] T010 Update GameSession changeset in lib/kadi/games/game_session.ex to validate new fields
- [X] T011 Add module constants for valid action_types and suits in lib/kadi/games/game_session.ex

### Validation Infrastructure

- [X] T012 [P] Add `valid_ace_play?/2` function in lib/kadi/games/play_validator.ex
- [X] T013 Update `valid_play?/2` in lib/kadi/games/play_validator.ex to handle Ace detection
- [X] T014 Add suit validation when action_suit is set in lib/kadi/games/play_validator.ex (Note: Only lead card must match requested suit for combos)

### Validation Tests

- [X] T015 [P] Add test: Ace can be played regardless of top card in test/kadi/games/play_validator_test.exs
- [X] T016 [P] Add test: Ace matching validates true in test/kadi/games/play_validator_test.exs
- [X] T017 [P] Add test: When action_suit set, only lead card must match in test/kadi/games/play_validator_test.exs
- [X] T018 [P] Add test: When action_suit set, another Ace is also accepted in test/kadi/games/play_validator_test.exs

### Verification

- [X] T019 Run validation tests: `mix test test/kadi/games/play_validator_test.exs`
- [X] T020 Verify no compilation warnings: `mix compile --warnings-as-errors`

**Checkpoint**: Validation layer and database ready - all user stories can now proceed

---

## Phase 3: User Story 1 - Core Ace Logic (Priority: P1) 🎯 MVP

**Goal**: Implement core Ace card mechanic in CardGames context where playing an Ace prompts suit selection and sets the required suit for the next turn

**Independent Test**: Start game, give player an Ace, play it via context function, verify game enters "select_suit" state, select suit, verify state updated

**Estimated Time**: 2-2.5 hours

### Core Ace Play Logic

- [X] T021 [US1] Add Ace detection in `execute_play/3` in lib/kadi/card_games.ex
- [X] T022 [US1] Update `execute_play/3` to set action_type to "select_suit" when Ace played in lib/kadi/card_games.ex
- [X] T023 [US1] Ensure turn does NOT advance when Ace played (awaiting suit selection) in lib/kadi/card_games.ex
- [X] T024 [US1] Update top_card_id to the played Ace in lib/kadi/card_games.ex

### Suit Selection Logic

- [X] T025 [US1] Create `select_suit/3` function in lib/kadi/card_games.ex
- [X] T026 [US1] Validate player is current turn player in `select_suit/3` in lib/kadi/card_games.ex
- [X] T027 [US1] Validate game is in "select_suit" state in `select_suit/3` in lib/kadi/card_games.ex
- [X] T028 [US1] Update action_type to nil and action_suit to selected suit in lib/kadi/card_games.ex
- [X] T029 [US1] Advance turn to next player after suit selection in lib/kadi/card_games.ex
- [X] T030 [US1] Broadcast game update after suit selection in lib/kadi/card_games.ex

### Telemetry Integration

- [X] T031 [P] [US1] Add telemetry event `[:kadi, :ace, :suit_selected]` in lib/kadi/card_games.ex
- [X] T032 [P] [US1] Create helper function `emit_ace_suit_selected_event/4` in lib/kadi/card_games.ex

### Integration Tests

- [X] T033 [US1] Add test: Playing Ace sets action_type to "select_suit" in test/kadi/card_games_test.exs
- [X] T034 [US1] Add test: Turn does not advance when Ace played in test/kadi/card_games_test.exs
- [X] T035 [US1] Add test: select_suit updates action_suit and advances turn in test/kadi/card_games_test.exs
- [X] T036 [US1] Add test: select_suit with invalid player returns error in test/kadi/card_games_test.exs
- [X] T037 [US1] Add test: select_suit with invalid game state returns error in test/kadi/card_games_test.exs
- [X] T038 [US1] Add test: Telemetry event emitted on suit selection in test/kadi/card_games_test.exs

### Verification

- [X] T039 [US1] Run integration tests: `mix test test/kadi/card_games_test.exs`
- [X] T040 [US1] Verify no compilation warnings: `mix compile --warnings-as-errors`

**Checkpoint**: User Story 1 core logic complete - Ace card can be played and suit can be selected via context functions ✅

---

## Phase 4: User Story 1 - LiveView UI (Priority: P1) 🎯 MVP

**Goal**: Add LiveView UI layer to allow players to select suits after playing an Ace

**Independent Test**: Play Ace via UI, verify suit selection buttons appear, click suit, verify game state updates

**Estimated Time**: 1.5-2 hours

### LiveView UI Implementation

- [X] T041 [US1] Add `handle_event("select_suit", ...)` in lib/kadi_web/live/game_live.ex
- [X] T042 [US1] Add conditional rendering for suit selection buttons in lib/kadi_web/live/game_live.html.heex
- [X] T043 [US1] Style suit selection buttons using Tailwind CSS in lib/kadi_web/live/game_live.html.heex
- [X] T044 [US1] Display message "Select a suit:" when awaiting selection in lib/kadi_web/live/game_live.html.heex

### LiveView Tests

- [X] T045 [US1] Add test: Suit selection buttons appear after Ace played in test/kadi_web/live/game_live_test.exs
- [X] T046 [US1] Add test: Clicking suit button calls select_suit event in test/kadi_web/live/game_live_test.exs
- [X] T047 [US1] Add test: Suit selection buttons disappear after selection in test/kadi_web/live/game_live_test.exs

### Verification

- [X] T048 [US1] Run LiveView tests: `mix test test/kadi_web/live/game_live_test.exs`
- [ ] T049 [US1] Manual test: Play Ace via UI, select suit, verify state update

**Checkpoint**: User Story 1 UI complete - Full Ace play and suit selection working in UI ✅

---

## Phase 5: User Story 2 - Subsequent player must follow requested suit (Priority: P2) ✅

**Goal**: Enforce that next player must play card matching requested suit or draw. **CRITICAL (2025-11-13)**: Suit requirement persists across draws and multiple turns.

**Independent Test**: Following US1 test, verify next player can only play matching suit or must draw. Verify suit requirement persists after draw.

**Estimated Time**: 2-3 hours

### Enforcement Logic

- [X] T050 [US2] Update `validate_can_play/2` to check action_suit in lib/kadi/card_games.ex
- [X] T051 [US2] Ensure validation rejects non-matching suit when action_suit set in lib/kadi/card_games.ex
- [X] T052 [US2] Clear action_suit after successful matching play in lib/kadi/card_games.ex
- [X] T053 [US2] Ensure Ace bypasses action_suit validation in lib/kadi/card_games.ex

### Draw Card Logic (UPDATED 2025-11-13)

- [X] T054 [US2] **CRITICAL UPDATE**: Verify `draw_card_from_deck/2` does NOT clear action_suit (requirement persists) in lib/kadi/card_games.ex
- [X] T055 [US2] Ensure drawn card cannot be played in same turn in lib/kadi/card_games.ex

### Integration Tests (UPDATED 2025-11-13)

- [X] T056 [P] [US2] Add test: Next player can play matching suit card in test/kadi/card_games/special_cards_ace_test.exs
- [X] T057 [P] [US2] Add test: Next player cannot play non-matching suit card in test/kadi/card_games/special_cards_ace_test.exs
- [X] T058 [P] [US2] **UPDATED**: Add test: After draw, action_suit persists for next player in test/kadi/card_games/special_cards_ace_test.exs
- [X] T059 [P] [US2] Add test: action_suit cleared after successful matching play in test/kadi/card_games/special_cards_ace_test.exs
- [X] T060 [P] [US2] **UPDATED**: Add test: Multiple players drawing in sequence, action_suit persists until matching card played in test/kadi/card_games/special_cards_ace_test.exs

### UI Enhancement

- [X] T061 [US2] Display active suit requirement banner (purple) with suit symbol in lib/kadi_web/live/game_live.html.heex
- [X] T062 [US2] Highlight cards matching required suit in green border (or Aces) in lib/kadi_web/live/game_live.html.heex
- [X] T063 [US2] Show specific error message when invalid card played ("must play {suit} or Ace") in lib/kadi_web/live/game_live.ex

### Verification

- [X] T064 [US2] Run enforcement tests: `mix test test/kadi/card_games/special_cards_ace_test.exs`
- [ ] T065 [US2] Manual test: Play non-matching card after Ace, verify rejection with specific error

**Checkpoint**: User Story 2 complete - suit requirement enforced with persistence across draws ✅

---

## Phase 6: User Story 3 - Ace Override (Priority: P3)

**Goal**: Allow players to play an Ace to override the current suit requirement and set a new one

**Independent Test**: Following US2 test, have next player play an Ace, verify they can set a new suit that replaces the old requirement

**Estimated Time**: 1-1.5 hours

### Override Logic

- [X] T066 [US3] Verify Ace validation already bypasses action_suit check (from T053) in lib/kadi/games/play_validator.ex
- [X] T067 [US3] Verify `execute_play/3` handles Ace when action_suit is set in lib/kadi/card_games.ex
- [X] T068 [US3] Ensure old action_suit is cleared when new Ace played in lib/kadi/card_games.ex
- [X] T069 [US3] Verify `select_suit/3` replaces previous action_suit with new selection in lib/kadi/card_games.ex

### Integration Tests

- [X] T070 [P] [US3] Add test: Playing Ace when action_suit is set triggers suit selection in test/kadi/card_games/special_cards_ace_test.exs
- [X] T071 [P] [US3] Add test: New selected suit replaces old action_suit in test/kadi/card_games/special_cards_ace_test.exs
- [X] T072 [P] [US3] Add test: Next player must follow new suit, not old suit in test/kadi/card_games/special_cards_ace_test.exs

### Verification

- [X] T073 [US3] Run override tests: `mix test test/kadi/card_games/special_cards_ace_test.exs`

**Checkpoint**: User Story 3 complete - Ace can override existing suit requirements ✅

---

## Phase 7: Edge Cases & Special Scenarios

**Goal**: Handle edge cases and integration with other special cards

**Estimated Time**: 2-3 hours

### Edge Case Implementation

- [ ] T074 [P] Add test: Playing Ace as last card wins game (no suit selection) in test/kadi/card_games_test.exs
- [ ] T075 [P] Add test: Multiple Aces in one play only prompts once in test/kadi/card_games_test.exs
- [ ] T076 [P] Add test: Draw when deck empty and action_suit set recycles correctly in test/kadi/card_games_test.exs
- [ ] T077 [P] Add test: Draw deck exhaustion with action_suit logs anomaly in test/kadi/card_games_test.exs
- [ ] T078 [P] Add test: Ace after King respects counter-clockwise direction in test/kadi/card_games_test.exs
- [ ] T079 [P] Add test: King after Ace preserves action_suit in test/kadi/card_games_test.exs
- [ ] T080 [P] Add test: Jack after Ace skips players but preserves action_suit in test/kadi/card_games_test.exs
- [ ] T081 [P] Add test: Ace allowed as starting card, first player can play any suit in test/kadi/card_games_test.exs

### Starting Card Logic

- [ ] T082 Verify "ace" is NOT in excluded start cards list in lib/kadi/card_games.ex
- [ ] T083 Remove "ace" from special_ranks excluded list if present in lib/kadi/card_games.ex

### Disconnection Handling

- [ ] T084 Add test: Game state persists if player disconnects during suit selection in test/kadi_web/live/game_live_test.exs
- [ ] T085 Verify LiveView reconnection shows suit selection prompt in test/kadi_web/live/game_live_test.exs

### Verification

- [ ] T086 Run edge case tests: `mix test test/kadi/card_games_test.exs`
- [ ] T087 Manual test: Trigger deck exhaustion scenario via UI

**Checkpoint**: All edge cases handled correctly ✅

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, documentation, final verification

**Estimated Time**: 1-1.5 hours

### Code Quality

- [ ] T088 [P] Run formatter: `mix format`
- [ ] T089 [P] Verify no compilation warnings: `mix compile --warnings-as-errors`
- [ ] T090 [P] Run full test suite: `mix test`
- [ ] T091 [P] Verify test coverage for Ace-specific logic: `mix test --cover`

### Documentation

- [ ] T092 [P] Add module docs for Ace logic in lib/kadi/card_games.ex
- [ ] T093 [P] Add @doc for `select_suit/3` function in lib/kadi/card_games.ex
- [ ] T094 [P] Add @doc for Ace validation functions in lib/kadi/games/play_validator.ex
- [ ] T095 [P] Create feature documentation in docs/ace-card-feature.md
- [ ] T096 Update README.md with Ace card summary and link to docs/ace-card-feature.md

### Telemetry Handler

- [ ] T097 Add Ace telemetry handlers in lib/kadi/application.ex (similar to King/Jack)
- [ ] T098 Test telemetry logging with: `mix phx.server` and play an Ace

### Final Verification

- [ ] T099 Run quickstart.md verification checklist from specs/008-ace-card-feature/quickstart.md
- [ ] T100 Manual end-to-end test: Complete game using Aces in various scenarios
- [ ] T101 Verify no regressions in King and Jack functionality
- [ ] T102 Check telemetry events visible in logs during manual testing
- [ ] T103 Verify UI responsive and accessible on mobile/desktop

**Checkpoint**: Feature complete and ready for PR ✅

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-6)**: All depend on Foundational phase completion
  - US1 Core Logic (Phase 3): Ace play and suit selection backend - FOUNDATIONAL for Phase 4-6
  - US1 LiveView UI (Phase 4): UI layer for Ace play - Depends on Phase 3 completion
  - US2 (Phase 5): Suit enforcement - Depends on Phases 3-4 being complete
  - US3 (Phase 6): Ace override - Depends on Phases 3-4, can run after Phase 5
- **Edge Cases (Phase 7)**: Depends on US1, US2, US3 (Phases 3-6)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 Core Logic (P1 - Phase 3)**: Can start after Phase 2 - No dependencies on other stories
- **US1 LiveView UI (P1 - Phase 4)**: Can start after Phase 3 - Requires core logic
- **US2 (P2 - Phase 5)**: Can start after Phases 3-4 - Requires full US1 implementation
- **US3 (P3 - Phase 6)**: Can start after Phases 3-4 - Can run in parallel with Phase 5

### Suggested Execution Order

**Sequential (Single Developer)**:
1. Phase 1: Setup (15-30 min)
2. Phase 2: Foundational (1.5-2 hours) - MUST complete before proceeding
3. Phase 3: US1 Core Logic (2-2.5 hours) - Backend mechanic
4. Phase 4: US1 LiveView UI (1.5-2 hours) - Frontend integration
5. Phase 5: US2 Suit enforcement (2-3 hours) - Makes US1 meaningful
6. Phase 6: US3 Ace override (1-1.5 hours) - Strategic depth
7. Phase 7: Edge cases (2-3 hours) - Integration testing
8. Phase 8: Polish (1-1.5 hours) - Final verification

**Parallel (Multiple Developers)**:
- After Phase 2 completes:
  - **Track A**: Phase 3 (US1 Core Logic, 2-2.5 hours)
  - **Track B**: Can prepare edge case tests
- After Phase 3 completes:
  - **Track A**: Phase 4 (US1 LiveView UI, 1.5-2 hours)
  - **Track B**: Can start on Phase 6 (US3 override logic, needs Phase 3 only)
- After Phase 4 completes:
  - **Track A**: Phase 5 (US2 enforcement, 2-3 hours)
  - **Track B**: Continue Phase 6 if not complete
- After both tracks complete: Phase 7 (edge cases)
- Final: Phase 8 (polish)

### MVP Scope

**Minimum Viable Product (MVP)**: Phases 1-4 (US1 complete - backend + frontend)
- Basic Ace play and suit selection with full UI
- No enforcement, no override
- Can be released as "Ace card (basic play only)"
- Estimated time: 5.5-7 hours

**Full Feature**: All phases
- MVP + enforcement + override + edge cases
- Estimated time: 13-17 hours

### Parallel Opportunities

- **Phase 1**: Tasks T003, T004, T005 can run in parallel
- **Phase 2**: 
  - Validation functions (T012, T013, T014) can run after migration
  - All validation tests (T015-T018) can run in parallel after functions complete
- **Phase 3-7**: Tests within each phase can run in parallel where marked [P]
- **Phase 8**: Most polish tasks (T088-T096) can run in parallel

---

## Task Summary

- **Total Tasks**: 103
- **Setup Tasks**: 5
- **Foundational Tasks**: 15
- **User Story 1 Core Logic Tasks**: 20
- **User Story 1 LiveView UI Tasks**: 9
- **User Story 2 Tasks**: 16
- **User Story 3 Tasks**: 8
- **Edge Cases Tasks**: 14
- **Polish Tasks**: 16

**Parallel Tasks**: 45 tasks marked [P] can run in parallel within their phase

**Estimated Total Time**: 13-17 hours (sequential execution)

**MVP Time**: 5.5-7 hours (Phases 1-4 only)

---

## Implementation Strategy

1. **MVP First**: Complete US1 (Phases 3-4: Core logic + UI) for basic functionality
2. **Incremental Delivery**: Each user story adds independent value:
   - US1 Core Logic (Phase 3): Backend can be tested independently
   - US1 UI (Phase 4): Full Ace play and suit selection → testable feature
   - US2 (Phase 5): Suit enforcement works → complete mechanic
   - US3 (Phase 6): Ace override works → strategic depth
3. **Test-Driven**: Write tests before implementation for each story
4. **Continuous Verification**: Run tests after each task to catch regressions early
5. **Manual Testing**: Verify UI behavior after each major milestone (Phase 4, Phase 5, Phase 6)

---

## Success Criteria

Feature is complete when all tasks are checked and:

- ✅ All 9 functional requirements (FR-001 through FR-009) implemented
- ✅ All 4 success criteria (SC-001 through SC-004) verified
- ✅ All 3 user stories have passing acceptance tests
- ✅ Edge cases (last card, multiple Aces, deck exhaustion, integration) handled
- ✅ Telemetry events emitting correctly
- ✅ No regressions in existing features (King, Jack, regular cards)
- ✅ Code passes all constitution checks (DRY, pattern matching, error handling)
- ✅ Manual UI testing confirms expected behavior
- ✅ Documentation complete (module docs + feature docs)
- ✅ Full test suite passes: `mix test`
