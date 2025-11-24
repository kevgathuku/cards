# Tasks: Jack Card (Jump/Skip Functionality)

**Input**: Design documents from `/specs/007-jack-card/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md  
**Branch**: `007-jack-card`  
**Estimated Total Time**: 5.5-7.5 hours

**Tests**: Tests are included as this is a core gameplay feature requiring comprehensive coverage.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5)
- Include exact file paths in descriptions

## Path Conventions

- **Core logic**: `lib/kadi/` and `lib/kadi/games/`
- **Web layer**: `lib/kadi_web/`
- **Tests**: `test/kadi/` and `test/kadi/games/`
- **Specs**: `specs/007-jack-card/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify prerequisites and environment

**Estimated Time**: 15-30 minutes

- [x] T001 Verify all tests pass on main branch: `mix test`
- [x] T002 Confirm feature branch `007-jack-card` exists and is checked out
- [x] T003 [P] Verify PostgreSQL running and database `kadi_dev` accessible
- [x] T004 [P] Review King card implementation pattern in lib/kadi/card_games.ex (lines 654-750)
- [x] T005 [P] Review existing cardless state logic in lib/kadi/card_games.ex

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core validation infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

**Estimated Time**: 1-1.5 hours

### Validation Function Implementation

- [x] T006 [P] Add `all_jacks?/1` helper function in lib/kadi/games/play_validator.ex
- [x] T007 [P] Add `valid_jack_play?/2` function in lib/kadi/games/play_validator.ex with @doc
- [x] T008 Update `valid_play?/2` in lib/kadi/games/play_validator.ex to handle Jack detection

### Validation Tests

- [x] T009 [P] Add test: single Jack matching by suit in test/kadi/games/play_validator_test.exs
- [x] T010 [P] Add test: single Jack matching by rank in test/kadi/games/play_validator_test.exs
- [x] T011 [P] Add test: Jack combo (all same rank) in test/kadi/games/play_validator_test.exs
- [x] T012 [P] Add test: reject Jack not matching suit or rank in test/kadi/games/play_validator_test.exs
- [x] T013 [P] Add test: reject combo with non-Jack cards in test/kadi/games/play_validator_test.exs

### Verification

- [x] T014 Run validation tests: `mix test test/kadi/games/play_validator_test.exs`
- [x] T015 Verify no compilation warnings: `mix compile --warnings-as-errors`

**Checkpoint**: Validation layer ready - all user stories can now proceed

---

## Phase 3: User Story 1 - Single Jack Skips Next Player (Priority: P1) 🎯 MVP

**Goal**: Implement basic Jack skip mechanic where playing 1 Jack skips 1 player

**Independent Test**: Setup 3-player game, play 1 Jack, verify turn advances 2 positions

**Estimated Time**: 1.5-2 hours

### Core Skip Logic Implementation

- [x] T016 [US1] Add `skip_count` parameter to `get_next_player_with_direction/3` in lib/kadi/card_games.ex (default: 1)
- [x] T017 [US1] Implement modulo arithmetic for wrap-around in `get_next_player_with_direction/4` in lib/kadi/card_games.ex
- [x] T018 [US1] Add Jack detection (`jack_played?` and `jack_count`) in `execute_play/3` in lib/kadi/card_games.ex
- [x] T019 [US1] Update next player calculation to use `skip_count` in `execute_play/3` in lib/kadi/card_games.ex

### Telemetry Integration

- [x] T020 [P] [US1] Add telemetry event `[:kadi, :jack, :skip_executed]` emission in lib/kadi/card_games.ex
- [x] T021 [P] [US1] Create helper function `emit_jack_skip_event/5` in lib/kadi/card_games.ex

### Integration Tests

- [x] T022 [US1] Add test: single Jack skips 1 player in 3-player game in test/kadi/card_games_test.exs
- [x] T023 [US1] Add test: single Jack skips 1 player in 4-player game in test/kadi/card_games_test.exs
- [x] T024 [US1] Add test: telemetry event emitted with correct metadata in test/kadi/card_games_test.exs

### Verification

- [x] T025 [US1] Run integration tests: `mix test test/kadi/card_games_test.exs`
- [ ] T026 [US1] Manual test: Start 3-player game via `mix phx.server`, play Jack, verify skip in UI

**Checkpoint**: User Story 1 complete - single Jack skip functionality working end-to-end

