# Implementation Plan: Basic Gameplay - Regular Cards

**Branch**: `005-basic-gameplay` | **Date**: 2025-11-06 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-basic-gameplay/spec.md`

## Summary

Implement basic gameplay mechanics for regular cards (4, 5, 6, 7, 9, 10) with play and draw actions. Players must match suit or rank of the top card on the played stack. Supports single card plays and combo plays (multiple cards with same rank). When no valid play exists, player draws from deck. Leverages existing features: 003-pick-card-from-deck (draw_card_from_deck/2) and 004-recycle-played-stack (recycle_played_stack/1) for automatic deck recycling.

**Key Requirements**: Turn-based validation, atomic state updates via Ecto.Multi, real-time updates via Phoenix.PubSub, <100ms play validation performance target.

## Technical Context

**Language/Version**: Elixir 1.17+ with OTP 28  
**Primary Dependencies**: Phoenix 1.7.21, Phoenix LiveView 1.1+, Ecto 3.10+, PostgreSQL  
**Storage**: PostgreSQL with DeckCard location tracking (location_type: "deck" | "played_stack" | "player_hand")  
**Testing**: ExUnit with async tests, Phoenix.LiveViewTest for integration  
**Target Platform**: Web (Phoenix LiveView with real-time updates)  
**Project Type**: Web application (Phoenix MVC + LiveView)  
**Performance Goals**: <100ms play validation and state updates, real-time broadcast to all players  
**Constraints**: Turn-based (only current player can play), atomic transactions (Ecto.Multi), card conservation (52 cards total)  
**Scale/Scope**: 2-4 players per game, 6 regular card types (4,5,6,7,9,10), full 52-card deck

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

✅ **Code Quality Principles**: Pattern matching for validation, pure functions (PlayValidator), context boundaries respected  
✅ **Testing Standards**: All context functions will have tests, critical paths (play validation, turn advancement) 100% coverage  
✅ **Performance**: Ecto.Multi for batch operations, preloading to avoid N+1, indexed queries  
✅ **Security**: Server-side validation, turn checking, player hand verification  
✅ **Feature Reuse**: Integrates with existing draw_card_from_deck/2 (003) and recycle_played_stack/1 (004)  
✅ **Schema Verification**: Actual schema reviewed (current_turn_player_id, location_type, inserted_at for turn order)

**No violations** - All requirements align with constitution principles.

## Project Structure

### Documentation (this feature)

```text
specs/005-basic-gameplay/
├── plan.md              # This file
├── spec.md              # Feature specification with 14 clarifications
├── research.md          # Phase 0 - Technical decisions (8 decisions)
├── data-model.md        # Phase 1 - Data model (uses existing schema + top_card_id)
├── quickstart.md        # Phase 1 - Implementation guide (5 phases)
├── contracts/           # Phase 1 - Event contracts
│   └── play_actions.md  # LiveView event handlers
└── AUDIT.md             # Documentation audit results
```

### Source Code (repository root)

```text
lib/
├── kadi/
│   ├── card_games.ex            # MODIFY: Add play_cards/3, inline turn helpers
│   └── games/
│       ├── game_session.ex      # MODIFY: Add belongs_to :top_card
│       ├── play_validator.ex    # NEW: Pure validation functions
│       ├── deck_card.ex         # EXISTING: location_type tracking
│       ├── card.ex              # EXISTING: Card schema
│       └── deck.ex              # EXISTING: Deck schema
│
├── kadi_web/
│   └── live/
│       └── game_live/
│           ├── show.ex          # MODIFY: Add play_cards, draw_card handlers
│           └── show.html.heex   # MODIFY: Add play/draw UI
│
test/
├── kadi/
│   ├── card_games_test.exs      # MODIFY: Add play_cards tests
│   └── games/
│       └── play_validator_test.exs  # NEW: Validation logic tests
│
└── kadi_web/
    └── live/
        └── game_live/
            └── show_test.exs    # MODIFY: Add LiveView integration tests

