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

- [ ] 2. Add unit tests for PlayValidator question card logic
  - Test question card detection helpers
  - Test combo splitting with various scenarios
  - Test question sequence validation
  - Test answer validation
  - Test integration with valid_play?/3
  - _Requirements: All validation requirements_

- [ ] 2.1 Test question card detection
  - Test `all_queens?/1` with all Q cards, mixed cards, empty list
  - Test `all_eights?/1` with all 8 cards, mixed cards, empty list
  - Test `all_question_cards?/1` with Q only, 8 only, mixed Q/8, non-questions
  - Test `is_question_card?/1` with Q, 8, and non-question cards
  - _Requirements: 1.1, 1.2_

- [ ] 2.2 Test combo splitting
  - Test splitting `[8H, 8D, 2D]` → `{[8H, 8D], [2D]}`
  - Test splitting `[8H, 8D]` → `{[8H, 8D], []}`
  - Test splitting `[8H, 8D, 4D, 4H]` → `{[8H, 8D], [4D, 4H]}`
  - Test splitting `[8H, QH, 2D]` → `{[8H, QH], [2D]}`
  - Test splitting `[8H, 8D, QD]` → `{[8H, 8D, QD], []}` (Q at end is question)
  - _Requirements: 1.2, 3.5, 4.5, 10.5_

- [ ] 2.3 Test question sequence validation
  - Test valid sequence: `[8H, 8D]` (match by rank)
  - Test valid sequence: `[8H, QH]` (match by suit)
  - Test valid sequence: `[8H, QH, QD, 8D]` (mixed, all match)
  - Test invalid sequence: `[8H, QD]` (no match)
  - Test single question card: `[8H]` (always valid)
  - _Requirements: 4.1, 4.3_

- [ ] 2.4 Test answer validation
  - Test single answer matching suit: `[2D]` after `[8D]`
  - Test single answer matching rank: `[8H]` after `[8D]` (but 8 is question, so invalid)
  - Test answer combo: `[4D, 4H]` after `[8D]` (first matches suit, same rank)
  - Test invalid answer: `[2H]` after `[8D]` (no match)
  - Test invalid answer combo: `[4D, 5D]` after `[8D]` (different ranks)
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 6.2, 6.3, 6.4_

- [ ] 2.5 Test valid_play?/3 with question cards
  - Test complete play: `[8H, 8D, 2D]` on top card `5H` (8H matches suit)
  - Test incomplete play: `[8H, 8D]` on top card `5H` (8H matches suit)
  - Test invalid play: `[8H, 8D, 2H]` on top card `5D` (8H doesn't match)
  - Test question with answer combo: `[8H, 8D, 4D, 4H]` on top card `5H`
  - Test question ending with Q/8: `[8H, 8D, QD]` (all questions)
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 10.1, 10.2, 10.5_

- [ ] 3. Update starting card selection to exclude Q and 8
  - Modify `select_starting_card/1` in CardGames context
  - Filter out Q and 8 cards from selection
  - Ensure only regular cards (4, 5, 6, 7, 9, 10) can be starting cards
  - Add test to verify Q and 8 are never selected as starting cards
  - _Requirements: 8.1, 8.2, 8.3_

- [ ] 4. Add question draw prompt logic to CardGames context
  - Modify `play_cards/3` to detect incomplete question plays
  - Return special result indicating draw is needed
  - Add `answer_question_by_drawing/2` function to draw one card
  - Ensure turn advances after drawing
  - Handle deck exhaustion (recycle played pile)
  - _Requirements: 1.1, 1.2, 1.4, 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ] 4.1 Modify play_cards/3 for question detection
  - After validation, check if play is incomplete question combo
  - Use `split_question_and_answer/1` to detect
  - If answer list is empty, return `{:ok, :needs_draw, updated_game}`
  - If answer list has cards, execute play normally
  - Move cards to played pile in both cases
  - _Requirements: 1.1, 1.2, 1.4, 1.5_

- [ ] 4.2 Implement answer_question_by_drawing/2
  - Create new function `answer_question_by_drawing(game_session, player_id)`
  - Validate it's the player's turn
  - Draw one card from deck to player's hand
  - If deck is empty, recycle played pile first
  - Advance turn to next player
  - Broadcast game update
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 13.5_

- [ ] 4.3 Handle deck exhaustion during question draw
  - In `answer_question_by_drawing/2`, check if deck is empty
  - If empty, call `recycle_played_stack/1` before drawing
  - Ensure at least one card remains in played pile (the question card)
  - If recycling fails, handle gracefully (skip player with notification)
  - _Requirements: 2.5, 13.5_