---

## Phase 4: User Story 2 - Jack Combo Multiplies Skip Count (Priority: P2) ✅

**Goal**: Allow playing multiple Jacks with skip count = number of Jacks

**Independent Test**: Setup 3-player game, play 2 Jacks, verify turn skips 2 players (wraps to same player)

**Estimated Time**: 1-1.5 hours

### Combo Logic Enhancement

- [x] T027 [US2] Verify `jack_count` calculation handles combos in `execute_play/3` in lib/kadi/card_games.ex
- [x] T028 [US2] Test wrap-around math with skip_count > player_count in lib/kadi/card_games.ex

### Integration Tests

- [x] T029 [P] [US2] Add test: 2 Jacks skip 2 players in 3-player game in test/kadi/card_games_test.exs
- [x] T030 [P] [US2] Add test: 3 Jacks skip 3 players in 5-player game in test/kadi/card_games_test.exs
- [x] T031 [P] [US2] Add test: 4 Jacks in 4-player game advances to next player (full cycle wrap) in test/kadi/card_games_test.exs
- [x] T032 [P] [US2] Add test: 4 Jacks in 3-player game wraps correctly (skip through full cycle) in test/kadi/card_games_test.exs

### Verification

- [x] T033 [US2] Run combo tests: `mix test test/kadi/card_games_test.exs --only jack_combo` (4 tests, 0 failures)
- [ ] T034 [US2] Manual test: Play 2-Jack combo via UI, verify double skip

**Checkpoint**: User Story 2 complete - Jack combos multiply skip count correctly ✅

---

## Phase 5: User Story 3 - Jack Follows Standard Matching Rules (Priority: P1)

**Goal**: Ensure Jacks can only be played when matching top card by suit or rank

**Independent Test**: Attempt to play non-matching Jack and verify rejection

**Estimated Time**: 30-45 minutes

### Validation Verification

- [x] T035 [US3] Verify `valid_jack_play?/2` enforces suit/rank matching (completed in Phase 2)
- [x] T036 [US3] Verify `valid_play?/2` routes Jack validation correctly (completed in Phase 2)

### Integration Tests

- [x] T037 [P] [US3] Add test: Jack matching by suit is accepted in test/kadi/card_games_test.exs
- [x] T038 [P] [US3] Add test: Jack matching by rank is accepted in test/kadi/card_games_test.exs
- [x] T039 [P] [US3] Add test: Jack not matching suit or rank is rejected in test/kadi/card_games_test.exs

### Verification

- [x] T040 [US3] Run matching validation tests: `mix test test/kadi/card_games_test.exs`

**Checkpoint**: User Story 3 complete - Jack validation enforces matching rules

---

## Phase 6: User Story 4 - Jack Combo Validation (Priority: P2)

**Goal**: Validate Jack combos require all cards to be Jacks, first must match top card

**Independent Test**: Attempt various combo scenarios and verify proper validation

**Estimated Time**: 45 minutes - 1 hour

### Combo Validation Tests

- [x] T041 [P] [US4] Add test: combo with all Jacks, first matches top card - accepted in test/kadi/games/play_validator_test.exs
- [x] T042 [P] [US4] Add test: combo with Jack + regular card - rejected in test/kadi/games/play_validator_test.exs
- [x] T043 [P] [US4] Add test: combo where neither Jack matches top card - rejected in test/kadi/games/play_validator_test.exs

### Integration Tests

- [x] T044 [P] [US4] Add test: play 2-Jack combo matching by suit in test/kadi/card_games_test.exs
- [x] T045 [P] [US4] Add test: play 3-Jack combo matching by rank in test/kadi/card_games_test.exs

### Verification

- [x] T046 [US4] Run combo validation tests: `mix test test/kadi/games/play_validator_test.exs test/kadi/card_games_test.exs`

**Checkpoint**: User Story 4 complete - Jack combo validation works correctly

---

## Phase 7: User Story 5 - Jack as Last Card Creates Cardless State (Priority: P1)

**Goal**: Playing Jack(s) as last card(s) transitions player to cardless (not winning)

**Independent Test**: Setup player with only Jack(s), play them, verify cardless state entry

**Estimated Time**: 1-1.5 hours

### Cardless State Implementation

