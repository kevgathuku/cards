# Tasks: Randomize Player Card Distribution

**Input**: Design documents from `/specs/002-randomize-player-cards/`
**Prerequisites**: plan.md (complete), spec.md (complete), research.md, data-model.md, quickstart.md

**Tests**: Included - Feature spec requests statistical validation and comprehensive test coverage

**Organization**: Tasks are organized by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1)
- Include exact file paths in descriptions

## Path Conventions

This is a Phoenix/Elixir web application following standard Phoenix conventions:
- **Source**: `lib/kadi/` (context modules and schemas)
- **Tests**: `test/kadi/` (test files mirror source structure)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify existing infrastructure is ready for modifications

**Status**: ✅ No setup required - using existing Phoenix application structure

This feature modifies existing code, so no new project setup is needed. The `order_index` field already exists in the `deck_cards` table from feature 001-deal-start-card.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Verify pre-existing dependencies are in place before implementation

**Status**: ✅ All prerequisites exist from previous features

- ✅ `order_index` field exists in `deck_cards` table (from migration `20250922205611`)
- ✅ `order_index` is already randomized during deck creation (`lib/kadi/card_games.ex:105`)
- ✅ Test infrastructure exists (`test/kadi/card_games_test.exs` with Ecto Sandbox setup)

**Checkpoint**: Foundation verified - user story implementation can begin

---

## Phase 3: User Story 1 - Randomized Card Distribution (Priority: P1) 🎯 MVP

**Goal**: Ensure cards are dealt to players in randomized `order_index` sequence to prevent sequential patterns (e.g., 4,5,6,7 of hearts) in any player's hand.

**Independent Test**: Start multiple games and verify that player hands do not contain 3+ consecutive ranks of the same suit across a statistically significant sample (100 game starts, <5% occurrence threshold).

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T001 [P] [US1] Add test helper function `has_sequential_pattern?/1` in `test/kadi/card_games_test.exs` to detect 3+ consecutive ranks of same suit
- [X] T002 [P] [US1] Add test helper function `rank_to_number/1` in `test/kadi/card_games_test.exs` to convert card ranks to numeric values for sequence detection
- [X] T003 [P] [US1] Add test helper function `has_consecutive_sequence?/2` in `test/kadi/card_games_test.exs` to identify consecutive number sequences
- [X] T004 [US1] Add test "deals cards in order_index sequence" in `test/kadi/card_games_test.exs` to verify dealing respects order_index ordering
- [X] T005 [US1] Add test "distributes cards according to randomized order_index" in `test/kadi/card_games_test.exs` to verify non-deterministic distribution across multiple games
- [X] T006 [US1] Add statistical test "no sequential patterns across 100 game starts" in `test/kadi/card_games_test.exs` to verify <5% sequential pattern occurrence

### Implementation for User Story 1

- [X] T007 [US1] Modify `deal_cards/2` function in `lib/kadi/card_games.ex` to sort deck cards by `order_index` before splitting (add `|> Enum.sort_by(& &1.order_index)` after line 195)
- [X] T008 [US1] Add inline comment in `lib/kadi/card_games.ex` explaining sorting rationale: "Sort by randomized order_index to ensure non-sequential distribution"

### Validation for User Story 1

- [X] T009 [US1] Run all tests in `test/kadi/card_games_test.exs` and verify new tests pass with implementation
- [X] T010 [US1] Run full test suite with `mix test` to ensure no regressions in existing functionality
- [ ] T011 [US1] Manually verify card distribution by starting a game in IEx and inspecting player hands (optional validation per quickstart.md)

**Checkpoint**: At this point, User Story 1 should be fully functional. Cards are dealt in randomized order, and statistical tests confirm no sequential patterns.

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and documentation updates

- [X] T012 [P] Review and update CLAUDE.md if card dealing behavior needs documentation (agent context already updated by `/speckit.plan`)
- [X] T013 [P] Verify performance: Game initialization completes within 2-second budget (run `mix test` and check timing)
- [X] T014 Run quickstart.md validation steps to confirm implementation matches guide

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: ✅ Verified - No action required
- **Foundational (Phase 2)**: ✅ Verified - Pre-existing infrastructure confirmed
- **User Story 1 (Phase 3)**: Can start immediately - All dependencies satisfied
- **Polish (Phase 4)**: Depends on User Story 1 completion

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies on other stories - Can start immediately after verification

### Within User Story 1

**Test-First Approach**:
1. **T001-T003** (Test helpers) - Can run in parallel [P]
2. **T004-T006** (Test cases) - Sequential, depend on helpers (T001-T003)
3. **T007-T008** (Implementation) - After tests fail
4. **T009-T011** (Validation) - After implementation, sequential

**Execution Flow**:
```
T001, T002, T003 (parallel test helpers)
  ↓
T004 (test: order_index sequence)
  ↓
T005 (test: randomized distribution)
  ↓
T006 (test: statistical validation)
  ↓
T007 (modify deal_cards/2 - CORE CHANGE)
  ↓
T008 (add comment)
  ↓
T009 (run card_games tests)
  ↓
T010 (run full test suite)
  ↓
T011 (manual IEx verification - optional)
```

### Parallel Opportunities

**Within User Story 1**:
- **T001, T002, T003**: All test helper functions can be written in parallel (different function definitions)
- **T012, T013, T014**: All polish tasks can run in parallel (different files/concerns)