priv/repo/migrations/
└── XXXXXX_add_top_card_to_game_sessions.exs  # NEW: Add top_card_id field
```

**Structure Decision**: Standard Phoenix web application structure. New PlayValidator module in games namespace. No TurnManager module needed - turn logic inlined in CardGames context as private helpers. Leverages existing draw_card_from_deck/2 and recycle_played_stack/1 functions.

---

## Key Design Decisions

### Decision: Add `top_card_id` Field to GameSession

**Status**: ✅ Approved  
**Date**: 2025-11-06

**Context**: The top card of the played stack can be derived by querying `DeckCard WHERE location_type='played_stack' ORDER BY order_index DESC LIMIT 1`. However, play validation requires checking the top card on every turn (hot path).

**Decision**: Add `top_card_id` foreign key field to `game_sessions` table, maintained atomically during play transactions.

**Rationale**:

1. **Performance Optimization** (Primary)
   - Direct field access via preload vs query + sort operation
   - Validation happens every turn (hot path)
   - Helps meet <100ms play validation target (Constitution requirement)
   - Indexed foreign key lookup faster than ORDER BY on large played piles

2. **Code Simplicity**
   - Cleaner validation: `PlayValidator.valid_play?(cards, game_session.top_card)`
   - Self-documenting: schema explicitly models "current top card" concept
   - Less query complexity in context layer

3. **Consistency Guarantees**
   - Updated atomically in same Ecto.Multi transaction as card moves
   - No risk of stale reads between play and next validation
   - Easier to reason about game state

4. **Future-Proofing**
   - Special cards (8s, jacks, 2s in future features) will need top_card frequently
   - Pattern established for expansion

**Tradeoffs Considered**:

| Aspect | With top_card_id | Without (query-based) |
|--------|------------------|----------------------|
| **Performance** | ✅ Fast (index seek) | ⚠️ Slower (sort operation) |
| **Validation Speed** | ✅ ~5-10ms | ⚠️ ~15-25ms |
| **Write Overhead** | ⚠️ +1 field update | ✅ None |
| **Data Redundancy** | ⚠️ Derivable from DeckCard | ✅ Single source of truth |
| **Consistency Risk** | ⚠️ Must update atomically | ✅ Always correct |
| **Code Complexity** | ✅ Simpler validation | ⚠️ Extra query logic |
| **Schema Changes** | ⚠️ Migration required | ✅ No change |
| **Future Maintenance** | ⚠️ Update in all play paths | ✅ Automatic |

**Implementation Strategy**:
```elixir
# Atomic update in all play transactions
Multi.new()
|> Multi.update(:move_cards, deck_card_changesets)
|> Multi.update(:game_session, GameSession.changeset(game, %{
     top_card_id: last_played_card_id,
     current_turn_player_id: next_player_id
   }))
