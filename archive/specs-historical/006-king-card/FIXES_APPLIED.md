# Implementation Detail Fixes Applied

**Date**: 2025-11-07  
**Branch**: `006-king-card`  
**Based on**: `audit.md` findings

## Summary

Fixed all critical issues identified in the audit by:
1. Removing outdated optimistic locking references
2. Adding concrete file paths and line numbers
3. Adding cross-references between all artifacts
4. Adding concrete code examples with integration points
5. Adding detailed metadata examples with neutral flag and cardless scenarios

---

## Files Updated

### 1. quickstart.md ✅
**Issues Fixed**:
- ❌ **REMOVED**: All `lock_version` migration references
- ❌ **REMOVED**: Section §10 "Retry Strategy" 
- ✅ **ADDED**: Explicit 5-phase implementation sequence with dependencies
- ✅ **ADDED**: File paths and line numbers for every change
- ✅ **ADDED**: Complete Elixir code snippets (not pseudo-code)
- ✅ **ADDED**: Cross-references using § notation to other docs
- ✅ **ADDED**: Integration points with existing code locations

**New Structure**:
```
§1. Migrations (with templates and file paths)
§2. Schemas (exact line numbers to modify)
§3. King Logic (line-by-line integration points)
§4. Cardless Handling (transaction structure)
§5. Telemetry (helper functions and attachment)
§6. LiveView UI (assigns, indicators, toast)
§7. Tests (complete test suites)
§8. i18n Keys (gettext entries)
§9. Anomaly Handling (deck exhaustion guard)
§10. Deployment (pre/post checklist)
```

**Key Improvements**:
- Migration §1.1 references template: `20251107172808_add_top_card_to_game_sessions.exs`
- Schema §2.1 specifies "after line 8, after `status` field"
- Validator §3.1 specifies "add after line 44, before `player_has_cards?/2`"
- execute_play §3.3 says "replace lines 571-615"
- All functions now include FR references (e.g., "FR-002", "FR-009")

### 2. plan.md ✅
**Issues Fixed**:
- ✅ **ADDED**: File paths with line numbers to "Derived Components"
- ✅ **ADDED**: Cross-references to quickstart.md sections (e.g., "see quickstart.md §3.1")
- ✅ **ADDED**: Existing code locations (e.g., "line 697", "lines 415-465")
- ✅ **ADDED**: References to research.md sections for each resolved question

**Example Changes**:
```markdown
Before:
- `Kadi.Games.PlayValidator`: extend or add function `validate_king_play/3`

After:
- `Kadi.Games.PlayValidator` (`lib/kadi/games/play_validator.ex`, lines 1-107): 
  extend with `valid_king_play?/3` function → see quickstart.md §3.1
```

### 3. data-model.md ✅
**Issues Fixed**:
- ❌ **REMOVED**: References to optimistic locking / `lock_version` as required
- ✅ **CLARIFIED**: `lock_version` marked as "optional/dormant"
- ✅ **ADDED**: File paths for all schema references
- ✅ **ADDED**: Cross-references to quickstart.md sections
- ✅ **ADDED**: Migration directory path and naming convention
- ✅ **ADDED**: Template references (existing migration files)
- ✅ **ADDED**: Events.md references for error atoms

**Example Changes**:
```markdown
Before:
Migration A: Alter game_sessions add direction...

After:
Migration A: Add `direction` field to `game_sessions`
- File: `YYYYMMDDHHMMSS_add_direction_to_game_sessions.exs`
- Fields: `direction` (string, default 'clockwise', NOT NULL)
- Constraint: CHECK `direction IN ('clockwise','counter_clockwise')`
- Template: See `priv/repo/migrations/20251107172808_add_top_card_to_game_sessions.exs`
```

### 4. research.md ✅
**Issues Fixed**:
- ✅ **ADDED**: File paths and line numbers for all referenced code
- ✅ **ADDED**: Implementation references to quickstart.md sections
- ✅ **ADDED**: Existing function locations (e.g., `validate_current_turn/2` at line 715)
- ✅ **ADDED**: Cross-references to contracts/events.md

**Example Changes**:
```markdown
Before:
Decision: Extend PlayValidator with King validation

After:
Decision: Extend existing `Kadi.Games.PlayValidator` with King-specific clauses.
File: `lib/kadi/games/play_validator.ex` (current: lines 1-107)
Implementation: Add `valid_king_play?/3` function after line 44 (see quickstart.md §3.1)
```

### 5. contracts/events.md ✅
**Issues Fixed**:
- ✅ **ADDED**: Detailed metadata structure examples
- ✅ **ADDED**: `neutral` flag explanation and 2-player example
- ✅ **ADDED**: `cardless_entered` reason field and multiple player scenario
- ✅ **ADDED**: Assign structure examples with types
- ✅ **ADDED**: Error response format examples
- ✅ **ADDED**: Cross-references to quickstart.md and spec.md

**New Sections**:
```markdown
### Metadata Details
- direction_change: Full example with neutral=true for 2-player
- cardless_entered: Multiple simultaneous cardless players note
- anomaly_skip: Deck state description

### Assign Examples
- direction: Simple string value usage
- toast: Structure with updated_at for coalescing
- player_statuses: Map showing multiple cardless players
- banner: Anomaly notification structure
```

---

## Cross-Reference Summary

All documents now properly reference each other:

### From spec.md:
- FR requirements → implementation in quickstart.md §N

### From plan.md:
- Derived components → files, line numbers, quickstart.md sections
- Open questions → research.md sections

### From research.md:
- Decisions → implementation files with line numbers
- Best practices → quickstart.md sections

### From data-model.md:
- Schemas → file paths, quickstart.md sections
- Migrations → templates, naming conventions
- Events → contracts/events.md sections
- Error atoms → contracts/events.md error table

### From quickstart.md:
- Every section → spec.md FR references
- Every implementation → existing code line numbers
- Migrations → data-model.md specs
- Telemetry → contracts/events.md schemas
- Tests → spec.md success criteria

### From contracts/events.md:
- Events → quickstart.md implementation sections
- Metadata → spec.md FR requirements
- Error atoms → spec.md FR references

---

## Validation Checklist

- [x] All `lock_version` / optimistic locking references removed
- [x] All "Retry Strategy" references removed  
- [x] Every schema change has file path and line numbers
- [x] Every function addition has integration point location
- [x] Every implementation step references spec.md FRs
- [x] Every decision references research.md rationale
- [x] Migration naming convention documented
- [x] Migration templates referenced
- [x] Telemetry metadata fully documented
- [x] LiveView assign structures documented
- [x] Error payloads documented
- [x] Neutral flag explained with 2-player example
- [x] Cardless metadata detailed with multi-player example
- [x] Test patterns included with examples
- [x] Deployment sequence specified

---

## Next Steps

The implementation details are now ready for coding. Follow this sequence:

1. **Start with quickstart.md** - it's now the complete implementation guide
2. **Reference plan.md** for high-level context
3. **Check data-model.md** for schema details
4. **Use research.md** for design rationale when questions arise
5. **Follow contracts/events.md** for exact event/assign structures
6. **Keep audit.md** as the detailed cross-reference guide

All critical audit findings have been addressed. The documentation now provides:
- Clear sequencing with dependencies
- Exact file locations and line numbers
- Concrete code examples
- Complete cross-references
- No outdated concepts (optimistic locking removed)
