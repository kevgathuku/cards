# Implementation Plan Audit - Feature 005

**Date**: 2025-11-06  
**Auditor**: GitHub Copilot  
**Status**: 🟡 Needs Updates

---

## Executive Summary

The implementation documentation for feature 005 (basic gameplay) is generally well-structured but has several **critical inconsistencies** between files and **missing cross-references** that would slow down implementation. Key issues:

1. **CRITICAL**: data-model.md references non-existent `played_stack` array field
2. **CRITICAL**: TurnManager references non-existent `current_turn` integer and `turn_order` fields  
3. **MISSING**: Cross-references between quickstart steps and detailed design docs
4. **INCOMPLETE**: plan.md is still a template, not feature-specific
5. **OUTDATED**: Several sections don't reflect actual schema (despite recent alignment)

---

## Detailed Findings

### 1. plan.md - Implementation Plan

**Status**: 🔴 **INCOMPLETE - Still Template**

**Issues**:
- File is 100% generic template text
- No feature-specific content
- Placeholder text like "[FEATURE]", "[###-feature-name]", "[DATE]"
- Generic "ACTION REQUIRED" comments throughout
- No reference to actual implementation structure

**Recommendations**:
1. Fill in Summary section with: "Implement basic gameplay for regular cards (4-10) with play/draw mechanics, leveraging existing draw_card_from_deck/2 (feature 003) and recycle_played_stack/1 (feature 004)"
2. Update Technical Context:
   - Language/Version: Elixir 1.17+ with OTP 28
   - Primary Dependencies: Phoenix 1.7.21, Phoenix LiveView 1.1+, Ecto 3.10+, PostgreSQL
   - Storage: PostgreSQL with DeckCard tracking
   - Testing: ExUnit with async tests
   - Target Platform: Web (Phoenix LiveView)
   - Performance Goals: <100ms play validation and state updates
   - Constraints: Turn-based, atomic transactions, real-time updates
   - Scale/Scope: 2-4 players per game, 52 cards, 6 regular card types
3. Update Project Structure to reference actual directories:
   ```
   lib/
   ├── kadi/
   │   ├── card_games.ex (add play_cards/3)
   │   └── games/
   │       ├── game_session.ex (add top_card_id)
   │       ├── play_validator.ex (NEW)
   │       └── turn_manager.ex (REMOVE - inline logic instead)
   test/
   ├── kadi/
   │   ├── card_games_test.exs (add play_cards tests)
   │   └── games/
   │       └── play_validator_test.exs (NEW)
   ```
4. Add Constitution Check results (should pass all checks)
5. Remove generic placeholder text

**Priority**: HIGH - Developers will look here first

---

### 2. data-model.md - Data Model Design

**Status**: 🔴 **CRITICAL INCONSISTENCIES**

**Issues**:

#### Issue 2.1: Played Stack Array Field (Lines 150-470)
- Migration adds `played_stack` array field to `game_sessions`
- **PROBLEM**: Played stack is ALREADY tracked via DeckCard.location_type='played_stack'
- Contradicts Phase 0 in quickstart.md which correctly states "played stack is already tracked"
- Would create duplicate tracking mechanism

#### Issue 2.2: TurnManager References (Lines 294-340)
- Shows TurnManager using `game_session.current_turn` (integer)
- **PROBLEM**: GameSession uses `current_turn_player_id` (UUID), not `current_turn` integer
- References `game_session_players[].turn_order` field
- **PROBLEM**: GameSessionPlayer has NO `turn_order` field - uses `inserted_at` for ordering
- Code examples won't work with actual schema

#### Issue 2.3: State Transition Examples
- Line 235-290: Shows hand as array on GameSessionPlayer
- **PROBLEM**: NO `hand` field exists - cards tracked via DeckCard queries
- Examples would fail in actual implementation

**Recommendations**:

1. **REMOVE** entire migration section for `played_stack` array (lines 150-165):
   ```elixir
   # DELETE THIS - played_stack already tracked via DeckCard
   alter table(:game_sessions) do
     add :played_stack, {:array, :binary_id}, default: []
   end
   ```

2. **KEEP** only the `top_card_id` migration (already correct in quickstart.md)

3. **UPDATE** TurnManager examples to use actual schema:
   ```elixir
   # CORRECT VERSION - uses current_turn_player_id
   defmodule Kadi.Games.TurnManager do
     def current_player(game_session) do
       # Use current_turn_player_id, not current_turn integer
       game_session.current_turn_player
     end
     
     def get_next_player(game_session_id, current_player_id) do
       # Query GameSessionPlayer ordered by inserted_at (NOT turn_order)
       players = from(gsp in GameSessionPlayer,
         where: gsp.game_session_id == ^game_session_id,
         order_by: [asc: gsp.inserted_at],  # NOT turn_order
         preload: :player
       ) |> Repo.all()
       
       current_index = Enum.find_index(players, &(&1.player_id == current_player_id))
       next_index = rem(current_index + 1, length(players))
       Enum.at(players, next_index).player
     end
   end
   ```

