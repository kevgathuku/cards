# Clarification Session Results

**Date**: 2025-11-04  
**Feature**: 003-pick-card-from-deck  
**Status**: ✅ Complete

## Summary

All critical clarifications have been answered and the specification has been updated accordingly. The feature scope has been simplified by deferring deck recycling to a separate feature.

## Answers Received

| Question | Answer | Impact |
|----------|--------|--------|
| Q1.1: Turn order | By join time (`inserted_at`) | Added explicit ordering requirement |
| Q1.2: Turn wrapping | Yes, wraps around | Confirmed expected behavior |
| Q2.1: Empty deck options | Can still play from hand | Clarified drawing is optional |
| Q2.3: Empty deck handling | Hide "Draw Card" button | Simplified from error handling |
| Q3.1: UI update pattern | Disabled button, update via broadcast | Different from start_game pattern |
| Q7.1: Hand size limit | No limit | No validation needed |
| Q7.2: Actions per turn | Draw OR play, then auto-advance | Added FR-010 |
| Q5.2: Button label | "Draw Card" | Updated all references |

## Scope Changes

### Feature 003 (This Feature)
**Original**: Draw card with error handling for empty deck  
**Updated**: Draw card with button hiding when empty  
**Complexity**: REDUCED ✅

### Feature 004 (New Future Feature)
**Deferred**: Deck recycling from played stack  
**Reason**: Complex enough to warrant separate feature  
**Status**: Stub created at `specs/004-recycle-played-stack/spec.md`

## Critical Bug Identified

**Issue**: `get_game_session_players/1` has no explicit ordering  
**Impact**: Turn order is non-deterministic  
**Fix**: Add `order_by: [asc: gsp.inserted_at]` to query  
**Tracking**: Will be fixed in Phase 0 research

## Files Updated

1. ✅ `spec.md` - Updated with all clarifications
2. ✅ `clarifications.md` - Marked as resolved with answers
3. ✅ `004-recycle-played-stack/spec.md` - Created stub for future feature

## Next Steps

1. ✅ Specification is complete and ready for implementation
2. ⏳ Proceed to Phase 0: Research
3. ⏳ Fix `get_game_session_players/1` ordering bug
4. ⏳ Implement feature 003
5. ⏳ Plan feature 004 after 003 is complete

---

**Clarification Quality**: Excellent - all critical questions answered decisively  
**Spec Quality After Updates**: 9.5/10 - Clear, focused, ready to implement