**Example Parallel Execution for Test Helpers**:
```bash
# Launch all test helper functions together:
Task: "Add test helper function has_sequential_pattern?/1 in test/kadi/card_games_test.exs"
Task: "Add test helper function rank_to_number/1 in test/kadi/card_games_test.exs"
Task: "Add test helper function has_consecutive_sequence?/2 in test/kadi/card_games_test.exs"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

This feature has only ONE user story, so the entire feature is the MVP:

1. ✅ Verify Phase 1 & 2 (Setup + Foundational)
2. Write tests (T001-T006) - Tests should FAIL
3. Implement sorting (T007-T008) - Single line change
4. Validate (T009-T011) - Tests should now PASS
5. Polish (T012-T014) - Final verification
6. **STOP and VALIDATE**: Run full test suite and verify all tests pass
7. Ready for commit and merge

### Critical Path

The **critical path** through this feature is extremely short:

```
Prerequisites Verified → Write Tests → Add Sort Line → Validate Tests Pass
```

**Core Implementation**: Single line addition in `lib/kadi/card_games.ex:196`
```elixir
cards_in_deck =
  deck_cards
  |> Enum.filter(&(&1.location_type == "deck"))
  |> Enum.sort_by(& &1.order_index)  # ← NEW LINE
```

**Estimated Effort**: 1-2 hours total (including comprehensive test writing and validation)

---

## Task Details

### Core Implementation Task (T007)

**File**: `lib/kadi/card_games.ex`
**Function**: `deal_cards/2` (private function, currently lines 194-221)
**Change Type**: Behavior modification (add sorting)

**Current Code** (line 195):
```elixir
cards_in_deck = Enum.filter(deck_cards, &(&1.location_type == "deck"))
```

**New Code** (lines 195-197):
```elixir
cards_in_deck =
  deck_cards
  |> Enum.filter(&(&1.location_type == "deck"))
  |> Enum.sort_by(& &1.order_index)
```

**Rationale**: The `order_index` values are already randomized during deck creation (line 105: `Enum.shuffle(1..52)`). This change ensures card dealing respects that pre-randomized order instead of relying on undefined database insertion/preload order.

### Test Implementation Tasks (T001-T006)

**File**: `test/kadi/card_games_test.exs`
**Location**: Add new `describe` block: `"deal_cards/2 with order_index"`

**Test Strategy**:
1. **Helper functions** (T001-T003): Utility functions to detect sequential card patterns
2. **Order verification** (T004): Confirm dealing follows `order_index` sequence
3. **Randomization verification** (T005): Confirm distribution varies across games
4. **Statistical validation** (T006): 100-game sample with <5% sequential pattern threshold

**Expected Test Output** (before T007 implementation):
- T004-T006: **FAIL** (cards not sorted by `order_index`)

**Expected Test Output** (after T007 implementation):
- T004-T006: **PASS** (cards sorted, no sequential patterns)

---

## Success Criteria Mapping

Mapping spec Success Criteria to tasks:

- **SC-001**: "100% of games have no 3+ consecutive rank sequences in same suit"
  - ✅ **Covered by**: T006 (statistical test validates <5% occurrence across 100 games)

- **SC-002**: "Statistical analysis shows random distribution"
  - ✅ **Covered by**: T005 + T006 (randomization test + statistical validation)

- **SC-003**: "Players cannot predict hand composition"
  - ✅ **Covered by**: T007 (sorting by randomized `order_index` ensures unpredictability)

- **SC-004**: "Card dealing within 2-second constraint"
  - ✅ **Covered by**: T013 (performance verification in Polish phase)

---

## Risk Mitigation

### Risk: `order_index` nil values

**Probability**: Very Low (DB constraint prevents)
**Mitigation**: T004 test will catch any nil values (sort would crash)

### Risk: Test flakiness (statistical test)

**Probability**: Low
**Mitigation**: T006 uses generous 5% threshold (well above expected ~0% with proper randomization)

### Risk: Performance regression

**Probability**: Very Low
**Mitigation**: T013 validates timing; research shows <1ms overhead

---

## Notes

- **[P] tasks** = Different file sections, no dependencies, can run in parallel
- **[US1] label** = All tasks map to User Story 1 (only story in this feature)
- **Test-first approach**: Tests must FAIL before implementation (T004-T006 fail → T007 fixes → T009-T010 pass)
- **Minimal change**: Core implementation is literally ONE line addition
- **No new files**: All changes in existing `lib/kadi/card_games.ex` and `test/kadi/card_games_test.exs`
- **No schema changes**: Uses existing `order_index` field from feature 001
- **No API changes**: Internal behavior modification only

---

## Total Task Count

- **Phase 1 (Setup)**: 0 tasks (verified, no action required)
- **Phase 2 (Foundational)**: 0 tasks (verified, no action required)
- **Phase 3 (User Story 1)**: 11 tasks
  - Tests: 6 tasks (T001-T006)
  - Implementation: 2 tasks (T007-T008)
  - Validation: 3 tasks (T009-T011)
- **Phase 4 (Polish)**: 3 tasks (T012-T014)

**TOTAL**: 14 tasks

**Parallel Opportunities**: 5 tasks can run in parallel (T001-T003 test helpers, T012-T014 polish tasks)

**Critical Path Tasks**: 2 tasks (T007 core implementation + T008 comment)

**Estimated Total Time**: 1-2 hours

---

## Ready to Implement

✅ All prerequisites verified
✅ Test strategy defined
✅ Implementation path clear (single line change)
✅ Validation criteria established
✅ Success criteria mapped to tasks

**Next Step**: Begin Phase 3, Task T001 (test helper functions) or run `/speckit.implement` for guided execution