4. **UPDATE** state transition examples to show DeckCard queries instead of hand arrays:
   ```elixir
   # Get player's hand (CORRECT)
   hand_cards = from(dc in DeckCard,
     where: dc.deck_id == ^deck_id and 
            dc.location_type == "player_hand" and 
            dc.player_id == ^player_id,
     preload: :card
   ) |> Repo.all()
   ```

5. **ADD** section reference: "See docs/database-relationships.md for deck ordering conventions"

**Priority**: CRITICAL - Will cause implementation errors

---

### 3. quickstart.md - Implementation Guide

**Status**: 🟡 **GOOD but Missing Cross-References**

**Issues**:

#### Issue 3.1: TurnManager Module (Lines 310-450)
- Includes full TurnManager module implementation
- **PROBLEM**: Uses non-existent `current_turn` integer and `turn_order` fields
- Contradicts actual schema which uses `current_turn_player_id` and `inserted_at`

#### Issue 3.2: Missing Cross-References
- Phase 1 (PlayValidator): No reference to validation rules in spec.md or data-model.md
- Phase 2 (TurnManager): No reference to turn logic decisions in research.md
- Phase 3 (Context): No reference to contracts/play_actions.md for event payloads
- Phase 4 (LiveView): Says "See contracts/play_actions.md" but no specific sections
- No reference to docs/database-relationships.md for order_index semantics

#### Issue 3.3: Context Implementation (Lines 450-600)
- `execute_play` function has good structure BUT:
- References `player.hand` which doesn't exist
- Should query DeckCard instead: `find_player_deck_card(game_session, player.id, card.id)`
- Actually, this IS corrected at line 600-610, so inconsistency in example

**Recommendations**:

1. **REMOVE or FIX** Phase 2: TurnManager Module
   - Option A: Remove TurnManager entirely, inline logic in CardGames context
   - Option B: Fix to use actual schema fields (current_turn_player_id, inserted_at)
   - **RECOMMENDED**: Option A - simpler, less code to maintain

2. **ADD** Cross-references throughout:

   **Phase 0** (line 28):
   ```markdown
   ### Phase 0: Database Schema Review (15 minutes)
   
   📖 **Reference**: See `docs/database-relationships.md` for:
   - Deck ordering conventions (order_index semantics)
   - Cascade behavior for deletions
   - Existing relationships and constraints
   ```

   **Phase 1** (line 138):
   ```markdown
   ### Phase 1: Play Validation Module (2 hours)
   
   📖 **Reference**: See `data-model.md` section "Validation Rules" for:
   - Single card matching logic (FR-002)
   - Combo validation rules (FR-003, FR-004)
   - Player hand validation (FR-015)
   
   📖 **See Also**: `spec.md` clarification #3 for combo ordering semantics
   ```

   **Phase 2** (line 310):
   ```markdown
   ### Phase 2: Turn Management (INLINE) (30 minutes)
   
   ⚠️ **NOTE**: No separate TurnManager module needed. Turn logic is simple enough
   to implement inline in CardGames context functions.
   
   📖 **Reference**: See `research.md` section 2 for turn management decisions
   
   **Implementation**: Turn logic is implemented in helper functions:
   - `get_game_session_players/1` - Orders by inserted_at
   - `get_next_player/2` - Wraps around player list
   ```

   **Phase 3** (line 450):
   ```markdown
   ### Phase 3: Context Functions (3 hours)
   
   📖 **Reference**: See `contracts/play_actions.md` for:
   - Event payloads (play_cards, draw_card)
   - Error codes and messages
   - State change specifications
   
   📖 **See Also**: 
   - `data-model.md` section "State Transitions" for atomic update patterns
   - `research.md` section 4 for Ecto.Multi rationale
   ```

   **Phase 4** (line 638):
   ```markdown
   ### Phase 4: LiveView Integration (4 hours)
   
   📖 **Reference**: See `contracts/play_actions.md` for:
   - Complete event handler specifications
   - Request/response flow diagrams
   - Error handling patterns
   
   Implement these handlers:
   - `handle_event("select_card", ...)` - See contracts line 15
   - `handle_event("play_cards", ...)` - See contracts line 40
   - `handle_event("draw_card", ...)` - See contracts line 120
   - `handle_info({:game_updated, ...})` - See contracts line 230
   ```