- [x] T047 [US5] Update `will_be_cardless` condition to include `jack_played?` in `execute_play/3` in lib/kadi/card_games.ex
- [x] T048 [US5] Add telemetry event `[:kadi, :jack, :cardless_entered]` emission in lib/kadi/card_games.ex
- [x] T049 [US5] Verify cardless player excluded from skip count calculation in lib/kadi/card_games.ex

### Integration Tests

- [x] T050 [P] [US5] Add test: playing single Jack as last card enters cardless state in test/kadi/card_games_test.exs
- [x] T051 [P] [US5] Add test: playing 2 Jacks as last cards enters cardless state in test/kadi/card_games_test.exs
- [x] T052 [P] [US5] Add test: cardless player (from Jack) draws 1 card when turn returns in test/kadi/card_games_test.exs
- [x] T053 [P] [US5] Add test: cardless telemetry event emitted with correct metadata in test/kadi/card_games_test.exs
- [x] T054 [P] [US5] Add test: turn skips N other players from cardless player's position in test/kadi/card_games_test.exs

### Verification

- [x] T055 [US5] Run cardless state tests: `mix test test/kadi/card_games_test.exs`
- [ ] T056 [US5] Manual test: Play Jack as last card via UI, verify cardless indicator appears

**Checkpoint**: User Story 5 complete - Jack cardless behavior working correctly ✅

---

## Phase 8: Edge Cases & Direction Integration

**Goal**: Handle special scenarios and direction interaction with King cards

**Estimated Time**: 1-1.5 hours

### Edge Case Implementation

- [x] T057 [P] Add test: 2-player game, Jack returns to same player in test/kadi/card_games_test.exs
- [x] T058 [P] Add test: Jack after King respects counter-clockwise direction in test/kadi/card_games_test.exs
- [x] T059 [P] Add test: King after Jack preserves skip logic in test/kadi/card_games_test.exs
- [x] T060 [P] Add test: Jack excluded from starting cards (like other special cards) in test/kadi/card_games_test.exs
- [x] T061 [P] Add test: 4 Jacks in 3-player game multi-wrap scenario in test/kadi/card_games_test.exs

### Starting Card Logic

- [x] T062 Update `select_start_card/1` to exclude "jack" from valid starting cards in lib/kadi/card_games.ex (ALREADY DONE: line 1023)
- [x] T063 Verify "jack" added to excluded start cards list (special_ranks) in lib/kadi/card_games.ex (VERIFIED: line 1023)

### Verification

- [x] T064 Run edge case tests: `mix test test/kadi/card_games_test.exs`
- [ ] T065 Manual test: Trigger wrap-around scenarios via UI

**Checkpoint**: All edge cases handled correctly

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, documentation, final verification

**Estimated Time**: 45 minutes - 1 hour

### Code Quality

- [x] T066 [P] Run formatter: `mix format`
- [x] T067 [P] Verify no compilation warnings: `mix compile --warnings-as-errors`
- [x] T068 [P] Run full test suite: `mix test`
- [x] T069 [P] Verify test coverage for Jack-specific logic

### Documentation

- [x] T070 [P] Review and update module docs for `CardGames` in lib/kadi/card_games.ex
- [x] T071 [P] Review and update module docs for `PlayValidator` in lib/kadi/games/play_validator.ex
- [x] T072 [P] Create feature documentation in docs/jack-card-feature.md
- [x] T073 Update README.md with brief Jack card summary and link to docs/jack-card-feature.md

### Final Verification

- [ ] T074 Run quickstart.md verification checklist from specs/007-jack-card/quickstart.md
- [ ] T075 Manual end-to-end test: Play through full game using Jacks in various scenarios
- [ ] T076 Verify no regressions in existing card functionality (King, regular cards)
- [ ] T077 Check telemetry events visible in logs during manual testing

**Checkpoint**: Feature complete and ready for PR

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-7)**: All depend on Foundational phase completion
  - US1 (Phase 3): Single Jack skip - FOUNDATIONAL for US2
  - US2 (Phase 4): Jack combo - Depends on US1 skip logic
  - US3 (Phase 5): Matching rules - Independent, can run after Phase 2
  - US4 (Phase 6): Combo validation - Independent, can run after Phase 2
  - US5 (Phase 7): Cardless state - Depends on US1 skip logic
