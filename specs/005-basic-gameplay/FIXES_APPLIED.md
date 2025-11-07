# Documentation Fixes Applied - Feature 005

**Date**: 2025-11-06  
**Status**: ✅ Critical fixes completed

---

## Summary

Applied critical fixes to implementation documentation based on comprehensive audit. All schema inconsistencies resolved, cross-references added, and plan.md completed with feature-specific content.

---

## Files Modified

### 1. data-model.md - CRITICAL FIXES ✅

**Issues Fixed**:
- ❌ REMOVED: Non-existent `played_stack` array field from migration
- ❌ REMOVED: Non-existent `current_turn` integer references
- ❌ REMOVED: Non-existent `turn_order` field references
- ❌ REMOVED: Non-existent `hand` array references
- ✅ FIXED: All references now use actual schema fields
- ✅ ADDED: Cross-references to docs/database-relationships.md
- ✅ ADDED: Cross-references to spec.md for validation rules

**Key Changes**:
```markdown
# BEFORE (WRONG)
- game_session.current_turn (integer)
- game_session_player.turn_order
- game_session_player.hand (array)
- Migration adds played_stack array

# AFTER (CORRECT)
- game_session.current_turn_player_id (UUID)
- game_session_player.inserted_at (for turn order)
- DeckCard queries for player hands
- Migration adds ONLY top_card_id
```

**New Sections Added**:
- Relationships diagram updated with actual fields
- Validation rules with spec.md references
- State transitions using DeckCard queries
- Query optimization patterns
- Data integrity constraints using actual schema

---

### 2. quickstart.md - CRITICAL FIXES ✅

**Issues Fixed**:
- ❌ REMOVED: Entire TurnManager module (Phase 2)
- ✅ REPLACED: With inline turn helper functions using actual schema
- ✅ ADDED: Cross-references to all supporting documents
- ✅ FIXED: validate_can_play to use current_turn_player_id
- ✅ UPDATED: Timeline from 12.5 hours to 12 hours

**Key Changes**:

**Phase 0 - Database Review**:
```markdown
# ADDED
📖 Reference to docs/database-relationships.md for:
- Deck card ordering conventions
- Cascade behavior
- Validation constraints
```

**Phase 1 - PlayValidator**:
```markdown
# ADDED
📖 Reference to data-model.md for validation rules
📖 Reference to spec.md clarifications
```

**Phase 2 - Turn Management** (MAJOR CHANGE):
```markdown
# BEFORE: Dedicated TurnManager module with wrong fields
defmodule Kadi.Games.TurnManager do
  def current_player(game_session) do
    game_session.game_session_players
    |> Enum.find(&(&1.turn_order == game_session.current_turn))  # WRONG
  end
end

# AFTER: Inline helpers with correct fields
defp get_game_session_players(game_session_id) do
  from(gsp in GameSessionPlayer,
    where: gsp.game_session_id == ^game_session_id,
    order_by: [asc: gsp.inserted_at],  # CORRECT
    preload: :player
  )
  |> Repo.all()
end

defp validate_current_turn(game_session, player_id) do
  if game_session.current_turn_player_id == player_id do  # CORRECT
    {:ok, :valid}
  else
    {:error, :not_your_turn}
  end
end
```

**Phase 3 - Context Functions**:
```markdown
# ADDED
📖 Reference to contracts/play_actions.md for event payloads
📖 Reference to data-model.md for state transitions
📖 Reference to research.md for Ecto.Multi rationale
```

**Phase 4 - LiveView**:
```markdown
# ADDED
📖 Reference to contracts/play_actions.md with specific line numbers:
- handle_event("select_card", ...) - line 15-45
- handle_event("play_cards", ...) - line 47-120
- handle_event("draw_card", ...) - line 122-175
- handle_info({:game_updated, ...}) - line 230-265
```

---

### 3. contracts/play_actions.md - ENHANCEMENTS ✅

