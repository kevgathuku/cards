# Implementation Plan: Recycle Played Stack into Deck

**Branch**: `004-recycle-played-stack` | **Date**: 2025-11-05 | **Spec**: [spec.md](./spec.md) | **Status**: Planning

## Summary

Automatically rebuild the deck from played stack cards when a player attempts to draw from an empty deck. All cards in the played stack (except the topmost visible card) are shuffled and moved back to the deck with randomized `order_index` values. This prevents the game from stalling when the deck is depleted.

**Technical Approach**: Modify `draw_card_from_deck/2` to detect empty deck, trigger recycling via new `recycle_played_stack/1` function, reuse existing shuffle logic from game initialization, maintain atomicity with `Ecto.Multi`, and broadcast updates to all players.

**Scope**: Backend context function, LiveView integration for user feedback, comprehensive tests for edge cases (1 card in pile, empty pile, etc.).

## Technical Context

**Language/Version**: Elixir 1.17+ (OTP 25+)  
**Primary Dependencies**: Phoenix 1.7, Phoenix LiveView, Ecto 3.x  
**Storage**: PostgreSQL (via Ecto) - `deck_cards` table with `location_type`, `order_index`, `player_id` columns  
**Testing**: ExUnit with Ecto Sandbox (`:manual` mode for async tests where applicable)  
**Target Platform**: Web server (Phoenix)  
**Project Type**: Web application (Phoenix LiveView)  
**Performance Goals**: Recycle operation must complete within 1 second (database update + shuffle + broadcast)  
**Constraints**:
  - Database-driven game state (all card locations tracked in `deck_cards`)
  - Must keep topmost played card visible as reference
  - Atomic transaction (all cards moved or none)
  - Real-time updates via Phoenix PubSub broadcasts
  - Minimum 1 card must remain in played stack
  - Shuffle must be sufficiently random (use Elixir's `:rand.shuffle/1`)
**Scale/Scope**:
  - 100+ simultaneous games
  - 1000+ concurrent players
  - Up to 52 cards per deck
  - Typical recycle: ~40-50 cards

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Code Quality Principles ✅

- **Pattern matching first**: Will use pattern matching for card filtering, edge case detection
- **Immutability**: All Ecto operations return new structs; no mutation
- **Pure functions**: Shuffle and order assignment will be pure; side effects isolated to `Repo.transaction`
- **Small functions**: Break down into `recycle_played_stack/1`, helper functions for filtering, shuffling
- **Documentation**: Will add `@doc` for all public functions with examples

### Context Boundaries ✅

- **Respect Phoenix contexts**: Changes within `Kadi.CardGames` context (domain logic)
- **LiveView responsibility**: `KadiWeb.GameLive` handles UI feedback, delegates to context
- **Database access**: Only context module accesses Ecto
- **Business logic location**: Recycle logic in `Kadi.CardGames` (appropriate)

### Testing Standards ✅

- **Minimum coverage**: Will add comprehensive tests for happy path, error cases, edge cases
- **Critical paths**: Empty deck detection, card recycling, shuffle randomness are critical
- **Edge cases**: 
  - Only 1 card in played stack (cannot recycle)
  - Empty played stack (error case)
  - Exactly 2 cards in played stack (minimum recyclable)
  - Full 52-card recycle scenario
- **Isolation**: Tests will use Ecto Sandbox `:manual` mode (existing pattern)

### Performance Requirements ✅

- **Response time**: Database queries + shuffle should complete <1 second
- **Database queries**: Minimal queries (1 SELECT for played cards, 1 batch UPDATE)
- **Transaction scope**: Atomic transaction ensures consistency without long locks

### Security Standards ✅

- **Input validation**: Validate game state before recycling
- **Authorization checks**: Only triggered during valid game actions (draw card)
- **SQL injection**: Ecto parameterized queries prevent injection

**GATE RESULT**: ✅ **PASS** - All constitution principles satisfied.

## Project Structure

### Documentation (this feature)

```text
specs/004-recycle-played-stack/
├── spec.md              # Feature specification (existing stub)
├── plan.md              # This file
├── research.md          # Phase 0 output (to be created)
├── data-model.md        # Phase 1 output (to be created)
├── quickstart.md        # Phase 1 output (to be created)
└── tasks.md             # Phase 2 output (to be created via /speckit.tasks)
```

### Source Code

```text
lib/kadi/
└── card_games.ex                    # PRIMARY: Add recycle_played_stack/1, modify draw_card_from_deck/2

lib/kadi_web/
└── live/
    ├── game_live.ex                 # Add flash message for recycle notification
    └── game_live.html.heex          # Optional: Add visual indicator for deck rebuild

test/kadi/
├── card_games_test.exs              # Add tests for recycle_played_stack/1
└── kadi_web/live/
    └── game_live_test.exs           # Add integration tests for recycle flow
```

**Structure Decision**: Phoenix/Elixir web application. New functionality added to existing modules following established patterns (similar to `draw_card_from_deck/2` implementation in feature 003).

## Complexity Tracking

**Status**: N/A - No constitution violations anticipated. Follows existing patterns for game actions.

## Implementation Phases

### Phase 0: Research ⏳ PENDING

**Goal**: Understand current deck/played_stack mechanics and identify implementation approach.

**Key Questions**:
1. How is "topmost" card in played stack identified? (Highest `order_index`?)
2. What shuffle algorithm is currently used in `create_game_session`?
3. How should `order_index` be assigned to recycled cards?
4. What broadcast message format should be used for recycle events?
5. Should recycle be automatic or require player confirmation?
6. What happens if played stack is empty or has only 1 card?

**Research Tasks**:
- [ ] Review `create_game_session` shuffle logic (lines 105-110)
- [ ] Review `draw_card_from_deck/2` empty deck detection
- [ ] Review `deck_cards` schema and `order_index` usage
- [ ] Identify how played stack ordering is maintained
- [ ] Check existing broadcast patterns for reference
- [ ] Review UI showing deck/played pile counts

**Output**: Findings documented in `research.md`

### Phase 1: Design & Contracts ⏳ PENDING

**Goal**: Define function signatures, data flow, and edge case handling.

**Design Decisions Needed**:
- [ ] **Recycle trigger**: Automatic when deck empty or manual button?
- [ ] **Minimum cards**: Require 2+ cards in played stack to recycle?
- [ ] **Shuffle algorithm**: Use `:rand.shuffle/1` (existing) or custom?
- [ ] **Order index assignment**: Sequential (1, 2, 3...) or randomized gaps?
- [ ] **Error handling**: What errors can occur? How to communicate to user?
- [ ] **UI feedback**: Flash message? Visual animation? Sound effect?
- [ ] **Transaction scope**: Just card updates or also broadcast in transaction?

**Function Signatures (Draft)**:
```elixir
@doc """
Recycles cards from the played stack back into the deck.

Takes all cards from played_stack except the topmost card, shuffles them,
assigns new order_index values, and moves them to the deck location.

Returns `{:ok, updated_game_session}` or `{:error, reason}`.

## Examples

    iex> recycle_played_stack(game_session)
    {:ok, %GameSession{}}
    
    iex> recycle_played_stack(empty_played_stack_game)
    {:error, :insufficient_cards_to_recycle}
"""
def recycle_played_stack(game_session)
```

**Outputs**:
- Function contracts defined
- Data flow diagram in `data-model.md`
- Quickstart guide in `quickstart.md`

### Phase 2: Task Breakdown ⏳ PENDING

**Goal**: Break implementation into discrete, testable tasks.

**Expected Tasks** (preliminary):
1. Implement `recycle_played_stack/1` function
2. Modify `draw_card_from_deck/2` to call recycle when deck empty
3. Add helper function to filter recyclable cards
4. Add shuffle and order assignment logic
5. Add transaction with `Ecto.Multi`
6. Add broadcast for recycle event
7. Add flash message in LiveView
8. Unit tests for `recycle_played_stack/1`
9. Integration tests for empty deck flow
10. Edge case tests (1 card, empty pile, etc.)

**Output**: Detailed tasks in `tasks.md` (via `/speckit.tasks`)

## Risk Assessment

| Risk | Probability | Impact | Mitigation | Status |
|------|-------------|--------|------------|--------|
| Edge case: Only 1 card in played stack | Medium | Medium | Return error, require manual intervention or game end | ⚠️ Needs design decision |
| Shuffle not random enough | Low | Medium | Use `:rand.shuffle/1` (cryptographically sufficient for games) | ✅ Low risk |
| Performance with 50+ cards | Very Low | Low | Single batch UPDATE should be fast | ✅ Low risk |
| Race condition (multiple players draw simultaneously) | Very Low | Medium | Existing turn validation prevents this | ✅ Mitigated |
| Topmost card identification ambiguity | Medium | High | Define clear rule: highest `order_index` in played_stack | ⚠️ Needs research |
| Transaction timeout | Very Low | Low | Operation should complete in <100ms | ✅ Low risk |

## Success Criteria Validation

**Feature is complete when**:
1. ✅ Deck automatically rebuilds when empty and player draws
2. ✅ Topmost card remains in played stack as reference
3. ✅ Recycled cards are shuffled randomly
4. ✅ All players receive real-time update
5. ✅ Edge cases handled gracefully (1 card, empty pile)
6. ✅ Operation completes in <1 second
7. ✅ All tests passing (unit + integration)
8. ✅ No data loss or corruption
9. ✅ UI provides clear feedback to players

## Dependencies

**Prerequisites**:
- ✅ Feature 003 (draw card from deck) - COMPLETED
- ✅ `deck_cards` table with `location_type` and `order_index`
- ✅ Broadcast infrastructure (Phoenix PubSub)

**Blockers**: None

## Next Steps

1. **Run `/speckit.research`**: Investigate current shuffle logic and played stack ordering
2. **Phase 1: Design**: Define function signatures and edge case handling
3. **Run `/speckit.tasks`**: Generate detailed task breakdown
4. **Implementation**: Execute tasks in order
5. **Testing**: Comprehensive test coverage for edge cases
6. **Code Review**: Ensure constitution compliance
7. **Merge**: Create PR with test evidence

## References

- **Related Feature**: 003-pick-card-from-deck (draw card implementation)
- **Existing Pattern**: `create_game_session` shuffle logic (lines 105-110 in card_games.ex)
- **Shuffle Reference**: Elixir `:rand.shuffle/1` documentation
- **Transaction Pattern**: `draw_card_from_deck/2` uses `Ecto.Multi` (lines 245-265)

---

**Plan Status**: ⏳ **READY FOR RESEARCH** - Next step: `/speckit.research`

**Summary**: Recycle played stack cards back into deck when depleted. Keep topmost card visible, shuffle remaining cards, assign new order indices, move to deck location, broadcast update. Handle edge cases gracefully. No schema changes required.
