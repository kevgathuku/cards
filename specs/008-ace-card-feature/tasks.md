# Tasks: Ace Card Special Action

**Input**: Design documents from `/specs/008-ace-card-feature/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md, contracts/  
**Branch**: `008-ace-card-feature`  
**Estimated Total Time**: 8-12 hours

**Tests**: Tests are included as this is a core gameplay feature requiring comprehensive coverage.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

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

- [ ] T001 Verify all tests pass on main branch: `mix test`
- [ ] T002 Confirm feature branch `008-ace-card-feature` exists and is checked out
- [ ] T003 [P] Verify PostgreSQL running and database `kadi_dev` accessible
- [ ] T004 [P] Review existing King and Jack card implementation patterns in lib/kadi/card_games.ex
- [ ] T005 [P] Review validation patterns in lib/kadi/games/play_validator.ex

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database schema and validation infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

**Estimated Time**: 1.5-2 hours

### Database Migration

- [ ] T006 Create migration to add action fields to game_sessions table in priv/repo/migrations/
- [ ] T007 Run migration: `mix ecto.migrate`
- [ ] T008 Verify migration rollback works: `mix ecto.rollback`, then re-run migrate

### Schema Updates

- [ ] T009 Update GameSession schema in lib/kadi/games/game_session.ex with action_type and action_suit fields
- [ ] T010 Update GameSession changeset in lib/kadi/games/game_session.ex to validate new fields
- [ ] T011 Add module constants for valid action_types and suits in lib/kadi/games/game_session.ex

### Validation Infrastructure

- [ ] T012 [P] Add `valid_ace_play?/2` function in lib/kadi/games/play_validator.ex
- [ ] T013 Update `valid_play?/2` in lib/kadi/games/play_validator.ex to handle Ace detection
- [ ] T014 Add suit validation when action_suit is set in lib/kadi/games/play_validator.ex

### Validation Tests

- [ ] T015 [P] Add test: Ace can be played regardless of top card in test/kadi/games/play_validator_test.exs
- [ ] T016 [P] Add test: Ace matching validates true in test/kadi/games/play_validator_test.exs
- [ ] T017 [P] Add test: When action_suit set, only matching suit accepted in test/kadi/games/play_validator_test.exs
- [ ] T018 [P] Add test: When action_suit set, another Ace is also accepted in test/kadi/games/play_validator_test.exs

### Verification

- [ ] T019 Run validation tests: `mix test test/kadi/games/play_validator_test.exs`
- [ ] T020 Verify no compilation warnings: `mix compile --warnings-as-errors`

**Checkpoint**: Validation layer and database ready - all user stories can now proceed

---

## Phase 3: User Story 1 - Player uses Ace to change required suit (Priority: P1) 🎯 MVP

**Goal**: Implement core Ace card mechanic where playing an Ace prompts suit selection and sets the required suit for the next turn

**Independent Test**: Start game, give player an Ace, play it, verify game enters "select_suit" state, select suit, verify state updated

**Estimated Time**: 3-4 hours

### Core Ace Play Logic

- [ ] T021 [US1] Add Ace detection in `execute_play/3` in lib/kadi/card_games.ex
- [ ] T022 [US1] Update `execute_play/3` to set action_type to "select_suit" when Ace played in lib/kadi/card_games.ex
- [ ] T023 [US1] Ensure turn does NOT advance when Ace played (awaiting suit selection) in lib/kadi/card_games.ex
- [ ] T024 [US1] Update top_card_id to the played Ace in lib/kadi/card_games.ex

### Suit Selection Logic

- [ ] T025 [US1] Create `select_suit/3` function in lib/kadi/card_games.ex
- [ ] T026 [US1] Validate player is current turn player in `select_suit/3` in lib/kadi/card_games.ex
- [ ] T027 [US1] Validate game is in "select_suit" state in `select_suit/3` in lib/kadi/card_games.ex
- [ ] T028 [US1] Update action_type to nil and action_suit to selected suit in lib/kadi/card_games.ex
- [ ] T029 [US1] Advance turn to next player after suit selection in lib/kadi/card_games.ex
- [ ] T030 [US1] Broadcast game update after suit selection in lib/kadi/card_games.ex

### Telemetry Integration

- [ ] T031 [P] [US1] Add telemetry event `[:kadi, :ace, :suit_selected]` in lib/kadi/card_games.ex
- [ ] T032 [P] [US1] Create helper function `emit_ace_suit_selected_event/4` in lib/kadi/card_games.ex

### Integration Tests

- [ ] T033 [US1] Add test: Playing Ace sets action_type to "select_suit" in test/kadi/card_games_test.exs
- [ ] T034 [US1] Add test: Turn does not advance when Ace played in test/kadi/card_games_test.exs
- [ ] T035 [US1] Add test: select_suit updates action_suit and advances turn in test/kadi/card_games_test.exs
- [ ] T036 [US1] Add test: select_suit with invalid player returns error in test/kadi/card_games_test.exs
- [ ] T037 [US1] Add test: select_suit with invalid game state returns error in test/kadi/card_games_test.exs
- [ ] T038 [US1] Add test: Telemetry event emitted on suit selection in test/kadi/card_games_test.exs

### LiveView UI Implementation

- [ ] T039 [US1] Add `handle_event("select_suit", ...)` in lib/kadi_web/live/game_live.ex
- [ ] T040 [US1] Add conditional rendering for suit selection buttons in lib/kadi_web/live/game_live.html.heex
- [ ] T041 [US1] Style suit selection buttons using Tailwind CSS in lib/kadi_web/live/game_live.html.heex
- [ ] T042 [US1] Display message "Select a suit:" when awaiting selection in lib/kadi_web/live/game_live.html.heex

### LiveView Tests

- [ ] T043 [US1] Add test: Suit selection buttons appear after Ace played in test/kadi_web/live/game_live_test.exs
- [ ] T044 [US1] Add test: Clicking suit button calls select_suit event in test/kadi_web/live/game_live_test.exs
- [ ] T045 [US1] Add test: Suit selection buttons disappear after selection in test/kadi_web/live/game_live_test.exs

### Verification

- [ ] T046 [US1] Run integration tests: `mix test test/kadi/card_games_test.exs`
- [ ] T047 [US1] Run LiveView tests: `mix test test/kadi_web/live/game_live_test.exs`
- [ ] T048 [US1] Manual test: Play Ace via UI, select suit, verify state update

**Checkpoint**: User Story 1 complete - Ace card can be played and suit can be selected ✅

---

## Phase 4: User Story 2 - Subsequent player must follow requested suit (Priority: P2) ✅

**Goal**: Enforce that next player must play card matching requested suit or draw

**Independent Test**: Following US1 test, verify next player can only play matching suit or must draw

**Estimated Time**: 2-3 hours

### Enforcement Logic

- [ ] T049 [US2] Update `validate_can_play/2` to check action_suit in lib/kadi/card_games.ex
- [ ] T050 [US2] Ensure validation rejects non-matching suit when action_suit set in lib/kadi/card_games.ex
- [ ] T051 [US2] Clear action_suit after successful matching play in lib/kadi/card_games.ex
- [ ] T052 [US2] Ensure Ace bypasses action_suit validation in lib/kadi/card_games.ex

### Draw Card Logic

- [ ] T053 [US2] Update `draw_card_from_deck/2` to clear action_suit after draw in lib/kadi/card_games.ex
- [ ] T054 [US2] Ensure drawn card cannot be played in same turn in lib/kadi/card_games.ex

### Integration Tests

- [ ] T055 [P] [US2] Add test: Next player can play matching suit card in test/kadi/card_games_test.exs
- [ ] T056 [P] [US2] Add test: Next player cannot play non-matching suit card in test/kadi/card_games_test.exs
- [ ] T057 [P] [US2] Add test: Player with no matching suit can draw card in test/kadi/card_games_test.exs
- [ ] T058 [P] [US2] Add test: action_suit cleared after successful play in test/kadi/card_games_test.exs
- [ ] T059 [P] [US2] Add test: action_suit cleared after draw in test/kadi/card_games_test.exs

### UI Enhancement

- [ ] T060 [US2] Display active suit requirement in UI in lib/kadi_web/live/game_live.html.heex
- [ ] T061 [US2] Highlight cards matching required suit in player hand in lib/kadi_web/live/game_live.html.heex
- [ ] T062 [US2] Show error message when invalid card played in lib/kadi_web/live/game_live.ex

### Verification

- [ ] T063 [US2] Run enforcement tests: `mix test test/kadi/card_games_test.exs`
- [ ] T064 [US2] Manual test: Play non-matching card after Ace, verify rejection

**Checkpoint**: User Story 2 complete - suit requirement enforced ✅

---

## Phase 5: User Story 3 - Player uses another Ace to override (Priority: P3)

**Goal**: Allow playing another Ace to change the requested suit again

**Independent Test**: Following US2 test, give next player an Ace, play it, verify they can set new suit

**Estimated Time**: 1-1.5 hours

### Override Logic

- [ ] T065 [US3] Verify Ace validation bypasses action_suit check (should already work) in lib/kadi/games/play_validator.ex
- [ ] T066 [US3] Ensure playing Ace when action_suit is set works correctly in lib/kadi/card_games.ex
- [ ] T067 [US3] Verify action_suit is cleared and new suit selection triggered in lib/kadi/card_games.ex

### Integration Tests

- [ ] T068 [P] [US3] Add test: Player can play Ace when action_suit is set in test/kadi/card_games_test.exs
- [ ] T069 [P] [US3] Add test: New suit selection overrides previous action_suit in test/kadi/card_games_test.exs
- [ ] T070 [P] [US3] Add test: Chain of 3 Aces with different suits in test/kadi/card_games_test.exs

### Verification

- [ ] T071 [US3] Run override tests: `mix test test/kadi/card_games_test.exs`
- [ ] T072 [US3] Manual test: Play Ace after Ace, verify suit can be changed

**Checkpoint**: User Story 3 complete - Ace can override previous Ace ✅

---

## Phase 6: Edge Cases & Special Scenarios

**Goal**: Handle edge cases and integration with other special cards

**Estimated Time**: 2-3 hours

### Edge Case Implementation

- [ ] T073 [P] Add test: Playing Ace as last card wins game (no suit selection) in test/kadi/card_games_test.exs
- [ ] T074 [P] Add test: Multiple Aces in one play only prompts once in test/kadi/card_games_test.exs
- [ ] T075 [P] Add test: Draw when deck empty and action_suit set recycles correctly in test/kadi/card_games_test.exs
- [ ] T076 [P] Add test: Draw deck exhaustion with action_suit logs anomaly in test/kadi/card_games_test.exs
- [ ] T077 [P] Add test: Ace after King respects counter-clockwise direction in test/kadi/card_games_test.exs
- [ ] T078 [P] Add test: King after Ace preserves action_suit in test/kadi/card_games_test.exs
- [ ] T079 [P] Add test: Jack after Ace skips players but preserves action_suit in test/kadi/card_games_test.exs
- [ ] T080 [P] Add test: Ace excluded from starting cards in test/kadi/card_games_test.exs

### Starting Card Logic

- [ ] T081 Verify "ace" is in excluded start cards list in lib/kadi/card_games.ex
- [ ] T082 Add "ace" to special_ranks if not already present in lib/kadi/card_games.ex

### Disconnection Handling

- [ ] T083 Add test: Game state persists if player disconnects during suit selection in test/kadi_web/live/game_live_test.exs
- [ ] T084 Verify LiveView reconnection shows suit selection prompt in test/kadi_web/live/game_live_test.exs

### Verification

- [ ] T085 Run edge case tests: `mix test test/kadi/card_games_test.exs`
- [ ] T086 Manual test: Trigger deck exhaustion scenario via UI

**Checkpoint**: All edge cases handled correctly ✅

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, documentation, final verification

**Estimated Time**: 1-1.5 hours

### Code Quality

- [ ] T087 [P] Run formatter: `mix format`
- [ ] T088 [P] Verify no compilation warnings: `mix compile --warnings-as-errors`
- [ ] T089 [P] Run full test suite: `mix test`
- [ ] T090 [P] Verify test coverage for Ace-specific logic: `mix test --cover`

### Documentation

- [ ] T091 [P] Add module docs for Ace logic in lib/kadi/card_games.ex
- [ ] T092 [P] Add @doc for `select_suit/3` function in lib/kadi/card_games.ex
- [ ] T093 [P] Add @doc for Ace validation functions in lib/kadi/games/play_validator.ex
- [ ] T094 [P] Create feature documentation in docs/ace-card-feature.md
- [ ] T095 Update README.md with Ace card summary and link to docs/ace-card-feature.md

### Telemetry Handler

- [ ] T096 Add Ace telemetry handlers in lib/kadi/application.ex (similar to King/Jack)
- [ ] T097 Test telemetry logging with: `mix phx.server` and play an Ace

### Final Verification

- [ ] T098 Run quickstart.md verification checklist from specs/008-ace-card-feature/quickstart.md
- [ ] T099 Manual end-to-end test: Complete game using Aces in various scenarios
- [ ] T100 Verify no regressions in King and Jack functionality
- [ ] T101 Check telemetry events visible in logs during manual testing
- [ ] T102 Verify UI responsive and accessible on mobile/desktop

**Checkpoint**: Feature complete and ready for PR ✅

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-5)**: All depend on Foundational phase completion
  - US1 (Phase 3): Ace play and suit selection - FOUNDATIONAL for US2 and US3
  - US2 (Phase 4): Suit enforcement - Depends on US1 being complete
  - US3 (Phase 5): Ace override - Depends on US1, can run after US2
- **Edge Cases (Phase 6)**: Depends on US1, US2, US3
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1 - Ace play & suit selection)**: Can start after Phase 2 - No dependencies on other stories
- **US2 (P2 - Suit enforcement)**: Can start after US1 - Requires Ace play logic
- **US3 (P3 - Ace override)**: Can start after US1 - Can run in parallel with US2

### Suggested Execution Order

**Sequential (Single Developer)**:
1. Phase 1: Setup (15-30 min)
2. Phase 2: Foundational (1.5-2 hours) - MUST complete before proceeding
3. Phase 3: US1 Ace play and suit selection (3-4 hours) - Core mechanic
4. Phase 4: US2 Suit enforcement (2-3 hours) - Makes US1 meaningful
5. Phase 5: US3 Ace override (1-1.5 hours) - Strategic depth
6. Phase 6: Edge cases (2-3 hours) - Integration testing
7. Phase 7: Polish (1-1.5 hours) - Final verification

**Parallel (Multiple Developers)**:
- After Phase 2 completes:
  - **Track A**: US1 (3-4 hours) - Ace play and suit selection
  - **Track B**: Can prepare edge case tests
- After US1 completes:
  - **Track A**: US2 (2-3 hours) - Suit enforcement
  - **Track B**: US3 (1-1.5 hours) - Ace override
- After both tracks complete: Phase 6 (edge cases)
- Final: Phase 7 (polish)

### MVP Scope

**Minimum Viable Product (MVP)**: Phases 1-3 (US1 only)
- Basic Ace play and suit selection
- No enforcement, no override
- Can be released as "Ace card (basic play only)"
- Estimated time: 5-6.5 hours

**Full Feature**: All phases
- MVP + enforcement + override + edge cases
- Estimated time: 12-16 hours

### Parallel Opportunities

- **Phase 1**: Tasks T003, T004, T005 can run in parallel
- **Phase 2**: 
  - Validation functions (T012, T013, T014) can run after migration
  - All validation tests (T015-T018) can run in parallel after functions complete
- **Phase 3-6**: Tests within each phase can run in parallel where marked [P]
- **Phase 7**: Most polish tasks (T087-T095) can run in parallel

---

## Task Summary

- **Total Tasks**: 102
- **Setup Tasks**: 5
- **Foundational Tasks**: 15
- **User Story 1 Tasks**: 28
- **User Story 2 Tasks**: 16
- **User Story 3 Tasks**: 8
- **Edge Cases Tasks**: 14
- **Polish Tasks**: 16

**Parallel Tasks**: 45 tasks marked [P] can run in parallel within their phase

**Estimated Total Time**: 12-16 hours (sequential execution)

**MVP Time**: 5-6.5 hours (Phases 1-3 only)

---

## Implementation Strategy

1. **MVP First**: Complete US1 (Ace play and suit selection) for basic functionality
2. **Incremental Delivery**: Each user story adds independent value:
   - US1: Ace can be played and suit selected → testable feature
   - US2: Suit enforcement works → complete mechanic
   - US3: Ace override works → strategic depth
3. **Test-Driven**: Write tests before implementation for each story
4. **Continuous Verification**: Run tests after each task to catch regressions early
5. **Manual Testing**: Verify UI behavior after each major milestone (US1, US2, US3)

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