3. **UPDATE** Phase 2 to inline approach:
   ```markdown
   ### Phase 2: Turn Helper Functions (30 minutes)
   
   Instead of a separate TurnManager module, implement turn logic as private
   helpers in CardGames context.
   
   ```elixir
   # lib/kadi/card_games.ex (add to existing module)
   
   defp get_game_session_players(game_session_id) do
     from(gsp in GameSessionPlayer,
       where: gsp.game_session_id == ^game_session_id,
       order_by: [asc: gsp.inserted_at],  # Join order = turn order
       preload: :player
     )
     |> Repo.all()
   end
   
   defp get_next_player(players, current_player_id) do
     current_index = Enum.find_index(players, &(&1.player_id == current_player_id))
     next_index = rem(current_index + 1, length(players))
     Enum.at(players, next_index).player
   end
   
   defp validate_current_turn(game_session, player_id) do
     if game_session.current_turn_player_id == player_id do
       {:ok, :valid}
     else
       {:error, :not_your_turn}
     end
   end
   ```
   ```

4. **FIX** inconsistent examples to always query DeckCard (lines 520-600)

**Priority**: HIGH - Will improve implementation speed significantly

---

### 4. contracts/play_actions.md - Event Contracts

**Status**: 🟢 **GOOD**

**Strengths**:
- Well-defined event payloads
- Clear error codes matching spec.md
- Good request/response flow diagrams
- Security considerations documented
- Testing examples provided

**Minor Issues**:

#### Issue 4.1: Card Notation Format (Line 10)
- Shows payload with `card_notation: "4H"` (string)
- Also shows `cards: ["4H", "4D"]` (array of strings)
- **INCONSISTENT** with spec.md clarification which states array format is required
- Should always use array: `cards: ["4H"]` for single card too

#### Issue 4.2: Missing Reference to PlayValidator
- Validation section (lines 50-60) describes rules but doesn't reference PlayValidator module
- Should say "See quickstart.md Phase 1 for PlayValidator implementation"

**Recommendations**:

1. **CLARIFY** card notation format at top of file:
   ```markdown
   ## Card Notation Protocol
   
   **Format**: JSON array of strings (even for single card)
   - Single card: `["4H"]`
   - Combo: `["4H", "4D", "4S"]`
   - Case-insensitive: "4h" = "4H"
   
   📖 **Reference**: See `spec.md` clarification #1 for notation details
   ```

2. **ADD** cross-reference to PlayValidator (line 55):
   ```markdown
   **Validation** (Server-Side):
   
   📖 **Implementation**: See `quickstart.md` Phase 1 for PlayValidator module
   
   1. Card notation format is valid (e.g., "4H", "5D", "10C")
   2. Player is current player (turn validation via GameSession.current_turn_player_id)
   ...
   ```

**Priority**: MEDIUM - Contracts are mostly good

---

### 5. research.md - Technical Decisions

**Status**: 🟢 **EXCELLENT**

**Strengths**:
- Section 3 correctly references existing recycle implementation
- Clear rationale for decisions
- Good alternatives considered
- Constitution compliance noted

**Minor Issues**:

#### Issue 5.1: TurnManager Decision (Lines 56-80)
- Recommends dedicated TurnManager module
- **INCONSISTENT** with quickstart.md which could inline this logic
- Decision may be overkill for simple sequential turns

#### Issue 5.2: Missing Cross-References
- No forward references to where decisions are implemented
- Should link to quickstart.md phases

**Recommendations**:

1. **ADD** "Implementation Location" to each decision:
   ```markdown
   ### 1. Card Play Validation Strategy
   
   **Decision**: Pure function-based validation with pattern matching
   
   📍 **Implementation**: See `quickstart.md` Phase 1 - PlayValidator module
   
   [existing content...]
   ```

2. **UPDATE** TurnManager decision (line 56):
   ```markdown
   ### 2. Turn Management
   
   **Decision**: Inline turn logic in CardGames context (simple sequential progression)
   
   **Rationale**:
   - Turn logic is simple: validate current_turn_player_id, get next player
   - Only 2-3 functions needed (get_game_session_players, get_next_player, validate_turn)
   - Inlining reduces module count and makes context function flow clearer
   - Constitution compliance: Avoid unnecessary abstraction
   
   📍 **Implementation**: See `quickstart.md` Phase 2 - Inline helper functions
   
   **Alternatives Considered**:
   - Dedicated TurnManager module: Adds complexity for minimal benefit
   - GenServer for turn state: Overkill for simple sequential progression
   ```

**Priority**: LOW - Research is solid

---

## Schema Inconsistency Summary

