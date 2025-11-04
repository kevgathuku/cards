# Implementation Plan: Draw Card from Deck

**Branch**: `003-pick-card-from-deck` | **Date**: 2025-11-04 | **Spec**: [spec.md](./spec.md) | **Status**: Clarified & Ready

## Summary

Enable players to draw a card from the deck during their turn. The card with the lowest `order_index` in the deck is moved to the player's hand, and the turn automatically advances to the next player. Players can draw once OR play once per turn (not both). The "Draw Card" button is hidden when the deck is empty.

**Technical Approach**: Add `draw_card_from_deck/2` function in `Kadi.CardGames` context, create LiveView event handler, validate player turn, update card location and turn order in atomic transaction, broadcast updates to all players. Button disabled during operation, UI updates only via broadcast.

**Scope Reduction**: Deck recycling (rebuilding deck from played stack) has been deferred to feature 004-recycle-played-stack.

## Technical Context

**Language/Version**: Elixir 1.14+ (OTP 25+)
**Primary Dependencies**: Phoenix 1.7, Phoenix LiveView, Ecto 3.x
**Storage**: PostgreSQL (via Ecto) - `deck_cards` table with `location_type`, `order_index`, `player_id` columns
**Testing**: ExUnit with Ecto Sandbox (`:manual` mode for async tests where applicable)
**Target Platform**: Web server (Phoenix)
**Project Type**: Web application (Phoenix LiveView)
**Performance Goals**: Draw card action must complete within 500ms (database update + broadcast)
**Constraints**:
  - Database-driven game state (all card locations tracked in `deck_cards`)
  - Turn-based gameplay (only current turn player can draw)
  - Real-time updates via Phoenix PubSub broadcasts
  - Draw OR play per turn (not both) - drawing auto-advances turn
  - Empty deck: hide button (deck recycling deferred to feature 004)
  - Turn order: Players ordered by join time (`inserted_at`), wraps around
  - UI update pattern: Button disabled, updates only via broadcast (not direct)
**Scale/Scope**:
  - 100+ simultaneous games
  - 1000+ concurrent players
  - Up to 52 cards per deck

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Code Quality Principles ✅

- **Pattern matching first**: Will use pattern matching for turn validation, deck card filtering
- **Immutability**: All Ecto operations return new structs; no mutation
- **Pure functions**: Turn calculation logic will be pure; side effects isolated to `Repo.transaction`
- **Small functions**: Break down into `draw_card_from_deck/2`, `get_next_player/2`, helper functions for validation
- **Documentation**: Will add `@doc` for all public functions with examples

### Context Boundaries ✅

- **Respect Phoenix contexts**: Changes within `Kadi.CardGames` context (domain logic)
- **LiveView responsibility**: `KadiWeb.GameLive` handles UI events, delegates to context
- **Database access**: Only context module accesses Ecto
- **Business logic location**: Turn order and card movement logic in `Kadi.CardGames` (appropriate)

### Testing Standards ✅

- **Minimum coverage**: Will add comprehensive tests for happy path, error cases, edge cases
- **Critical paths**: Turn validation, card movement, turn advancement are critical and will have 100% coverage
- **Edge cases**: Empty deck (button hidden), wrong player (button hidden), race conditions, 2/3/4+ player turn rotation, turn wrapping
- **Isolation**: Tests will use Ecto Sandbox `:manual` mode (existing pattern)

### Performance Requirements ✅

- **Response time**: Single SELECT + UPDATE + broadcast should complete <100ms; well within 500ms budget
- **Database queries**: Minimal queries (1 SELECT for card, 1 UPDATE for card+turn in transaction)
- **Transaction scope**: Atomic transaction ensures consistency without long locks

### Security Standards ✅

- **Input validation**: Must validate `player_id` matches `current_turn_player_id`
- **Authorization checks**: Only current turn player can pick card
- **SQL injection**: Ecto parameterized queries prevent injection

**GATE RESULT**: ✅ **PASS** - All constitution principles satisfied.

## Project Structure

### Documentation (this feature)

```text
specs/003-pick-card-from-deck/
├── spec.md              # Feature specification (completed)
├── plan.md              # This file
├── research.md          # Phase 0 output (to be created)
├── data-model.md        # Phase 1 output (to be created)
├── quickstart.md        # Phase 1 output (to be created)
└── tasks.md             # Phase 2 output (to be created via /speckit.tasks)
```

### Source Code