- [ ] 5. Add integration tests for question card plays
  - Test complete question play (with answer)
  - Test incomplete question play (without answer)
  - Test drawing as answer to question
  - Test question with special card answers (Ace, Jack, King, 2, 3)
  - Test last card scenarios
  - _Requirements: All requirements_

- [ ] 5.1 Test complete question play
  - Setup: Player has `[8H, 8D, 2D]`, top card is `5H`
  - Play all three cards
  - Verify cards moved to played pile
  - Verify turn advanced to next player
  - Verify no draw prompt
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 5.2 Test incomplete question play
  - Setup: Player has `[8H, 8D]`, top card is `5H`
  - Play both cards
  - Verify cards moved to played pile
  - Verify turn did NOT advance
  - Verify draw prompt is needed
  - _Requirements: 1.1, 1.2, 2.1_

- [ ] 5.3 Test drawing as answer
  - Setup: Player played incomplete question, needs to draw
  - Call `answer_question_by_drawing/2`
  - Verify one card drawn to player's hand
  - Verify turn advanced to next player
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ] 5.4 Test question with Ace answer
  - Setup: Player has `[8H, 8D, AH]`, top card is `5H`
  - Play all three cards
  - Verify cards moved to played pile
  - Verify suit selection is triggered (action_type: "select_suit")
  - Verify turn did NOT advance (waiting for suit selection)
  - _Requirements: 5.1, 13.3_

- [ ] 5.5 Test question with penalty answer (2 or 3)
  - Setup: Player has `[8H, 8D, 2D]`, top card is `5H`
  - Play all three cards
  - Verify cards moved to played pile
  - Verify penalty activated for next player
  - Verify turn advanced to next player
  - _Requirements: 5.2, 5.3, 13.4_

- [ ] 5.6 Test question with Jack answer
  - Setup: Player has `[8H, 8D, JD]`, top card is `5H`
  - Play all three cards
  - Verify cards moved to played pile
  - Verify next player is skipped
  - Verify turn advanced to player after next
  - _Requirements: 5.4, 13.1_

- [ ] 5.7 Test question with King answer
  - Setup: Player has `[8H, 8D, KD]`, top card is `5H`
  - Play all three cards
  - Verify cards moved to played pile
  - Verify direction is reversed
  - Verify turn advanced in new direction
  - _Requirements: 5.5, 13.2_

- [ ] 5.8 Test last card as question without answer
  - Setup: Player has only `[8H]`, top card is `5H`
  - Play the card
  - Verify card moved to played pile
  - Verify player status is NOT "cardless"
  - Verify draw prompt is needed
  - Player draws card
  - Verify player has 1 card again
  - _Requirements: 9.1, 9.2, 9.5_

- [ ] 5.9 Test last cards as question with answer
  - Setup: Player has only `[8H, 2H]`, top card is `5H`
  - Play both cards
  - Verify cards moved to played pile
  - Verify player status is "cardless"
  - Verify turn advanced to next player
  - _Requirements: 9.3, 9.4_

- [ ] 5.10 Test deck exhaustion during question draw
  - Setup: Player needs to draw for question, deck is empty
  - Call `answer_question_by_drawing/2`
  - Verify played pile is recycled
  - Verify one card drawn to player's hand
  - Verify turn advanced
  - _Requirements: 2.5, 13.5_

- [ ] 6. Add LiveView integration for question draw prompt
  - Add `pending_question_draw` socket assign
  - Handle `:needs_draw` result from `play_cards/3`
  - Add "answer_question_draw" event handler
  - Update UI to show draw button when needed
  - Add question banner to indicate active question
  - _Requirements: 2.1, 11.1, 11.2, 11.3, 11.4, 11.5_

- [ ] 6.1 Add socket assign for question state
  - In `mount/3`, initialize `pending_question_draw: false`
  - In `assign_game_state/2`, reset `pending_question_draw: false`
  - Add helper to check if current player needs to draw
  - _Requirements: 2.1, 11.1_

- [ ] 6.2 Handle needs_draw result in play_cards event
  - In `handle_event("play_cards", ...)`, check result
  - If `{:ok, :needs_draw, game}`, set `pending_question_draw: true`
  - Broadcast game update as usual
  - Don't advance turn (already handled in context)
  - _Requirements: 1.4, 2.1_

- [ ] 6.3 Implement answer_question_draw event handler
  - Add `handle_event("answer_question_draw", _params, socket)`
  - Call `CardGames.answer_question_by_drawing/2`
  - On success, clear `pending_question_draw` flag
  - Broadcast game update
  - Handle errors gracefully
  - _Requirements: 2.2, 2.3, 2.4_

