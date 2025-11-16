# Implementation Plan: Three Card Draw Penalty

## Overview

This implementation plan breaks down the 3 card feature into discrete, incremental coding tasks. Each task builds on previous work and references specific requirements from the requirements document. The plan follows the database-driven architecture established by the 2 card feature (spec 009).

## Task List

- [x] 1. Add penalty_count/1 helper function
  - Create public function in `CardGames` module that returns penalty count based on type
  - Handle "two" → 2, "three" → 3, nil/unknown → 0
  - Add @doc documentation explaining nil handling for inacti8ve penalties
  - _Requirements: All (foundation for penalty system)_

- [x] 2. Create data migration script
  - Create `priv/repo/migrate_penalty_data.exs` script
  - Query all game sessions with old `count` field in draw_penalty
  - Migrate active penalties: add penalty_type="two", remove count
  - Migrate inactive penalties: set to standard format with penalty_type=nil
  - Add logging for migration progress
  - _Requirements: 9.1 (backward compatibility)_

- [x] 3. Extend PlayValidator for 3 card validation
- [x] 3.1 Add all_threes?/1 helper function
  - Add private function to check if all cards in list are rank "3"
  - Follow same pattern as existing `all_twos?/1` and `all_jacks?/1`
  - _Requirements: 1.1, 4.1_

- [x] 3.2 Update valid_play?/3 for single 3 card (no penalty)
  - Add case for rank "3" in single card validation
  - Use existing `validate_single_card/3` for matching rules
  - Return {:three, valid?} tuple for type tracking
  - _Requirements: 1.1, 1.2_

- [x] 3.3 Update valid_play?/3 for combo 3 cards (no penalty)
  - Add case for `all_threes?(cards)` in combo validation
  - Use existing `validate_combo/3` for matching rules
  - Ensure non-additive behavior (handled in CardGames, not validator)
  - _Requirements: 4.1, 4.2, 4.3_

- [x] 3.4 Update valid_play?/3 to accept penalty_type option
  - Add `:penalty_type` to opts keyword list
  - Extract penalty_type in single card and combo validation
  - Pass penalty_type to blocking validation logic
  - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [x] 3.5 Implement 3 card blocking validation when penalty active
  - When penalty_active? is true, check penalty_type
  - If penalty_type == "three", accept "ace" or "3" cards only
  - If penalty_type == "two", reject "3" cards (cross-blocking prevention)
  - Return false for non-blocking cards
  - _Requirements: 2.1, 3.1, 5.3, 8.1, 8.2_

- [x] 3.6 Update validate_single_card/3 for 3 card with action_suit
  - When action_suit is set, allow 3 to match either action_suit OR rank "3"
  - Follow same pattern as existing 2 card logic
  - _Requirements: 6.4_

- [x] 3.7 Write unit tests for PlayValidator 3 card logic
  - Test `all_threes?/1` with various card combinations
  - Test single 3 card validation (matching suit, matching rank, no match)
  - Test combo 3 cards validation
  - Test 3 card blocking when penalty_type="three" (accept)
  - Test 3 card blocking when penalty_type="two" (reject - cross-blocking)
  - Test Ace blocking when penalty_type="three" (accept)
  - Test regular card when penalty_type="three" (reject)
  - _Requirements: All validation requirements_

- [ ] 4. Update CardGames context for 3 card penalty
- [x] 4.1 Update play_cards/3 to create 3 card penalty
  - Detect when cards contain rank "3"
  - Create draw_penalty map with penalty_type="three"
  - Set target_player_id to next player
  - Clear action_suit if present (same as 2 card behavior)
  - Use Ecto.Multi for atomic transaction
  - _Requirements: 1.1, 1.4_

- [x] 4.2 Update play_cards/3 to handle 3 card blocking
  - When penalty is active and 3 is played, check penalty_type
  - If penalty_type="three", transfer penalty to next player
  - If penalty_type="two", return error (cross-blocking prevention)
  - Keep penalty_type="three" when transferring
  - _Requirements: 3.1, 3.2, 3.3, 8.1, 8.2_

- [x] 4.3 Update play_cards/3 to handle Ace blocking 3 penalty
  - When Ace is played and penalty_type="three", clear penalty
  - Set action_suit to suit of the most recent 3 card
  - Do not prompt for suit selection (same as 2 card behavior)
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 4.4 Update play_cards/3 to pass penalty_type to validator
  - Extract penalty_type from game_session.draw_penalty
  - Add penalty_type to opts passed to PlayValidator.valid_play?/3
  - Ensure validation uses correct penalty type for blocking checks
  - _Requirements: 8.3, 8.4_

- [x] 4.5 Update process_draw_penalty/2 to handle 3 card penalty
  - Check penalty_type from game_session.draw_penalty
  - Calculate count using penalty_count/1 helper
  - Draw correct number of cards (2 for "two", 3 for "three")
  - Handle deck recycling if needed (reuse existing logic)
  - Clear penalty after drawing
  - _Requirements: 1.4, 6.1, 6.2, 6.3_

