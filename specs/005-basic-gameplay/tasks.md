# Tasks: Basic Gameplay - Regular Cards

**Input**: Design documents from `/specs/005-basic-gameplay/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Tests are included as this is a core gameplay feature requiring high reliability.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Elixir/Phoenix project**: `lib/`, `test/` at repository root
- Migrations: `priv/repo/migrations/`
- LiveView files: `lib/kadi_web/live/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database schema setup for basic gameplay

- [X] T001 Create migration to add top_card_id to game_sessions in priv/repo/migrations/XXXXXX_add_top_card_to_game_sessions.exs
- [X] T002 Update GameSession schema to include belongs_to :top_card in lib/kadi/games/game_session.ex
- [X] T003 Update GameSession changeset to include top_card_id in cast and assoc_constraint in lib/kadi/games/game_session.ex
- [X] T004 Run migration with mix ecto.migrate and verify existing tests pass
- [X] T004a Update start_game to set top_card_id when game starts in lib/kadi/card_games.ex
- [X] T004b Simplify get_top_card/1 to remove fallback logic (no longer needed) in lib/kadi/card_games.ex
- [X] T004c Add test to verify top_card_id is set on game start in test/kadi/card_games_test.exs

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core validation logic and turn helpers that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create PlayValidator module with valid_play?/2 function in lib/kadi/games/play_validator.ex
- [X] T006 [P] Implement validate_single_card/2 private function in lib/kadi/games/play_validator.ex
- [X] T007 [P] Implement validate_combo/2 private function in lib/kadi/games/play_validator.ex
- [X] T008 [P] Implement matches_suit_or_rank?/2 helper in lib/kadi/games/play_validator.ex
- [X] T009 [P] Implement same_rank?/1 helper in lib/kadi/games/play_validator.ex
- [X] T010 [P] Implement first_card_matches?/2 helper in lib/kadi/games/play_validator.ex
- [X] T011 [P] Implement player_has_cards?/2 function in lib/kadi/games/play_validator.ex
- [X] T012 Add turn helper functions (get_game_session_players/1, get_next_player/2, validate_current_turn/2) to lib/kadi/card_games.ex

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Play Single Matching Card (Priority: P1) 🎯 MVP

**Goal**: Player can play a single card that matches suit or rank of the top card

**Independent Test**: Set up game with known top card (5H), player with matching card (5D or 7H), execute play, verify card moved from hand to stack and turn advanced

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T013 [P] [US1] Test accepts card matching suit in test/kadi/games/play_validator_test.exs
- [X] T014 [P] [US1] Test accepts card matching rank in test/kadi/games/play_validator_test.exs
- [X] T015 [P] [US1] Test rejects card matching neither suit nor rank in test/kadi/games/play_validator_test.exs

### Implementation for User Story 1

- [X] T016 [US1] Implement get_game_session_preloaded/1 helper in lib/kadi/card_games.ex
- [X] T017 [P] [US1] Implement validate_can_play/2 helper in lib/kadi/card_games.ex
- [X] T018 [P] [US1] Implement get_player_in_session/2 helper in lib/kadi/card_games.ex
- [X] T019 [P] [US1] Implement validate_player_has_cards/2 helper in lib/kadi/card_games.ex
- [X] T020 [P] [US1] Implement get_top_card/1 helper in lib/kadi/card_games.ex
- [X] T021 [P] [US1] Implement get_max_played_stack_order/1 helper in lib/kadi/card_games.ex
- [X] T022 [P] [US1] Implement find_player_deck_card/3 helper in lib/kadi/card_games.ex
- [X] T023 [US1] Implement execute_play/3 with Ecto.Multi for atomic state updates in lib/kadi/card_games.ex
- [X] T024 [US1] Implement play_cards/3 main function with validation pipeline in lib/kadi/card_games.ex
- [X] T025 [US1] Implement broadcast_game_update/1 helper for PubSub in lib/kadi/card_games.ex
- [X] T026 [US1] Add play_cards/3 integration tests in test/kadi/card_games_test.exs

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Play Multiple Matching Cards (Priority: P2)

**Goal**: Player can play combo of cards with same rank where first card matches top card

**Independent Test**: Set up game with known top card (5H), player with multiple same-rank cards (4H, 4D), execute combo play, verify all cards moved in correct order and turn advanced

### Tests for User Story 2

- [X] T027 [P] [US2] Test accepts combo with same rank and one match in test/kadi/games/play_validator_test.exs
- [X] T028 [P] [US2] Test rejects combo with different ranks in test/kadi/games/play_validator_test.exs
- [X] T029 [P] [US2] Test rejects combo where no card matches in test/kadi/games/play_validator_test.exs

### Implementation for User Story 2

- [X] T030 [US2] Extend execute_play/3 to handle multiple cards with Enum.with_index for order_index assignment in lib/kadi/card_games.ex
- [X] T031 [US2] Update play_cards/3 to handle card ID lists (already supports from US1, verify works for combos) in lib/kadi/card_games.ex
- [X] T032 [US2] Add combo play integration tests (2-card and 3-card combos) in test/kadi/card_games_test.exs

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Invalid Play Rejection (Priority: P1)