|> Repo.transaction()
```

**Safety Measures**:
- Database constraint: `FOREIGN KEY (top_card_id) REFERENCES cards(id) ON DELETE SET NULL`
- Test helper for verification: `verify_top_card_consistency/1`
- Ecto.Multi ensures atomicity (no partial updates)

**Implementation Details** (Updated 2025-11-07):
- ✅ `top_card_id` set when game starts via `start_game/1` function
- ✅ `top_card_id` updated on every card play via `execute_play/3` function
- ✅ `get_top_card/1` simplified to remove fallback logic (no longer needed)
- ✅ Preloaded via `:top_card` association in `get_game_session_preloaded/1`
- ✅ Test coverage added to verify top_card_id is set on game start

**Rejected Alternative**: Query-based approach
- **Why Rejected**: Performance overhead on hot path (every turn validation)
- **When Reconsidered**: If <100ms target consistently met without field, or if consistency bugs emerge
- **Fallback**: Keep query helper function for debugging/repair

**Acceptance Criteria**:
- ✅ top_card_id updated atomically with every play
- ✅ Validation uses top_card_id (no additional queries)
- ✅ Initial start card sets top_card_id
- ✅ Test coverage for consistency maintenance
- ✅ Performance: play validation <100ms (as per Constitution)

**References**:
- Constitution Section 4.1: Database Performance (<50ms queries, indexed lookups)
- data-model.md: Required Schema Changes section
- quickstart.md: Phase 0 migration implementation

---

## Complexity Tracking

> **No violations to justify** - Feature aligns with constitution principles.

**Feature Reuse**: 
- ✅ Uses existing draw_card_from_deck/2 from feature 003
- ✅ Uses existing recycle_played_stack/1 from feature 004
- ✅ No duplication of existing functionality

**Schema Changes**:
- ✅ Minimal: Only adds top_card_id to game_sessions
- ✅ No new tables needed
- ✅ Leverages existing DeckCard.location_type for played stack tracking

**Module Count**:
- ✅ One new module: PlayValidator (pure functions)
- ✅ No TurnManager - logic inlined as helpers
- ✅ Modifications to existing CardGames context

---

## Implementation Phases

### Phase 0: Research & Technical Decisions
**Status**: ✅ Complete - See research.md  
**Output**: 8 technical decisions documented  
**Key Decisions**: Pure function validation, inline turn logic, reuse existing draw/recycle, Ecto.Multi for atomicity

### Phase 1: Design
**Status**: ✅ Complete - See data-model.md, quickstart.md, contracts/  
**Output**: Data model (1 migration), implementation guide (5 phases), event contracts (4 events)  
**Key Artifacts**: 
- Migration for top_card_id
- PlayValidator module spec
- Turn helper functions spec
- LiveView event handlers spec

### Phase 2: Implementation
**Status**: 🔲 Not Started  
**Estimated**: ~12 hours  
**Phases**:
1. Database schema (15 min) - Add top_card_id migration
2. PlayValidator module (2 hrs) - Pure validation logic
3. Turn helpers (30 min) - Inline in CardGames context
4. Context functions (3 hrs) - play_cards/3 with Ecto.Multi
5. LiveView integration (4 hrs) - Event handlers and UI
6. Testing (2 hrs) - Unit, integration, LiveView tests

### Phase 3: Tasks Generation
**Status**: 🔲 Not Started  
**Command**: `/speckit.tasks` (after Phase 2 completion)  
**Output**: tasks.md with implementation checklist

---

## Dependencies

### Feature Dependencies
- **003-pick-card-from-deck**: Provides draw_card_from_deck/2 function
- **004-recycle-played-stack**: Provides recycle_played_stack/1 function
- Both are already implemented and tested

### External Dependencies
- Phoenix 1.7.21 (web framework)
- Phoenix LiveView 1.1+ (real-time UI)
- Ecto 3.10+ (database)
- PostgreSQL (storage)

---

## Risk Assessment

### Technical Risks
- **Race conditions on concurrent plays**: Mitigated by Ecto.Multi atomic transactions
- **Turn validation bypass**: Mitigated by server-side validation only
- **Performance on broadcast**: Mitigated by targeted PubSub topics (per game)

### Implementation Risks
- **Schema confusion**: ⚠️ MITIGATED - Audit completed, schema verified
- **Missing test coverage**: Mitigated by TDD approach in quickstart
- **LiveView complexity**: Mitigated by detailed contracts documentation

---

## Success Criteria

1. ✅ Players can play single cards matching suit or rank
2. ✅ Players can play combo cards (same rank, first card must match)
3. ✅ Players can draw when no valid play exists
4. ✅ Deck automatically recycles when empty
5. ✅ Turn advances after play or draw
6. ✅ All players see updates in real-time (<100ms)
7. ✅ Invalid plays rejected with clear error messages
8. ✅ Test coverage >90% for core logic
9. ✅ All existing tests still pass

---

## Next Steps

1. Review this plan with team
2. Begin Phase 2 implementation following quickstart.md
3. Start with Phase 2.0 (database migration)
4. Proceed sequentially through phases
5. Run tests after each phase
6. Generate tasks.md after implementation complete

---

## References

- [Feature Specification](./spec.md) - 26 functional requirements
- [Research](./research.md) - 8 technical decisions
- [Data Model](./data-model.md) - Schema and validation rules
- [Quickstart](./quickstart.md) - Step-by-step implementation
- [Contracts](./contracts/play_actions.md) - LiveView events
- [Constitution](/.specify/memory/constitution.md) - Project standards
- [Database Relationships](../../docs/database-relationships.md) - Schema reference