- **Edge Cases (Phase 8)**: Depends on US1, US2, US5
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1 - Single Jack Skip)**: Can start after Phase 2 - No dependencies on other stories
- **US2 (P2 - Jack Combo)**: Can start after US1 - Builds on skip calculation
- **US3 (P1 - Matching Rules)**: Can start after Phase 2 - Independent (validation only)
- **US4 (P2 - Combo Validation)**: Can start after Phase 2 - Independent (validation only)
- **US5 (P1 - Cardless State)**: Can start after US1 - Uses skip logic for turn advancement

### Suggested Execution Order

**Sequential (Single Developer)**:
1. Phase 1: Setup (15-30 min)
2. Phase 2: Foundational (1-1.5 hours) - MUST complete before proceeding
3. Phase 3: US1 Single Jack skip (1.5-2 hours) - Core mechanic
4. Phase 5: US3 Matching rules (30-45 min) - Quick validation check
5. Phase 7: US5 Cardless state (1-1.5 hours) - Critical P1 feature
6. Phase 4: US2 Jack combo (1-1.5 hours) - Extends US1
7. Phase 6: US4 Combo validation (45 min-1 hour) - Extends US3
8. Phase 8: Edge cases (1-1.5 hours) - Integration testing
9. Phase 9: Polish (45 min-1 hour) - Final verification

**Parallel (Multiple Developers)**:
- After Phase 2 completes:
  - **Track A**: US1 → US2 → US5 (skip logic + cardless)
  - **Track B**: US3 → US4 (validation only)
- After both tracks complete: Phase 8 (edge cases)
- Final: Phase 9 (polish)

### MVP Scope

**Minimum Viable Product (MVP)**: Phases 1-3 + Phase 5 (US1 + US3)
- Basic single Jack skip functionality
- Proper validation (matching rules)
- Can be released as "Jack card (single play only)"
- Estimated time: 3-4 hours

**Full Feature**: All phases
- MVP + combos + cardless + edge cases
- Estimated time: 5.5-7.5 hours

### Parallel Opportunities

- **Phase 1**: Tasks T003, T004, T005 can run in parallel
- **Phase 2**: 
  - Validation functions (T006, T007, T008) can run in parallel
  - All validation tests (T009-T013) can run in parallel after functions complete
- **Phase 3**: Telemetry tasks (T020, T021) can run in parallel with core logic
- **Phase 4-8**: All tests within each phase can run in parallel
- **Phase 9**: Most polish tasks (T066-T073) can run in parallel

---

## Task Summary

- **Total Tasks**: 77
- **Setup Tasks**: 5
- **Foundational Tasks**: 10
- **User Story 1 Tasks**: 11
- **User Story 2 Tasks**: 8
- **User Story 3 Tasks**: 6
- **User Story 4 Tasks**: 6
- **User Story 5 Tasks**: 10
- **Edge Cases Tasks**: 9
- **Polish Tasks**: 12

**Parallel Tasks**: 47 tasks marked [P] can run in parallel within their phase

**Estimated Total Time**: 5.5-7.5 hours (sequential execution)

**MVP Time**: 3-4 hours (Phases 1-3 + Phase 5 only)

---

## Implementation Strategy

1. **MVP First**: Complete US1 (single Jack skip) and US3 (matching rules) for basic functionality
2. **Incremental Delivery**: Each user story adds independent value:
   - US1: Single Jack works → playable feature
   - US2: Combos work → strategic depth
   - US5: Cardless state → game balance
3. **Test-Driven**: Write tests before implementation for each story
4. **Continuous Verification**: Run tests after each task to catch regressions early
5. **Manual Testing**: Verify UI behavior after each major milestone (US1, US2, US5)

---

## Success Criteria

Feature is complete when all tasks are checked and:

- ✅ All 16 functional requirements (FR-001 through FR-016) implemented
- ✅ All 6 success criteria (SC-001 through SC-006) verified
- ✅ All 5 user stories have passing acceptance tests
- ✅ Edge cases (wrap-around, 2-player, starting card, direction) handled
- ✅ Telemetry events emitting correctly
- ✅ No regressions in existing features (King, regular cards, combos)
- ✅ Code passes all constitution checks (DRY, pattern matching, error handling)
- ✅ Manual UI testing confirms expected behavior
- ✅ Documentation complete (module docs + feature docs)
- ✅ Full test suite passes: `mix test`