**Goal**: System rejects invalid plays with clear feedback and maintains game state

**Independent Test**: Attempt various invalid plays (wrong suit/rank, mixed numbers) and verify rejection with appropriate error codes

### Tests for User Story 3

- [X] T033 [P] [US3] Test rejects play when not player's turn in test/kadi/card_games_test.exs
- [X] T034 [P] [US3] Test rejects play when player doesn't have cards in hand in test/kadi/card_games_test.exs
- [X] T035 [P] [US3] Test rejects invalid single card (no match) in test/kadi/card_games_test.exs
- [X] T036 [P] [US3] Test rejects invalid combo (mixed ranks) in test/kadi/card_games_test.exs

### Implementation for User Story 3

- [X] T037 [US3] Verify all validation paths in play_cards/3 return appropriate error tuples in lib/kadi/card_games.ex
- [X] T038 [US3] Document error codes (:not_your_turn, :cards_not_in_hand, :no_match, :different_ranks) in lib/kadi/card_games.ex
- [X] T039 [US3] Add edge case tests (empty card list, nil top_card, player not in game) in test/kadi/card_games_test.exs

**Checkpoint**: All validation rules should be tested and working

---

## Phase 6: User Story 4 - Draw Card When No Valid Play (Priority: P1)

**Goal**: Player can draw card from deck when no valid play exists, turn advances, automatic deck recycling when empty

**Independent Test**: Set up player with no matching cards, execute draw, verify card added to hand and turn advanced

### Tests for User Story 4

- [X] T040 [US4] REMOVED DUPLICATE - draw adds card to player's hand (already tested in feature 003 line 453)
- [X] T041 [US4] REMOVED DUPLICATE - draw advances turn to next player (already tested in feature 003 line 476)
- [X] T042 [US4] REMOVED DUPLICATE - draw with empty deck triggers recycle (already tested in feature 004 line 826)
- [X] T043 [US4] Test drawn card cannot be played immediately (gameplay-specific) in test/kadi/card_games_test.exs

### Implementation for User Story 4

- [X] T044 [US4] Use existing draw_card_from_deck/2 directly (no wrapper needed) in lib/kadi/card_games.ex
- [X] T045 [US4] Verify draw_card_from_deck/2 includes turn validation and turn advancement in lib/kadi/card_games.ex
- [X] T046 [US4] Verify automatic deck recycling integration with recycle_played_stack/1 (feature 004) in lib/kadi/card_games.ex
- [X] T047 [US4] REMOVED DUPLICATE - full draw flow integration test (redundant with existing tests)

**Checkpoint**: Draw functionality should work independently with automatic deck management

---

## Phase 7: LiveView Integration

**Purpose**: Connect backend gameplay logic to frontend UI

### Card Selection UI

- [X] T048 [P] Add card_hand component with click handlers in lib/kadi_web/live/game_live/show.html.heex
- [X] T049 [P] Implement handle_event("select_card", ...) for card selection toggling in lib/kadi_web/live/game_live/show.ex
- [X] T050 [P] Add selected_cards to socket assigns in lib/kadi_web/live/game_live/show.ex

### Play Cards Handler

- [X] T051 Implement handle_event("play_cards", ...) calling CardGames.play_cards/3 in lib/kadi_web/live/game_live/show.ex
- [X] T052 Add error handling with flash messages for all error codes in lib/kadi_web/live/game_live/show.ex
- [X] T053 Clear selected_cards on successful play or error in lib/kadi_web/live/game_live/show.ex

### Draw Card Handler

- [X] T054 [P] Implement handle_event("draw_card", ...) calling CardGames.draw_card/2 in lib/kadi_web/live/game_live/show.ex
- [X] T055 [P] Add "Draw Card" button visible only when player's turn in lib/kadi_web/live/game_live/show.html.heex

### Real-Time Updates

- [X] T056 Implement handle_info({:game_updated, ...}) for PubSub broadcasts in lib/kadi_web/live/game_live/show.ex
- [X] T057 Subscribe to game:#{id} PubSub topic in mount callback in lib/kadi_web/live/game_live/show.ex
- [X] T058 Auto-clear selected_cards when turn changes to another player in lib/kadi_web/live/game_live/show.ex

### UI Elements

