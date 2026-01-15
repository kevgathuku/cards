# Implementation Plan: Question Cards (Q and 8)

## Overview

This implementation plan breaks down the question card feature into discrete, manageable coding tasks. Each task builds incrementally on previous work, ensuring the feature is integrated properly with existing game mechanics.

---

## Task List

- [x] 1. Update PlayValidator for question card detection
  - Add helper functions to detect Q and 8 cards
  - Add function to split question cards from answer cards in a combo
  - Add validation for question card sequences (matching by suit or rank)
  - Add validation for answer cards matching last question card
  - _Requirements: 1.1, 1.2, 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3_

- [x] 1.1 Add question card detection helpers
  - Implement `all_queens?/1` to check if all cards are Q
  - Implement `all_eights?/1` to check if all cards are 8
  - Implement `all_question_cards?/1` to check if all cards are Q or 8
  - Implement `is_question_card?/1` to check if a single card is Q or 8
  - _Requirements: 1.1, 1.2_

- [x] 1.2 Add combo splitting logic
  - Implement `split_question_and_answer/1` to separate question cards from answer cards
  - Function should iterate through cards and split at first non-question card
  - Return tuple `{question_cards, answer_cards}`
  - Handle edge case where all cards are questions (empty answer list)
  - _Requirements: 1.1, 1.2, 3.5, 4.5_

- [x] 1.3 Add question sequence validation
  - Implement `valid_question_sequence?/1` to validate question cards match each other
  - Check that each subsequent question card matches previous by suit or rank
  - Allow mixed Q and 8 cards (e.g., 8H QH QD 8D)
  - Return true if sequence is valid, false otherwise
  - _Requirements: 4.1, 4.3_

- [x] 1.4 Add answer validation logic
  - Implement `valid_answer_for_question?/2` to validate answer cards
  - Check first answer card matches last question card by suit or rank
  - If multiple answer cards, validate they form a valid combo (same rank)
  - Return true if answer is valid, false otherwise
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 6.2, 6.3, 6.4_

- [x] 1.5 Integrate question validation into valid_play?/3
  - Detect if play contains question cards at the start
  - If yes, use question card validation logic
  - Return appropriate validation result
  - Ensure first question card matches top card by suit or rank
  - _Requirements: 1.1, 1.2, 10.2_

- [x] 2. Add unit tests for PlayValidator question card logic
  - Test question card detection helpers
  - Test combo splitting with various scenarios
  - Test question sequence validation
  - Test answer validation
  - Test integration with valid_play?/3
  - _Requirements: All validation requirements_

- [x] 2.1 Test question card detection
  - Test `all_question_cards?/1` with Q only, 8 only, mixed Q/8, non-questions (tested through `valid_question_sequence?/1`)
  - Test `is_question_card?/1` with Q, 8, and non-question cards (tested through `valid_question_sequence?/1`)
  - Note: `all_queens?/1` and `all_eights?/1` were removed as unused dead code
  - _Requirements: 1.1, 1.2_

- [x] 2.2 Test combo splitting
  - Test splitting `[8H, 8D, 2D]` → `{[8H, 8D], [2D]}`
  - Test splitting `[8H, 8D]` → `{[8H, 8D], []}`
  - Test splitting `[8H, 8D, 4D, 4H]` → `{[8H, 8D], [4D, 4H]}`
  - Test splitting `[8H, QH, 2D]` → `{[8H, QH], [2D]}`
  - Test splitting `[8H, 8D, QD]` → `{[8H, 8D, QD], []}` (Q at end is question)
  - _Requirements: 1.2, 3.5, 4.5, 10.5_

- [x] 2.3 Test question sequence validation
  - Test valid sequence: `[8H, 8D]` (match by rank)
  - Test valid sequence: `[8H, QH]` (match by suit)
  - Test valid sequence: `[8H, QH, QD, 8D]` (mixed, all match)
  - Test invalid sequence: `[8H, QD]` (no match)
  - Test single question card: `[8H]` (always valid)
  - _Requirements: 4.1, 4.3_

- [x] 2.4 Test answer validation
  - Test single answer matching suit: `[2D]` after `[8D]`
  - Test single answer matching rank: `[8H]` after `[8D]` (but 8 is question, so invalid)
  - Test answer combo: `[4D, 4H]` after `[8D]` (first matches suit, same rank)
  - Test invalid answer: `[2H]` after `[8D]` (no match)
  - Test invalid answer combo: `[4D, 5D]` after `[8D]` (different ranks)
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 6.2, 6.3, 6.4_