**Issues Fixed**:
- ✅ ADDED: Card Notation Protocol section at top
- ✅ ADDED: Cross-reference to PlayValidator implementation
- ✅ CLARIFIED: Array format always used (even for single card)

**New Section**:
```markdown
## Card Notation Protocol

**Format**: JSON array of strings (even for single card)
- Single card: `["4H"]`
- Combo: `["4H", "4D", "4S"]`
- Case-insensitive: "4h" = "4H"

📖 Reference: See spec.md clarification #1
```

**Validation Section Enhanced**:
```markdown
📖 Implementation: See quickstart.md Phase 1 for PlayValidator module
```

---

### 4. plan.md - COMPLETED FROM TEMPLATE ✅

**Issues Fixed**:
- ❌ REMOVED: 100% generic template content
- ✅ ADDED: Feature-specific summary
- ✅ ADDED: Complete technical context
- ✅ ADDED: Actual project structure with file paths
- ✅ ADDED: Constitution check results
- ✅ ADDED: Implementation phases with status
- ✅ ADDED: Dependencies and risk assessment
- ✅ ADDED: Success criteria and next steps

**Key Sections Completed**:

**Summary**:
```markdown
Implement basic gameplay mechanics for regular cards (4, 5, 6, 7, 9, 10) 
with play and draw actions. Leverages existing features 003 and 004.
```

**Technical Context**:
```markdown
Language: Elixir 1.17+ with OTP 28
Dependencies: Phoenix 1.7.21, LiveView 1.1+, Ecto 3.10+
Performance: <100ms play validation
Scale: 2-4 players, 6 card types, 52-card deck
```

**Project Structure**:
```markdown
lib/kadi/
├── card_games.ex           # MODIFY: Add play_cards/3
├── games/
│   ├── game_session.ex     # MODIFY: Add top_card_id
│   └── play_validator.ex   # NEW
```

**Implementation Phases**:
- Phase 0: Research ✅ Complete
- Phase 1: Design ✅ Complete  
- Phase 2: Implementation 🔲 Not Started (~12 hours)
- Phase 3: Tasks 🔲 Not Started

---

## Schema Corrections Summary

| Incorrect Reference | Correct Schema | Files Fixed |
|-------------------|----------------|-------------|
| `played_stack` array | DeckCard.location_type='played_stack' | data-model.md |
| `current_turn` integer | `current_turn_player_id` UUID | data-model.md, quickstart.md |
| `turn_order` field | `inserted_at` timestamp | data-model.md, quickstart.md |
| `hand` array | DeckCard queries | data-model.md |
| TurnManager module | Inline helpers | quickstart.md |

---

## Cross-References Added

### quickstart.md
- Phase 0 → docs/database-relationships.md
- Phase 1 → data-model.md, spec.md
- Phase 2 → research.md
- Phase 3 → contracts/play_actions.md, data-model.md, research.md
- Phase 4 → contracts/play_actions.md (with line numbers)

### data-model.md
- Schema changes → docs/database-relationships.md
- Validation rules → spec.md FR numbers
- State transitions → docs/database-relationships.md
- Query optimization → Constitution section 4.1

### contracts/play_actions.md
- Card notation → spec.md clarification #1
- Validation → quickstart.md Phase 1

---

## Files Ready for Implementation

✅ **plan.md** - Complete feature overview and structure  
✅ **data-model.md** - Accurate schema and migrations  
✅ **quickstart.md** - Correct implementation steps  
✅ **contracts/play_actions.md** - Clear event specifications  
✅ **research.md** - Already correct (no changes needed)

---

## Validation Checklist

- [x] plan.md has feature-specific content (not template)
- [x] data-model.md uses only existing schema fields
- [x] data-model.md migration adds ONLY top_card_id
- [x] quickstart.md uses inline helpers (not TurnManager module)
- [x] quickstart.md has cross-references in all phases
- [x] All examples use current_turn_player_id (not current_turn)
- [x] All examples use inserted_at for ordering (not turn_order)
- [x] All examples query DeckCard for hands (not hand arrays)
- [x] contracts.md clarifies card notation format
- [x] All files cross-reference related documentation