- [ ] 6.4 Add draw button to UI template
  - In `game_live.html.heex`, add conditional button
  - Show when `@pending_question_draw` and it's player's turn
  - Button text: "Draw Card (Answer Question)"
  - Style with blue background and pulse animation
  - Wire to "answer_question_draw" event
  - _Requirements: 11.1, 11.3_

- [ ] 6.5 Add question banner to UI
  - Add banner above game board when `@pending_question_draw`
  - Show message: "Question Active: Draw a card or play a matching card"
  - Style with blue background and info icon
  - Hide when question is not active
  - _Requirements: 11.1, 11.2, 11.5_

- [ ] 6.6 Prevent playing cards when draw is pending
  - In `handle_event("play_cards", ...)`, check `@pending_question_draw`
  - If true, reject play with error message
  - Show flash: "You must draw a card to answer the question"
  - Don't execute play
  - _Requirements: 10.3, 10.4_

- [ ] 7. Add LiveView tests for question card UI
  - Test draw button appears when question pending
  - Test draw button hidden when no question
  - Test clicking draw button draws card
  - Test playing cards when draw pending is rejected
  - Test question banner displays correctly
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [ ] 7.1 Test draw button visibility
  - Render LiveView with `pending_question_draw: true`
  - Assert draw button is visible
  - Render with `pending_question_draw: false`
  - Assert draw button is not visible
  - _Requirements: 11.3, 11.4_

- [ ] 7.2 Test draw button functionality
  - Setup: Player needs to draw for question
  - Click draw button
  - Verify `answer_question_by_drawing/2` was called
  - Verify player has one more card
  - Verify turn advanced
  - _Requirements: 2.2, 2.3, 2.4, 11.3_

- [ ] 7.3 Test playing cards when draw pending
  - Setup: Player needs to draw for question
  - Attempt to play cards
  - Verify play is rejected
  - Verify error message is shown
  - Verify `pending_question_draw` still true
  - _Requirements: 10.3, 10.4_

- [ ] 7.4 Test question banner
  - Render LiveView with `pending_question_draw: true`
  - Assert banner is visible with correct message
  - Render with `pending_question_draw: false`
  - Assert banner is not visible
  - _Requirements: 11.1, 11.2, 11.5_

- [ ] 8. Add end-to-end tests for question card scenarios
  - Test complete question card flow (play → no draw)
  - Test incomplete question card flow (play → draw)
  - Test question with special card answers
  - Test next player plays normally after question
  - Test edge cases (last card, deck exhaustion)
  - _Requirements: All requirements_

- [ ] 8.1 E2E: Complete question play
  - Create game with 2 players
  - Give player 1: `[8H, 8D, 2D]`, top card: `5H`
  - Player 1 plays all three cards
  - Verify cards on played pile
  - Verify turn is now player 2
  - Verify no draw button shown
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 8.2 E2E: Incomplete question play with draw
  - Create game with 2 players
  - Give player 1: `[8H, 8D]`, top card: `5H`
  - Player 1 plays both cards
  - Verify draw button appears
  - Player 1 clicks draw button
  - Verify player 1 has 1 card
  - Verify turn is now player 2
  - _Requirements: 1.1, 1.2, 2.1, 2.2, 2.3, 2.4_

- [ ] 8.3 E2E: Question with Ace answer
  - Create game with 2 players
  - Give player 1: `[8H, 8D, AH]`, top card: `5H`
  - Player 1 plays all three cards
  - Verify suit selection buttons appear
  - Player 1 selects suit
  - Verify turn is now player 2
  - Verify action_suit is set
  - _Requirements: 5.1, 13.3_

- [ ] 8.4 E2E: Next player plays normally
  - Create game with 2 players
  - Player 1 plays question and draws
  - Top card is now `8D`
  - Give player 2: `[4D, 5H]`
  - Player 2 can play `4D` (matches suit)
  - Verify play succeeds
  - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [ ] 8.5 E2E: Edge cases
  - Test Q and 8 excluded from starting card (run multiple games)
  - Test last card as question without answer (draw required)
  - Test deck exhaustion during question draw (recycle works)
  - Test question with answer combo `[8H, 8D, 4D, 4H]`
  - _Requirements: 8.1, 8.2, 8.3, 9.1, 9.2, 9.5, 13.5, 6.2, 6.3, 6.4_

- [ ] 9. Update documentation
  - Create feature documentation file
  - Document question card mechanics
  - Document validation rules
  - Document UI elements
  - Document integration with other features
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