- [X] T059 [P] Add play/draw button visibility logic (hide when not player's turn) in lib/kadi_web/live/game_live/show.html.heex
- [X] T060 [P] Display current turn indicator in lib/kadi_web/live/game_live/show.html.heex
- [X] T061 [P] Display top card on played stack in lib/kadi_web/live/game_live/show.html.heex
- [X] T062 [P] Display player hand with selection state in lib/kadi_web/live/game_live/show.html.heex

---

## Phase 8: LiveView Testing

**Purpose**: Verify end-to-end gameplay through LiveView

- [ ] T063 [P] Test card selection UI in test/kadi_web/live/game_live/show_test.exs
- [ ] T064 [P] Test play cards event updates game state in test/kadi_web/live/game_live/show_test.exs
- [ ] T065 [P] Test draw card event updates game state in test/kadi_web/live/game_live/show_test.exs
- [ ] T066 [P] Test invalid play shows error flash in test/kadi_web/live/game_live/show_test.exs
- [ ] T067 [P] Test turn validation prevents out-of-turn plays in test/kadi_web/live/game_live/show_test.exs
- [ ] T068 [P] Test PubSub broadcasts update all connected players in test/kadi_web/live/game_live/show_test.exs
- [ ] T069 [P] Test selection cleared when turn changes in test/kadi_web/live/game_live/show_test.exs
- [ ] T070 Test full gameplay round (all players play once) in test/kadi_web/live/game_live/show_test.exs

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T071 [P] Add logging for play_cards/3 operations (info level for success, warning for invalid) in lib/kadi/card_games.ex
- [ ] T072 [P] Add telemetry events for play validation duration in lib/kadi/card_games.ex
- [ ] T073 [P] Verify performance target <100ms for play validation with benchmarking
- [ ] T074 [P] Add database indexes for deck_cards location queries if not present in priv/repo/migrations/
- [ ] T075 Code review for security (turn validation, hand ownership, atomic transactions) across lib/kadi/card_games.ex
- [ ] T076 Run full test suite with mix test and verify >90% coverage
- [ ] T077 Manual testing with 2-4 players in live game session
- [ ] T078 Verify top_card_id consistency with played stack in all flows
- [ ] T079 Run quickstart.md validation for all phases
- [ ] T080 Update CLAUDE.md if any architectural patterns changed

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 stories first: US1, US3, US4, then US2)
- **LiveView Integration (Phase 7-8)**: Depends on all P1 user stories (US1, US3, US4) being complete
- **Polish (Phase 9)**: Depends on all phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Extends US1 but independently testable
- **User Story 3 (P1)**: Can start after Foundational (Phase 2) - Validates US1/US2, independently testable
- **User Story 4 (P1)**: Can start after Foundational (Phase 2) - Uses existing feature 003, independently testable

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Helpers before main functions
- Validation before state updates
- Core logic before LiveView integration
- Story complete before moving to next priority

### Parallel Opportunities

- Phase 1: All tasks are sequential (migration must complete before schema updates)
- Phase 2: Tasks T006-T011 can run in parallel (different validation functions)
- Phase 3: Tests T013-T015 can run in parallel, helpers T017-T022 can run in parallel
- Phase 4: Tests T027-T029 can run in parallel
- Phase 5: Tests T033-T036 can run in parallel
- Phase 6: Tests T040-T043 can run in parallel
- Phase 7: Card Selection (T048-T050) can run parallel to Draw Handler (T054-T055), UI Elements (T059-T062) can run in parallel
- Phase 8: All tests can run in parallel except T070 (full round test)
- Phase 9: All polish tasks can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Test accepts card matching suit in test/kadi/games/play_validator_test.exs"
Task: "Test accepts card matching rank in test/kadi/games/play_validator_test.exs"
Task: "Test rejects card matching neither suit nor rank in test/kadi/games/play_validator_test.exs"

# Launch all helper functions for User Story 1 together:
Task: "Implement validate_can_play/2 helper in lib/kadi/card_games.ex"
Task: "Implement get_player_in_session/2 helper in lib/kadi/card_games.ex"
Task: "Implement validate_player_has_cards/2 helper in lib/kadi/card_games.ex"
Task: "Implement get_top_card/1 helper in lib/kadi/card_games.ex"
Task: "Implement get_max_played_stack_order/1 helper in lib/kadi/card_games.ex"
Task: "Implement find_player_deck_card/3 helper in lib/kadi/card_games.ex"
```

---

## Implementation Strategy

### MVP First (User Stories 1, 3, 4 - All P1)

1. Complete Phase 1: Setup (database schema)
2. Complete Phase 2: Foundational (CRITICAL - validation and turn logic)
3. Complete Phase 3: User Story 1 (single card play)
4. Complete Phase 5: User Story 3 (validation)
5. Complete Phase 6: User Story 4 (draw card)
6. Complete Phase 7-8: LiveView Integration and Testing
7. **STOP and VALIDATE**: Test all P1 stories independently
8. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Basic play works
3. Add User Story 3 → Test independently → Validation works
4. Add User Story 4 → Test independently → Draw works (MVP!)
5. Add User Story 2 → Test independently → Combo plays work (Enhancement)
6. Add LiveView → Test end-to-end → Full UI works
7. Polish → Performance and reliability hardening

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (single play)
   - Developer B: User Story 3 (validation)
   - Developer C: User Story 4 (draw)
3. Developer D (or A after US1): User Story 2 (combo play)
4. Once backend complete: Team splits on LiveView components
5. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing (TDD approach)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Feature 003 (draw_card_from_deck/2) and Feature 004 (recycle_played_stack/1) are reused - no reimplementation
- top_card_id maintained atomically in all play transactions
- All validation server-side only (Constitution security requirement)
- Performance target: <100ms for play validation and state updates
- Tests are included as this is core gameplay requiring high reliability
