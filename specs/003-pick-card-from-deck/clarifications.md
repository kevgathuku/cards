# Specification Clarifications: Pick Card from Deck

**Generated**: 2025-11-04  
**Status**: ✅ RESOLVED  
**Spec Version**: Updated with answers

## Clarification Session Summary

All critical questions have been answered. The specification has been updated accordingly.

---

## Answers Provided

### 1. Turn Order Algorithm ✅ RESOLVED

**Q1.1**: Players ordered by **join time** (`game_session_players.inserted_at` ASC)

**Q1.2**: Turns **wrap around** (last player → first player)

**Action Taken**: 
- Updated FR-005 to specify "by join time, wrapping around"
- Updated Technical Approach to specify `order_by: [asc: inserted_at]`
- Noted that `get_game_session_players/1` needs ordering fix

---

### 2. Empty Deck Behavior ✅ RESOLVED

**Q2.1**: Player **CAN** play a card from hand when deck is empty (drawing is optional)

**Q2.3**: **Hide "Draw Card" button** when deck is empty (Option C selected)

**Future Feature**: Deck recycling (rebuilding deck from played stack) will be feature **004-recycle-played-stack**

**Action Taken**:
- Updated FR-006: Hide button when deck empty
- Updated User Story 2: Focus on button hiding, not error handling
- Added OOS-002: Deck recycling is out of scope
- Added note about dependency on feature 004

---

### 3. Turn Advancement ✅ RESOLVED

**Q7.2**: Player can **draw once OR play once**, then turn **auto-advances**

**Action Taken**:
- Added FR-010: Drawing auto-advances turn
- Updated edge cases
- Added OOS-005: Multiple draws per turn not allowed

---

### 4. UI Update Pattern ✅ RESOLVED

**Q3.1**: Button **disabled**, UI updates **only after broadcast received** (Option C)

**Action Taken**:
- Added NFR-004: Button disabled on click
- Updated Frontend Flow: No direct socket update, wait for broadcast
- Clarified this differs from `start_game` pattern (which updates twice)

---

### 5. Game Rules ✅ RESOLVED

**Q7.1**: **No hand size limit**

**Q5.2**: Button labeled **"Draw Card"**

**Action Taken**:
- Updated all references from "Pick Card" to "Draw Card"
- Updated button label in Technical Approach
- Confirmed no validation needed for hand size

---

## Issues Identified and Fixed

### Critical Bug Found
**Issue**: `get_game_session_players/1` has no explicit ordering
**Impact**: Turn order would be non-deterministic
**Fix Required**: Add `order_by: [asc: gsp.inserted_at]` to query
**Tracked In**: Plan.md Phase 0 research tasks

---

## Remaining Work

1. ✅ Specification updated with all answers
2. ⏳ Update plan.md with clarification results
3. ⏳ Create stub spec for feature 004-recycle-played-stack
4. ⏳ Proceed to Phase 0 research

---

## Feature Scope Changes

**Original Scope**: Simple card drawing with error on empty deck
**Updated Scope**: Card drawing with button hiding (simpler)
**Deferred to 004**: Deck recycling from played stack (more complex)

This scope reduction makes feature 003 cleaner and more focused.

---

## Critical Clarifications Needed

### 1. Turn Order Algorithm ⚠️ HIGH PRIORITY

**Issue**: The specification assumes "sequential order" for turn advancement (FR-005, line 120-123), but the implementation details are unclear.

**Questions**:
- Q1.1: How are players ordered in the turn sequence?
  - Option A: By `game_session_players.inserted_at` (join order)
  - Option B: By `game_session_players.id` (database ID)
  - Option C: By `player.id`
  - Option D: Explicit `turn_order` column (not currently in schema)

- Q1.2: What happens in a 2-player game?
  - Player 1 picks → Player 2's turn
  - Player 2 picks → Player 1's turn
  - Is this the expected behavior?

- Q1.3: What happens if a player leaves the game during their turn?
  - Does the turn skip to the next active player?
  - Is this handled in this feature or separate?

**Current Code Evidence**:
```elixir
# lib/kadi/card_games.ex:252-259
defp get_game_session_players(game_session_id) do
  query =
    from gsp in GameSessionPlayer,
      where: gsp.game_session_id == ^game_session_id,
      select: gsp.player_id
  
  Repo.all(from p in Player, where: p.id in subquery(query))
end
```
**Analysis**: This query does NOT specify an explicit order, meaning player order is non-deterministic. This is a **critical bug** for turn-based gameplay.