---

## Next Steps

1. ✅ Documentation fixes complete
2. 🔲 Review with team
3. 🔲 Begin Phase 2.0 - Database migration
4. 🔲 Follow quickstart.md phases 1-5
5. 🔲 Run tests after each phase
6. 🔲 Generate tasks.md with /speckit.tasks

---

## Estimated Implementation Time

**Before Fixes**: Would have wasted hours debugging schema errors  
**After Fixes**: Clean implementation following correct schema

**Time Saved**: ~4-6 hours of debugging and rework  
**Fix Time**: ~90 minutes

**ROI**: Excellent - prevented major implementation errors

---

## Post-Implementation Bug Fixes

### Card Selection Order Fix (2025-11-07) ✅

**Issue**: Cards were being sent to backend in reverse selection order due to list prepending.

**Root Cause**:
- `handle_event("toggle_card", ...)` in `game_live.ex` used `[card_id | selected_cards]`
- This prepends new selections to the front of the list
- When user selected cards A, B, C, backend received `[C, B, A]`

**Impact**: 
- **Critical** for game rules requiring specific card order
- Affects combo plays where order matters
- Poor user experience (cards played in reverse of selection)

**Files Modified**:
1. `lib/kadi_web/live/game_live.ex`:
   - Added `Enum.reverse(selected_cards)` in `handle_event("play_cards", ...)`
   - Ensures cards are sent in selection order (oldest first)

2. `test/kadi_web/live/game_live_test.exs`:
   - Added test: "cards are sent to backend in selection order"
   - Verifies two cards selected as A, B are played as [A, B] in played_stack
   - Uses PubSub to intercept broadcast and validate order_index

**Code Change**:
```elixir
# BEFORE (BUG)
def handle_event("play_cards", _params, socket) do
  selected_cards = socket.assigns.selected_cards
  case CardGames.play_cards(game_session, player_id, selected_cards) do
    # ... cards in wrong order [C, B, A]
  end
end

# AFTER (FIXED)
def handle_event("play_cards", _params, socket) do
  selected_cards = socket.assigns.selected_cards
  cards_in_selection_order = Enum.reverse(selected_cards)
  case CardGames.play_cards(game_session, player_id, cards_in_selection_order) do
    # ... cards in correct order [A, B, C]
  end
end
```

**Test Coverage**:
```elixir
test "cards are sent to backend in selection order" do
  # 1. Select card1, then card2
  render_click(view, "toggle_card", %{"card_id" => to_string(card1.card_id)})
  render_click(view, "toggle_card", %{"card_id" => to_string(card2.card_id)})
  
  # 2. Play cards
  render_click(view, "play_cards")
  
  # 3. Verify order in played_stack
  assert played_first.card_id == card1.card_id  # Selected first
  assert played_second.card_id == card2.card_id # Selected second
end
```

**Why This Matters**:
- **Future Features**: Special card combos (2, 3, 8, J, Q, K, A) may depend on play order
- **Game Rules**: Some variants require specific sequencing for multi-card plays
- **User Expectations**: Players expect cards to play in the order they select them
- **Data Integrity**: `order_index` in played_stack now reflects actual selection order

**Validation**:
- ✅ All 25 game_live tests pass
- ✅ New test validates selection order A, B → played [A, B]
- ✅ No performance impact (single `Enum.reverse/1` call)

---

## References

- [AUDIT.md](./AUDIT.md) - Complete audit findings
- [plan.md](./plan.md) - Implementation plan (now complete)
- [data-model.md](./data-model.md) - Data model (now correct)
- [quickstart.md](./quickstart.md) - Implementation guide (now accurate)
- [contracts/play_actions.md](./contracts/play_actions.md) - Event contracts (enhanced)