- [x] 2.5 Test valid_play?/3 with question cards
  - Test complete play: `[8H, 8D, 2D]` on top card `5H` (8H matches suit)
  - Test incomplete play: `[8H, 8D]` on top card `5H` (8H matches suit)
  - Test invalid play: `[8H, 8D, 2H]` on top card `5D` (8H doesn't match)
  - Test question with answer combo: `[8H, 8D, 4D, 4H]` on top card `5H`
  - Test question ending with Q/8: `[8H, 8D, QD]` (all questions)
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 10.1, 10.2, 10.5_

- [x] 3. Update starting card selection to allow Q and 8
  - Modify `select_start_card/1` in CardGames context (line 1370)
  - Remove "8" and "queen" from the special_ranks exclusion list
  - Keep "2", "3", and "jack" in the exclusion list
  - Add test to verify Q and 8 can be selected as starting cards
  - Verify that when Q or 8 is the starting card, it behaves like a regular card (no question effect)
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 4. Add question draw prompt logic to CardGames context
  - Modify `play_cards/3` to detect incomplete question plays
  - Return special result indicating draw is needed
  - Add `answer_question_by_drawing/2` function to draw one card
  - Ensure turn advances after drawing
  - Handle deck exhaustion (recycle played pile)
  - _Requirements: 1.1, 1.2, 1.4, 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 4.1 Modify play_cards/3 for question detection
  - After validation, check if play is incomplete question combo
  - Use `split_question_and_answer/1` to detect
  - If answer list is empty, return `{:ok, :needs_draw, updated_game}`
  - If answer list has cards, execute play normally
  - Move cards to played pile in both cases
  - _Requirements: 1.1, 1.2, 1.4, 1.5_

- [x] 4.2 Implement answer_question_by_drawing/2
  - Create new function `answer_question_by_drawing(game_session, player_id)`
  - Validate it's the player's turn
  - Draw one card from deck to player's hand
  - If deck is empty, recycle played pile first
  - Advance turn to next player
  - Broadcast game update
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 13.5_

- [x] 4.3 Handle deck exhaustion during question draw
  - In `answer_question_by_drawing/2`, check if deck is empty
  - If empty, call `recycle_played_stack/1` before drawing
  - Ensure at least one card remains in played pile (the question card)
  - If recycling fails, handle gracefully (skip player with notification)
  - _Requirements: 2.5, 13.5_

- [ ] 5. Write failing integration tests for question card plays (TDD)
  - **Write tests FIRST before any implementation**
  - Tests should fail initially (no implementation yet)
  - Verify tests fail with expected errors
  - Test complete question play (with answer)
  - Test incomplete question play (without answer)
  - Test drawing as answer to question
  - Test question with special card answers (Ace, Jack, King, 2, 3)
  - Test last card scenarios
  - _Requirements: All requirements_

- [ ] 5.1 Write failing test: complete question play
  - **Write test FIRST - it should fail**
  - Setup: Player has `[8H, 8D, 2D]`, top card is `5H`
  - Test should verify: cards moved to played pile, turn advanced, no draw prompt
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 5.2 Write failing test: incomplete question play
  - **Write test FIRST - it should fail**
  - Setup: Player has `[8H, 8D]`, top card is `5H`
  - Test should verify: cards moved to played pile, turn did NOT advance, draw prompt needed
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 1.1, 1.2, 2.1_

- [ ] 5.3 Write failing test: drawing as answer
  - **Write test FIRST - it should fail**
  - Setup: Player played incomplete question, needs to draw
  - Test should call `answer_question_by_drawing/2` and verify: one card drawn, turn advanced
  - Run test and verify it fails (function doesn't exist yet)
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ] 5.4 Write failing test: question with Ace answer
  - **Write test FIRST - it should fail**
  - Setup: Player has `[8H, 8D, AH]`, top card is `5H`
  - Test should verify: cards moved, suit selection triggered, turn did NOT advance
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 5.1, 13.3_

- [ ] 5.5 Write failing test: question with penalty answer (2 or 3)
  - **Write test FIRST - it should fail**
  - Setup: Player has `[8H, 8D, 2D]`, top card is `5H`
  - Test should verify: cards moved, penalty activated, turn advanced
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 5.2, 5.3, 13.4_

- [ ] 5.6 Write failing test: question with Jack answer
  - **Write test FIRST - it should fail**
  - Setup: Player has `[8H, 8D, JD]`, top card is `5H`
  - Test should verify: cards moved, next player skipped, turn advanced to player after next
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 5.4, 13.1_

- [ ] 5.7 Write failing test: question with King answer
  - **Write test FIRST - it should fail**
  - Setup: Player has `[8H, 8D, KD]`, top card is `5H`
  - Test should verify: cards moved, direction reversed, turn advanced in new direction
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 5.5, 13.2_

- [ ] 5.8 Write failing test: last card as question without answer
  - **Write test FIRST - it should fail**
  - Setup: Player has only `[8H]`, top card is `5H`
  - Test should verify: card moved, player NOT cardless, draw prompt needed, after draw player has 1 card
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 9.1, 9.2, 9.5_

- [ ] 5.9 Write failing test: last cards as question with answer
  - **Write test FIRST - it should fail**
  - Setup: Player has only `[8H, 2H]`, top card is `5H`
  - Test should verify: cards moved, player is cardless, turn advanced
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 9.3, 9.4_

- [ ] 5.10 Write failing test: deck exhaustion during question draw
  - **Write test FIRST - it should fail**
  - Setup: Player needs to draw for question, deck is empty
  - Test should verify: played pile recycled, one card drawn, turn advanced
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 2.5, 13.5_

- [ ] 5.11 Implement code to make integration tests pass
  - **Only after all tests are written and failing**
  - Implement the question card logic in CardGames context
  - Run tests after each change to see progress
  - All tests in task 5 should pass when complete
  - _Requirements: All requirements from tasks 5.1-5.10_

- [ ] 6. Write failing LiveView tests for question draw prompt (TDD)
  - **Write tests FIRST before any LiveView implementation**
  - Tests should fail initially (no implementation yet)
  - Verify tests fail with expected errors
  - Test socket assigns, event handlers, UI elements
  - _Requirements: 2.1, 11.1, 11.2, 11.3, 11.4, 11.5_

- [ ] 6.1 Write failing test: socket assign for question state
  - **Write test FIRST - it should fail**
  - Test should verify `pending_question_draw` is initialized to false in mount
  - Test should verify it resets to false in assign_game_state
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 2.1, 11.1_

- [ ] 6.2 Write failing test: handle needs_draw result in play_cards event
  - **Write test FIRST - it should fail**
  - Test should verify when play_cards returns `:needs_draw`, socket sets `pending_question_draw: true`
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 1.4, 2.1_

- [ ] 6.3 Write failing test: answer_question_draw event handler
  - **Write test FIRST - it should fail**
  - Test should verify clicking answer_question_draw calls CardGames function and clears flag
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 2.2, 2.3, 2.4_

- [ ] 6.4 Write failing test: draw button in UI template
  - **Write test FIRST - it should fail**
  - Test should verify button appears when pending_question_draw is true
  - Test should verify button has correct text and event binding
  - Run test and verify it fails (UI doesn't exist yet)
  - _Requirements: 11.1, 11.3_

- [ ] 6.5 Write failing test: question banner in UI
  - **Write test FIRST - it should fail**
  - Test should verify banner appears with correct message when pending_question_draw is true
  - Run test and verify it fails (UI doesn't exist yet)
  - _Requirements: 11.1, 11.2, 11.5_

- [ ] 6.6 Write failing test: prevent playing cards when draw is pending
  - **Write test FIRST - it should fail**
  - Test should verify playing cards when pending_question_draw is true shows error
  - Run test and verify it fails (implementation doesn't exist yet)
  - _Requirements: 10.3, 10.4_

- [ ] 6.7 Implement LiveView code to make tests pass
  - **Only after all tests are written and failing**
  - Add socket assigns, event handlers, UI elements
  - Run tests after each change to see progress
  - All tests in task 6 should pass when complete
  - _Requirements: All requirements from tasks 6.1-6.6_

- [ ] 7. Write failing LiveView integration tests (TDD)
  - **Write tests FIRST before implementation**
  - Tests should fail initially
  - Test full user interactions with LiveView
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [ ] 7.1 Write failing test: draw button visibility
  - **Write test FIRST - it should fail**
  - Test should render LiveView and check button visibility based on pending_question_draw
  - Run test and verify it fails
  - _Requirements: 11.3, 11.4_

- [ ] 7.2 Write failing test: draw button functionality
  - **Write test FIRST - it should fail**
  - Test should simulate clicking button and verify card drawn, turn advanced
  - Run test and verify it fails
  - _Requirements: 2.2, 2.3, 2.4, 11.3_

- [ ] 7.3 Write failing test: playing cards when draw pending
  - **Write test FIRST - it should fail**
  - Test should attempt to play cards and verify rejection with error message
  - Run test and verify it fails
  - _Requirements: 10.3, 10.4_

- [ ] 7.4 Write failing test: question banner
  - **Write test FIRST - it should fail**
  - Test should render LiveView and check banner visibility and message
  - Run test and verify it fails
  - _Requirements: 11.1, 11.2, 11.5_

- [ ] 8. Write failing end-to-end tests (TDD)
  - **Write tests FIRST before implementation**
  - Tests should fail initially
  - Test complete user flows from start to finish
  - _Requirements: All requirements_

- [ ] 8.1 Write failing E2E test: Complete question play
  - **Write test FIRST - it should fail**
  - Test full flow: create game, play question+answer combo, verify results
  - Run test and verify it fails
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 8.2 Write failing E2E test: Incomplete question play with draw
  - **Write test FIRST - it should fail**
  - Test full flow: play questions only, draw button appears, click to draw
  - Run test and verify it fails
  - _Requirements: 1.1, 1.2, 2.1, 2.2, 2.3, 2.4_

- [ ] 8.3 Write failing E2E test: Question with Ace answer
  - **Write test FIRST - it should fail**
  - Test full flow: play question+Ace, suit selection triggered
  - Run test and verify it fails
  - _Requirements: 5.1, 13.3_

- [ ] 8.4 Write failing E2E test: Next player plays normally
  - **Write test FIRST - it should fail**
  - Test that after question is resolved, next player plays with normal rules
  - Run test and verify it fails
  - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [ ] 8.5 Write failing E2E test: Edge cases
  - **Write test FIRST - it should fail**
  - Test multiple edge cases: starting card, last card, deck exhaustion, answer combos
  - Run test and verify it fails
  - _Requirements: 9.1, 9.2, 9.5, 13.5, 6.2, 6.3, 6.4_

- [ ] 9. Update documentation (after all tests pass)
  - **Only after all implementation is complete and tests pass**
  - Create comprehensive feature documentation
  - Document all mechanics, rules, and edge cases
  - _Requirements: All requirements_

- [ ] 9.1 Create docs/question-card-feature.md
  - Copy structure from existing feature docs
  - Document overview and core mechanics
  - Document user stories and behaviors
  - Document database touchpoints (none for this feature)
  - Document validation rules
  - _Requirements: All requirements_

- [ ] 9.2 Document edge cases and testing
  - Document all edge cases covered
  - Document test coverage
  - Document manual testing checklist
  - Document integration with existing features
  - Document known limitations
  - _Requirements: All requirements_

- [ ] 10. Manual testing and polish
  - Run full test suite
  - Manual testing of all scenarios
  - Fix any issues discovered
  - Code formatting and cleanup
  - Final review
  - _Requirements: All requirements_

- [ ] 10.1 Run full test suite
  - Run `mix test`
  - Verify all tests pass
  - Check test coverage for new code
  - Fix any failing tests
  - _Requirements: All requirements_

- [ ] 10.2 Manual testing checklist
  - Play single Q or 8 → prompted to draw
  - Play multiple Q or 8 → prompted to draw once
  - Play Q/8 with answer → no draw prompt, turn advances
  - Play Q/8 with answer combo → works correctly
  - Try to play cards when draw pending → rejected
  - Draw card when prompted → turn advances
  - Play Q/8 as last card without answer → draw required
  - Play Q/8 with answer as last cards → valid finish
  - Next player plays normally after question
  - Deck exhaustion during draw → recycle works
  - _Requirements: All requirements_

- [ ] 10.3 Code formatting and cleanup
  - Run `mix format`
  - Remove any debug code or comments
  - Ensure consistent naming conventions
  - Add any missing documentation
  - _Requirements: All requirements_

---

## Notes

- Tasks are designed to be executed sequentially
- Each task builds on previous work
- Tests are written alongside implementation
- Integration tests verify feature works with existing mechanics
- Manual testing ensures good user experience

## Dependencies

- Existing PlayValidator module
- Existing CardGames context
- Existing LiveView game interface
- Existing special card features (Ace, Jack, King, 2, 3)

## Estimated Effort

- PlayValidator updates: 3-4 hours
- CardGames context updates: 2-3 hours
- LiveView integration: 2-3 hours
- Testing: 4-5 hours
- Documentation and polish: 1-2 hours
- **Total: 12-17 hours**