**Recommendation**: 
- Add explicit ordering to `get_game_session_players/1`:
  ```elixir
  from gsp in GameSessionPlayer,
    where: gsp.game_session_id == ^game_session_id,
    order_by: [asc: gsp.inserted_at],  # or gsp.id
    select: gsp.player_id
  ```
- Document the turn order algorithm in spec (FR-005 needs more detail)

---

### 2. Empty Deck Behavior ⚠️ MEDIUM PRIORITY

**Issue**: FR-006 states "turn is NOT passed" when deck is empty (line 43), but this contradicts typical Poker/Kadi game rules.

**Questions**:
- Q2.1: If a player cannot pick from an empty deck, can they still play a card from their hand?
- Q2.2: Does the turn pass only after a valid action (pick OR play)?
- Q2.3: Should picking from deck be mandatory, or can players choose to pass/play instead?

**Current Spec Statement**:
> **Line 13**: "Q: What should happen if the deck is empty when a player tries to pick a card? → A: Not specified; needs clarification (assumed: display error, turn skipped)"
> **Line 43**: "I receive an error message 'No cards left in deck' and my turn is NOT passed to the next player."

**Contradiction**: Line 13 says "turn skipped", line 43 says "turn NOT passed".

**Recommendation**: Clarify whether:
- Option A: Error shown, turn does NOT advance (current spec)
- Option B: Error shown, turn DOES advance (line 13 assumption)
- Option C: When deck is empty, "Pick Card" button is hidden entirely

---

### 3. Game State Consistency During Pick ⚠️ MEDIUM PRIORITY

**Issue**: FR-007 and FR-008 describe real-time updates, but the timing and order of updates is unclear.

**Questions**:
- Q3.1: What does the picking player see immediately after clicking?
  - Option A: Optimistic UI update (card appears in hand before server confirms)
  - Option B: Loading state until server responds
  - Option C: Disabled button, then update after broadcast received

- Q3.2: Should the picking player's UI update from the broadcast or from the direct response?
  - Current pattern in `start_game`: Both direct update AND broadcast received

- Q3.3: If the broadcast fails for some players, do they see stale state?
  - Is there a retry mechanism?
  - LiveView reconnection should handle this, but should we test it?

**Current Code Pattern** (from start_game):
```elixir
# lib/kadi_web/live/game_live.ex:38-48
def handle_event("start_game", _, socket) do
  case CardGames.start_game(game_session) do
    {:ok, updated_game_session} ->
      socket = assign_game_state(socket, updated_game_session)  # Direct update
      {:noreply, socket |> put_flash(:info, "Game started!")}
  end
end

# The player who started also receives the broadcast (line 64-66)
def handle_info(%Phoenix.Socket.Broadcast{event: "game_updated", ...}, socket) do
  socket = assign_game_state(socket, updated_game_session)  # Broadcast update
  {:noreply, socket}
end
```

**Analysis**: This means the initiating player updates their state TWICE (once from direct response, once from broadcast). Is this intentional or a bug?

**Recommendation**: 
- Document whether pick_card should follow the same pattern
- Consider refactoring to only update via broadcast for consistency

---

### 4. Player Disconnection Scenarios ⚠️ LOW PRIORITY

**Issue**: Edge case mentioned (line 48) but not covered in requirements.

**Questions**:
- Q4.1: If current turn player disconnects, does their turn expire after a timeout?
- Q4.2: If a player picks a card and disconnects before UI updates, is the action still valid?
  - Answer implied: Yes (database state is source of truth)
- Q4.3: Should there be a reconnection grace period?

**Current Spec Statement**:
> **Line 48**: "What happens if a player disconnects immediately after picking a card? → Turn should still advance based on database state"

**Recommendation**: 
- Add this as a test case (not necessarily a feature requirement)
- Document that database state is authoritative

---

## Minor Clarifications Needed

### 5. UI/UX Details 🔵 LOW PRIORITY

**Questions**:
- Q5.1: Should there be a confirmation dialog before picking a card?
  - Recommendation: No (adds friction for a simple action)
  
- Q5.2: What should the button label be?
  - Option A: "Pick Card from Deck"
  - Option B: "Draw Card"
  - Option C: "Take Card"
  