| File | Incorrect Reference | Actual Schema | Status |
|------|-------------------|---------------|--------|
| data-model.md:150 | `played_stack` array field | DeckCard.location_type | 🔴 CRITICAL |
| data-model.md:298 | `game_session.current_turn` integer | `current_turn_player_id` UUID | 🔴 CRITICAL |
| data-model.md:305 | `game_session_player.turn_order` | `inserted_at` timestamp | 🔴 CRITICAL |
| data-model.md:312 | `game_session_player.hand` array | DeckCard queries | 🔴 CRITICAL |
| quickstart.md:318 | TurnManager uses `current_turn` | Should use `current_turn_player_id` | 🔴 CRITICAL |
| quickstart.md:335 | TurnManager uses `turn_order` | Should use `inserted_at` | 🔴 CRITICAL |
| contracts.md:10 | Inconsistent card notation | Should always be array | 🟡 MINOR |

---

## Missing Cross-References Map

### What Developers Need to Know

When implementing **Phase 0** (Database):
- ❌ MISSING: Reference to docs/database-relationships.md for order_index semantics
- ❌ MISSING: Reference to existing DeckCard validation rules

When implementing **Phase 1** (PlayValidator):
- ❌ MISSING: Reference to spec.md FR-002, FR-003, FR-004 for rules
- ❌ MISSING: Reference to data-model.md validation section
- ❌ MISSING: Reference to contracts.md for error codes

When implementing **Phase 2** (Turn Logic):
- ❌ MISSING: Reference to research.md decision on turn management
- ❌ MISSING: Reference to actual schema fields (current_turn_player_id, inserted_at)

When implementing **Phase 3** (Context):
- ❌ MISSING: Reference to contracts.md for event payloads
- ❌ MISSING: Reference to data-model.md for state transitions
- ❌ MISSING: Reference to existing draw_card_from_deck/2 and recycle_played_stack/1

When implementing **Phase 4** (LiveView):
- ⚠️ VAGUE: "See contracts/play_actions.md" but no specific line numbers
- ❌ MISSING: Reference to specific error codes to implement
- ❌ MISSING: Reference to PubSub broadcast patterns

---

## Recommended Action Plan

### Immediate (Before Implementation Starts)

1. **FIX data-model.md** (30 minutes)
   - Remove played_stack array migration
   - Fix TurnManager examples to use actual schema
   - Fix state transition examples to use DeckCard queries
   - Add reference to docs/database-relationships.md

2. **UPDATE quickstart.md** (20 minutes)
   - Change Phase 2 from TurnManager module to inline helpers
   - Add cross-references to all phases (see recommendations above)
   - Fix any remaining schema inconsistencies

3. **COMPLETE plan.md** (15 minutes)
   - Fill in feature-specific details
   - Update technical context
   - Add actual project structure

### Nice to Have (Can Do During Implementation)

4. **ENHANCE contracts.md** (10 minutes)
   - Add card notation format section at top
   - Add cross-references to PlayValidator

5. **UPDATE research.md** (10 minutes)
   - Add implementation location pointers
   - Revise TurnManager decision

---

## Validation Checklist

Before marking this feature "ready for implementation":

- [ ] plan.md has feature-specific content (not template)
- [ ] data-model.md uses only existing schema fields
- [ ] data-model.md migration adds ONLY top_card_id (not played_stack array)
- [ ] quickstart.md Phase 2 uses inline helpers (not TurnManager module)
- [ ] quickstart.md has cross-references in all phases
- [ ] All examples use current_turn_player_id (not current_turn integer)
- [ ] All examples use inserted_at for ordering (not turn_order field)
- [ ] All examples query DeckCard for hands (not hand arrays)
- [ ] contracts.md clarifies card notation format
- [ ] research.md matches quickstart.md approach

---

## Estimated Fix Time

- **Critical Fixes**: 1 hour (data-model.md, quickstart.md Phase 2)
- **Cross-References**: 30 minutes (add references throughout)
- **Plan Completion**: 15 minutes (fill in plan.md)
- **Polish**: 20 minutes (contracts, research updates)

**Total**: ~2 hours to make documentation implementation-ready

---

## Conclusion

The implementation documentation has **good structure and thorough coverage** but suffers from:

1. **Schema inconsistencies** that would cause implementation failures
2. **Missing cross-references** that would slow down developers
3. **Incomplete plan.md** that doesn't provide feature overview

With 2 hours of focused updates, this documentation would be **excellent** and significantly speed up implementation.

**Recommendation**: Fix critical issues before starting implementation to avoid:
- Writing code that doesn't work with actual schema
- Creating unnecessary modules (TurnManager)
- Implementing duplicate tracking (played_stack array)
- Constantly context-switching between files to find information

---

**Next Steps**: Review this audit with the team and prioritize fixes.