```text
lib/kadi/
├── card_games.ex                    # PRIMARY: Add draw_card_from_deck/2 and get_next_player/2
│                                    # BUGFIX: Fix get_game_session_players/1 ordering
└── games/
    ├── game_session.ex              # Schema (no changes needed)
    └── deck_card.ex                 # Schema (no changes needed)

lib/kadi_web/
└── live/
    ├── game_live.ex                 # Add handle_event("draw_card", ...) with no direct update
    └── game_live.html.heex          # Add "Draw Card" button (hidden when deck empty or not player's turn)

test/kadi/
├── card_games_test.exs              # Add tests for draw_card_from_deck/2, turn order logic
└── kadi_web/live/
    └── game_live_test.exs           # Add integration tests for draw card flow, button visibility
```

**Structure Decision**: Phoenix/Elixir web application. New functionality added to existing modules following established patterns (similar to `start_game/1` implementation).

## Complexity Tracking

**Status**: N/A - No constitution violations. Follows existing patterns for game actions.

## Implementation Phases

### Phase 0: Research ✅ COMPLETE (via /speckit.clarify)

**Status**: ✅ Complete

**Key Findings**:
1. **Turn order tracking**: `game_session.current_turn_player_id` stores current player
2. **Turn sequence**: Players ordered by `game_session_players.inserted_at` (join order), wraps around
3. **BUG FOUND**: `get_game_session_players/1` lacks explicit ordering (non-deterministic)
4. **Atomic updates**: `Ecto.Multi` with broadcast pattern (see `start_game/1` lines 150-190)
5. **Deck card selection**: Lowest `order_index` among `location_type = 'deck'`
6. **UI update pattern**: Existing `start_game` updates twice (direct + broadcast), but spec requires broadcast-only for this feature
7. **Empty deck handling**: Hide button (deck recycling is feature 004)
8. **Turn advancement**: Draw OR play, then auto-advance (FR-010)

**Critical Bug to Fix**:
```elixir
# lib/kadi/card_games.ex:252-259 (CURRENT - BROKEN)
defp get_game_session_players(game_session_id) do
  query =
    from gsp in GameSessionPlayer,
      where: gsp.game_session_id == ^game_session_id,
      select: gsp.player_id
  
  Repo.all(from p in Player, where: p.id in subquery(query))
end

# NEEDS TO BE:
defp get_game_session_players(game_session_id) do
  query =
    from gsp in GameSessionPlayer,
      where: gsp.game_session_id == ^game_session_id,
      order_by: [asc: gsp.inserted_at],  # FIX: Add explicit ordering
      select: gsp.player_id
  
  Repo.all(from p in Player, where: p.id in subquery(query))
end
```

**Output**: Findings documented in [clarifications.md](./clarifications.md)

### Phase 1: Design & Contracts ✅ COMPLETE (via /speckit.clarify)

**Status**: ✅ Complete

**Key Design Decisions** (from clarification session):
- ✅ **Turn order**: By join time (`inserted_at` ASC), wraps around to first player
- ✅ **Empty deck**: Hide "Draw Card" button (no error handling needed)
- ✅ **Turn advancement**: Auto-advance after draw (player cannot draw AND play)
- ✅ **UI update pattern**: Button disabled on click, update ONLY via broadcast (no direct socket update)
- ✅ **Button label**: "Draw Card"
- ✅ **Error handling**: Return tuples `{:ok, ...}` / `{:error, reason}`
- ✅ **Broadcast payload**: Full `game_session` (consistent with `start_game` pattern)
- ✅ **Button visibility**: Hidden when not player's turn OR deck is empty

**Function Signature**:
```elixir
@doc """
Draws a card from the deck for the specified player.

Validates that it's the player's turn, moves one card from deck to player's hand,
advances turn to next player (by join order), and broadcasts update.

Returns `{:ok, updated_game_session}` or `{:error, reason}`.

## Examples

    iex> draw_card_from_deck(game_session, player.id)
    {:ok, %GameSession{}}
    
    iex> draw_card_from_deck(game_session, wrong_player.id)
    {:error, :not_your_turn}
    
    iex> draw_card_from_deck(empty_deck_game, player.id)
    {:error, :deck_empty}
"""
def draw_card_from_deck(game_session, player_id)
```

**Outputs**:
- Design decisions documented in spec.md and clarifications.md
- Function contract defined above (to be added to card_games.ex)

### Phase 2: Task Breakdown ✅ COMPLETE

**Status**: ✅ Complete - [tasks.md](./tasks.md) generated

**Task Summary**:
- **Total Tasks**: 12 discrete, actionable tasks
- **Estimated Time**: 6-8 hours
- **Phases**: 5 (Foundation → Implementation → UI → Testing → Verification)
- **Critical Path**: Tasks 1.1 → 1.2 → 2.1 (must be sequential)
- **Parallel Work**: After Task 2.1, UI and testing tasks can run in parallel