- [x] 4.6 Update select_starting_card/1 to exclude 3 cards
  - Filter out cards with rank "3" from eligible starting cards
  - Also exclude rank "2" (already implemented, verify it's working)
  - Handle edge case where all cards are 2s or 3s (use fallback)
  - _Requirements: 9.1, 9.2_

- [ ] 4.7 Write unit tests for CardGames 3 card logic
  - Test penalty_count/1 with "two", "three", nil, unknown
  - Test play_cards/3 creates 3 penalty with correct penalty_type
  - Test play_cards/3 transfers 3 penalty when blocked by 3
  - Test play_cards/3 clears 3 penalty when blocked by Ace
  - Test play_cards/3 rejects 3 blocking 2 penalty (cross-blocking)
  - Test play_cards/3 rejects 2 blocking 3 penalty (cross-blocking)
  - Test process_draw_penalty/2 draws 3 cards for penalty_type="three"
  - Test select_starting_card/1 excludes 3 cards
  - Test multiple 3s played together create single penalty (not cumulative)
  - _Requirements: All CardGames requirements_

- [ ] 5. Update LiveView for 3 card penalty UI
- [ ] 5.1 Update handle_event("accept_penalty") to use penalty_count/1
  - Get penalty_type from game_session.draw_penalty
  - Calculate count using CardGames.penalty_count/1
  - Call CardGames.process_draw_penalty/2
  - Wait for broadcast (don't update socket directly)
  - _Requirements: 1.4, 5.2_

- [ ] 5.2 Update penalty button rendering to show correct count
  - Use penalty_count/1 to calculate button text
  - Display "Draw 2 Cards" or "Draw 3 Cards" based on penalty_type
  - Show button only when penalty is active and targets current player
  - _Requirements: 1.3, 7.1_

- [ ] 5.3 Update penalty indicator to show correct count
  - Use penalty_count/1 to calculate indicator text
  - Display "Draw 2 penalty active" or "Draw 3 penalty active"
  - Show indicator when penalty is active (visible to all players)
  - _Requirements: 7.1, 7.3_

- [ ] 5.4 Update error messages for 3 card penalty
  - Show "Penalty Active. You must play blocking card or draw penalty cards" when non-blocking card played
  - Show specific error for cross-blocking attempts
  - Display notification when player must draw 3 cards
  - _Requirements: 5.3, 7.2, 8.1, 8.2_

- [ ] 5.5 Write LiveView integration tests for 3 card UI
  - Test "Draw 3 Cards" button displays when penalty_type="three"
  - Test "Draw 3 penalty active" indicator displays
  - Test clicking "Draw 3 Cards" button draws 3 cards
  - Test blocking cards are clickable when penalty active
  - Test error message when non-blocking card clicked
  - Test penalty indicator disappears after accepting penalty
  - _Requirements: All UI requirements_

- [ ] 6. End-to-end testing and verification
- [ ] 6.1 Test complete 3 card penalty flow
  - Player plays 3 → next player sees "Draw 3 Cards" button
  - Next player clicks button → draws 3 cards, turn advances
  - Verify penalty indicator appears and disappears correctly
  - _Requirements: 1.1, 1.4, 7.1, 7.2_

- [ ] 6.2 Test 3 card blocking with another 3
  - Player A plays 3 → Player B plays 3 → Player C sees penalty
  - Verify penalty transfers correctly
  - Verify penalty_type remains "three"
  - _Requirements: 3.1, 3.2, 3.3_

- [ ] 6.3 Test 3 card blocking with Ace
  - Player plays 3 → next player plays Ace
  - Verify penalty clears
  - Verify action_suit set to 3's suit
  - Verify next player must match suit
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ] 6.4 Test cross-blocking prevention
  - Player plays 2 → next player tries to play 3 → rejected
  - Player plays 3 → next player tries to play 2 → rejected
  - Verify error messages display correctly
  - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [ ] 6.5 Test edge cases
  - Play 3 as last card → player becomes cardless, penalty still applies
  - Draw 3 cards when deck has fewer than 3 → recycling works
  - Multiple 3s played together → penalty is 3, not cumulative
  - Starting card is never a 3
  - _Requirements: 4.1, 4.2, 4.3, 6.1, 6.2, 6.3, 9.1, 9.2, 9.3_

## Implementation Notes

### Reuse Existing Infrastructure

- **Penalty System**: Reuse `draw_penalty` map field from 2 card feature
- **Validation Pattern**: Follow same structure as `all_twos?/1` and 2 card validation
- **Blocking Logic**: Extend existing Ace blocking pattern
- **Deck Recycling**: Reuse existing `draw_card_from_deck/2` logic
- **UI Components**: Extend existing penalty button and indicator components

### Testing Strategy

- **Unit Tests First**: Test PlayValidator and CardGames logic in isolation
- **Integration Tests**: Test LiveView interactions and UI updates
- **End-to-End Tests**: Verify complete gameplay flows
- **Edge Cases**: Test boundary conditions and error scenarios

### Deployment Checklist

1. Run migration script: `mix run priv/repo/migrate_penalty_data.exs`
2. Verify migration: Check that all active penalties have penalty_type set
3. Run test suite: `mix test`
4. Deploy code changes
5. Monitor production logs for errors
6. Test in production with real game session

## Task Dependencies

```
1 (penalty_count helper)
  ↓
2 (migration script) ← can run independently
  ↓
3 (PlayValidator) → 4 (CardGames) → 5 (LiveView) → 6 (E2E testing)
  ↓                    ↓                ↓
3.7 (tests)         4.7 (tests)      5.5 (tests)
```

## Success Criteria

- All unit tests pass
- All integration tests pass
- Migration script runs successfully on production data
- 3 card penalty works identically to 2 card penalty (different count)
- Cross-blocking prevention works (2 cannot block 3, vice versa)
- UI displays correct penalty count and indicators
- No regressions in existing 2 card functionality