- Q5.3: Should there be visual feedback during the pick action?
  - Loading spinner on button?
  - Disabled state?

- Q5.4: Where should the "Pick Card" button be placed in the UI?
  - Near the deck visualization?
  - In a player action panel?
  - Below the player's hand?

**Recommendation**: Use existing UI patterns from the game. Check with designer/product owner.

---

### 6. Error Message Specificity 🔵 LOW PRIORITY

**Issue**: FR-006 specifies exact error message, but other error cases don't.

**Questions**:
- Q6.1: What error message for "not your turn"?
  - Suggested: "It's not your turn"
  - Current spec: "appropriate error message" (line 30)

- Q6.2: Should errors be flash messages or inline?
  - Flash messages (current pattern in app)
  - Inline near button

**Recommendation**: Use flash messages for consistency with `start_game` pattern.

---

## Assumptions to Validate

### 7. Assumptions Made in Spec

These assumptions were made but should be confirmed:

1. **No hand limit** (line 12)
   - Validate: In real Poker/Kadi, is there a maximum hand size?
   - Impact: If yes, need to add validation in `pick_card_from_deck/2`

2. **Pick allowed anytime during turn** (line 14)
   - Validate: Can players pick multiple times in one turn?
   - Impact: If no, need to track "action taken this turn"

3. **Card identity hidden from other players** (line 50, FR-009)
   - Validate: Is this the correct game rule?
   - Impact: None on backend, just confirming frontend behavior

4. **Turn order wraps around** (line 123)
   - Validate: In a 4-player game, does Player 4 → Player 1?
   - Impact: Critical for `get_next_player/2` implementation

---

## Data Model Questions

### 8. Schema Validation

**Questions**:
- Q8.1: Is there a database constraint ensuring `location_type` is one of ('deck', 'player_hand', 'played_stack')?
  - Need to verify schema in `lib/kadi/games/deck_card.ex`

- Q8.2: Can `player_id` be NULL when `location_type = 'deck'`?
  - Assumed: Yes (cards in deck don't belong to a player)
  - Need to verify

- Q8.3: Is there an index on `deck_cards.order_index` for performance?
  - Recommendation: Add if missing (FR-004 performance critical)

---

## Testing Clarifications

### 9. Test Coverage Questions

**Questions**:
- Q9.1: Should we test with games in "lobby" status?
  - Expected: Error (game must be "live")
  - Current spec: Not mentioned

- Q9.2: Should we test concurrent pick attempts (race condition)?
  - Mentioned in risks (line 136)
  - Should this be a formal test case?

- Q9.3: What's the test strategy for "95% complete within 500ms" (SC-003)?
  - Load testing tool?
  - Manual profiling?
  - Statistical sampling in test suite?

---

## Recommendations Summary

### Must Address Before Implementation
1. ✅ **Define explicit turn order algorithm** (Q1.1, Q1.2)
2. ✅ **Clarify empty deck behavior** (Q2.1, Q2.2)
3. ✅ **Document UI update pattern** (Q3.1, Q3.2)

### Should Address During Design Phase
4. ⚠️ Fix `get_game_session_players/1` ordering bug
5. ⚠️ Validate hand limit assumption
6. ⚠️ Clarify "pick multiple times per turn" rule

### Nice to Have
7. 🔵 UI/UX details (button label, placement)
8. 🔵 Error message wording
9. 🔵 Performance test strategy

---

## Next Steps

1. **User/Product Owner**: Answer Q1.1, Q1.2, Q2.1, Q2.2, Q2.3
2. **Technical Lead**: Review Q3.1, Q3.2, Q4.1, Q8.1-Q8.3
3. **Update Spec**: Incorporate answers into spec.md
4. **Proceed to Research Phase**: Once critical questions answered

---

## Spec Quality Score

Based on typical specification quality metrics:

| Criteria | Score | Notes |
|----------|-------|-------|
| Requirements Clarity | 7/10 | Most FRs clear, but turn order needs detail |
| Edge Cases Covered | 8/10 | Good coverage, needs disconnection handling |
| Testability | 9/10 | Excellent acceptance scenarios |
| Technical Feasibility | 9/10 | Well-aligned with existing architecture |
| Completeness | 7/10 | Missing turn order algorithm details |

**Overall**: 8/10 - Good specification, needs minor clarifications on turn order and empty deck behavior before implementation.