**Key Deliverables**:
- ✅ Complete code implementations for all functions
- ✅ 12+ test cases with full test code
- ✅ Clear acceptance criteria for each task
- ✅ Dependency graph showing task relationships
- ✅ Performance benchmarks (<500ms requirement)

**First Task**: Task 1.1 - Fix `get_game_session_players/1` ordering bug (15 min, critical)

See [tasks.md](./tasks.md) for full breakdown.

## Risk Assessment

| Risk | Probability | Impact | Mitigation | Status |
|------|-------------|--------|------------|--------|
| Race condition (simultaneous draws) | Low | High | Use Ecto.Multi transaction with row-level locks | ✅ Mitigated by design |
| Empty deck breaks game flow | ~~Medium~~ None | ~~Medium~~ N/A | Hide button when deck empty (deck recycling is feature 004) | ✅ Resolved by scope change |
| Turn order calculation error | ~~Medium~~ Low | High | Fix `get_game_session_players/1` ordering; comprehensive tests | ⚠️ Bug identified, fix planned |
| Broadcast failure (stale UI) | Low | Medium | Rely on LiveView reconnection; test network interruption scenarios | ✅ Accepted risk |
| Performance regression | Very Low | Low | Profile transaction; ensure single query for card selection | ✅ Low risk |
| UI update double-render | Low | Low | Only update via broadcast (different from start_game pattern) | ✅ Mitigated by design |

## Success Criteria Validation

Mapping spec Success Criteria to implementation:

- **SC-001**: "100% of valid draw card actions result in exactly one card moved from deck to player hand"
  - ✅ **Addressed**: Ecto.Multi transaction ensures atomic update
  
- **SC-002**: "100% of draw card actions correctly advance the turn to the next player (by join order)"
  - ✅ **Addressed**: `get_next_player/2` function using `inserted_at` ordering with comprehensive tests

- **SC-003**: "Draw card action completes within 500ms for 95% of requests"
  - ✅ **Addressed**: Single transaction with minimal queries; performance test planned

- **SC-004**: "100% of draw attempts when it's not the player's turn are prevented (button hidden)"
  - ✅ **Addressed**: Button visibility conditional; backend validation as backup

- **SC-005**: "UI updates synchronized across all connected players within 1 second"
  - ✅ **Addressed**: Broadcast-only update pattern (no direct update race)

- **SC-006**: "Draw Card button is hidden in 100% of cases where deck is empty"
  - ✅ **Addressed**: Template conditional `@deck_size > 0`

## Next Steps

1. ✅ ~~Phase 0: Research~~ (Complete via `/speckit.clarify`)
2. ✅ ~~Phase 1: Design~~ (Complete via `/speckit.clarify`)
3. **Run `/speckit.tasks`**: Generate detailed task breakdown from refined task list
4. **Implementation**: 
   - Fix `get_game_session_players/1` ordering bug FIRST
   - Implement `get_next_player/2` helper
   - Implement `draw_card_from_deck/2`
   - Add LiveView handler and template changes
5. **Testing**: Execute comprehensive test plan (unit + integration)
6. **Code Review**: Ensure constitution compliance
7. **Merge**: Create PR with test evidence
8. **Future**: Plan feature 004-recycle-played-stack after 003 is complete

## References

- **Feature Specification**: [spec.md](./spec.md)
- **Related Feature**: 001-deal-start-card (establishes game start pattern)
- **Related Feature**: 002-randomize-player-cards (deck order_index usage)
- **Existing Pattern**: `start_game/1` in lib/kadi/card_games.ex (lines 140-190)
- **Broadcast Pattern**: KadiWeb.Endpoint.broadcast at line 181

---

## Clarification Session Results

**Session Date**: 2025-11-04  
**Questions Answered**: 8 critical + 3 minor  
**Spec Quality**: Improved from 8/10 to 9.5/10  
**Scope Change**: Deck recycling deferred to feature 004 (complexity reduction)

**Critical Decisions**:
- Turn order by join time (`inserted_at`), wraps around ✅
- Empty deck: hide button (no error handling) ✅  
- Draw OR play per turn (auto-advance) ✅
- UI update: broadcast-only (no direct update) ✅
- Button label: "Draw Card" ✅

**Bug Discovered**: `get_game_session_players/1` lacks ordering (will be fixed in implementation)

See [clarification-results.md](./clarification-results.md) for full session details.

---

**Plan Status**: ✅ **READY FOR IMPLEMENTATION** - All phases complete, tasks ready to generate

**Summary**: Add player action to draw card from deck, validate turn, move card to hand, auto-advance turn, broadcast updates. Button hidden when deck empty or not player's turn. Deck recycling deferred to feature 004. No schema changes required.
