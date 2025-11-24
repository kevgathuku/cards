# Research: Jack Card Implementation

**Feature**: 007-jack-card  
**Date**: 2025-11-08  
**Status**: Complete

## Overview

Research findings for implementing Jack card as a "Jump" special card that skips N players in turn order. This research resolves all technical unknowns identified in the Technical Context section.

## Decisions Made

### Decision 1: Skip Calculation Algorithm

**Context**: Need to determine which player receives turn after N players are skipped, handling wrap-around.

**Decision**: Reuse and extend existing `get_next_player_with_direction/3` function with skip count parameter.

**Rationale**:
- Existing function already handles direction (clockwise/counter_clockwise)
- Already handles wrap-around using `rem/2`
- Consistent with King card implementation pattern
- Minimal code duplication

**Implementation approach**:
```elixir
# Current (for King - 1 skip):
get_next_player_with_direction(players, current_player_id, direction)

# Enhanced (for Jack - N skips):
get_next_player_with_direction(players, current_player_id, direction, skip_count \\ 1)

# Algorithm:
# 1. Find current player index in ordered list
# 2. Calculate offset: (clockwise: +skip_count, counter_clockwise: -skip_count)
# 3. Apply modulo: rem(current_index + offset, player_count)
# 4. Handle negative wrap: if result < 0, add player_count
```

**Alternatives considered**:
- Create separate `skip_n_players/4` function → Rejected: Duplicates direction/wrap logic
- Loop N times calling existing function → Rejected: Less efficient, harder to test

---

### Decision 2: Jack Validation Pattern

**Context**: Need to validate Jack plays following existing patterns.

**Decision**: Create dedicated `valid_jack_play?/2` function in PlayValidator module, parallel to `valid_king_play?/2`.

**Rationale**:
- Maintains consistency with King card validation pattern
- Isolates Jack-specific rules for easy testing
- Allows future Jack rule modifications without affecting other validations
- Clear separation of concerns

**Implementation approach**:
```elixir
defmodule Kadi.Games.PlayValidator do
  # Existing for King:
  def valid_king_play?([%{rank: "king"} = king], top_card), do: matches_suit_or_rank?(king, top_card)
  def valid_king_play?([%{rank: "king"} | _rest], _top_card), do: false  # Combo rejected
  
  # New for Jack:
  def valid_jack_play?([], _top_card), do: false
  def valid_jack_play?(_cards, nil), do: false
  
  def valid_jack_play?(cards, top_card) when is_list(cards) do
    all_jacks?(cards) and first_card_matches?(cards, top_card)
  end
  
  defp all_jacks?(cards), do: Enum.all?(cards, &(&1.rank == "jack"))
end
```

**Alternatives considered**:
- Handle Jack in general combo validation → Rejected: Mixes special card rules with regular cards
- Create generic `valid_special_card_play?/3` → Rejected: Over-abstraction, each special card has unique rules

---

### Decision 3: Cardless State Integration

**Context**: Jack as last card enters cardless state instead of winning. Need to integrate with existing cardless system.

**Decision**: Reuse existing cardless detection and status update logic from King implementation, modify condition to check for Jack.

**Rationale**:
- Cardless state infrastructure already exists from Feature 006 (King card)
- `GameSessionPlayer` schema already has `status` field with "cardless" value
- Telemetry events (`[:kadi, :jack, :cardless_entered]`) follow same pattern
- Auto-draw on turn arrival already implemented

**Implementation approach**:
```elixir
# In execute_play/3:
jack_played? = Enum.any?(cards_to_play, &(&1.rank == "jack"))
will_be_cardless = player_hand == cards_played_count and jack_played?

# Reuse existing logic:
if will_be_cardless do
  # Update game_session_player status to "cardless"
  # Emit telemetry: [:kadi, :jack, :cardless_entered]
end
```

**Alternatives considered**:
- Create separate "jack_cardless" status → Rejected: Unnecessary complexity, cardless is cardless regardless of cause
- Skip cardless state, handle in UI → Rejected: Violates server-authoritative game state principle

---

### Decision 4: Starting Card Behavior

**Context**: Jack can be selected as starting card but should not trigger skip effect at game start.

**Decision**: Add conditional check in `start_game/1` to skip Jack effect application when dealing starting card.

**Rationale**:
- King already has similar logic (starting King doesn't reverse direction)
- Clean separation: card selection vs. card play effects
- Maintains game start predictability

**Implementation approach**:
```elixir
# In start_game/1, after selecting start card:
# Kings are allowed as start cards (no direction reversal occurs) - FR-003 from feature 006
# Jacks are allowed as start cards (no skip effect occurs) - FR-015 from feature 007
# Only special effect triggering is prevented; cards themselves are valid start cards
```

**Alternatives considered**:
- Exclude Jack from start card pool → Rejected: Spec explicitly allows Jack as start card
- Apply skip effect at start → Rejected: Confusing UX, unpredictable first turn

---

### Decision 5: Telemetry Event Structure

**Context**: Need to emit telemetry for Jack plays to maintain observability consistent with King card.

**Decision**: Create telemetry events under `[:kadi, :jack, ...]` namespace following King pattern.

**Events to emit**:
1. `[:kadi, :jack, :skip_executed]` - When Jack skip happens
   - Metadata: `game_session_id`, `player_id`, `skip_count`, `from_player_id`, `to_player_id`, `jack_count`, `card_ids`
   
2. `[:kadi, :jack, :cardless_entered]` - When Jack causes cardless state
   - Metadata: `game_session_id`, `player_id`, `card_id`, `reason: "jack_last_card"`

**Rationale**:
- Consistent with existing King events (`[:kadi, :king, :direction_change]`, `[:kadi, :king, :cardless_entered]`)
- Enables metrics, monitoring, debugging
- Supports future analytics (most skipped player, Jack combo frequency)

**Alternatives considered**:
- Generic `[:kadi, :special_card, :effect]` → Rejected: Loses card-specific granularity
- No telemetry → Rejected: Violates observability standards

---

## Best Practices Researched

### Elixir/Phoenix Patterns

**Pattern 1: Multi-step Transaction with Ecto.Multi**
- Use for atomic skip + cardless + turn update operations
- Reference: King card implementation (`execute_play/3`)
- Ensures consistency if any step fails

**Pattern 2: Pattern Matching for Special Card Detection**
```elixir
# Preferred Elixir idiom:
jack_played? = Enum.any?(cards_to_play, &(&1.rank == "jack"))

# Instead of:
if Enum.find(cards_to_play, fn c -> c.rank == "jack" end) != nil
```

**Pattern 3: Broadcast-Only LiveView Updates**
- Don't update socket in event handler
- Call context function → broadcast → all clients receive update via `handle_info`
- Reference: Existing `play_cards/3` workflow

### Testing Patterns

**Pattern 1: Test Organization**
- Group tests by functional requirement: `describe "Jack skip behavior (FR-002)"` 
- Use clear Given-When-Then structure in test names
- Example: `test "Given 3-player game, When Jack played, Then skips 1 player"`

**Pattern 2: Reuse Test Helpers**
- `player_fixture/1` for creating players
- `CardGames.start_game/1` for consistent game setup
- Avoid testing same scenario multiple times (DRY)

**Pattern 3: Edge Case Coverage**
- Wrap-around scenarios (skip count > player count)
- 2-player games (skip returns to same player)
- Direction interaction (Jack + King combination)
- Cardless player in skip path

---

## Integration Points

### With Feature 006 (King Card)
- **Direction system**: Jack skip respects current direction
- **Cardless state**: Jack reuses existing cardless infrastructure
- **Telemetry**: Jack follows King's event structure
- **Validation**: Jack uses same pattern as King (`valid_jack_play?/2`)

### With Feature 005 (Basic Gameplay)
- **play_cards/3**: Jack integrates into existing play flow
- **Validation**: Uses existing `PlayValidator.valid_play?/2` entry point
- **Turn advancement**: Extends existing `get_next_player_with_direction/3`

### With Feature 003 (Pick Card from Deck)
- **Auto-draw**: Cardless player auto-draws on their turn (existing logic)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Skip calculation bug with wrap-around | Medium | High | Comprehensive edge case tests (2-player, 4 Jacks in 3-player game) |
| Jack+King interaction issues | Low | Medium | Integration tests combining direction reversal + skip |
| Cardless state race condition | Low | High | Ecto.Multi ensures atomic updates |
| Performance with large player counts | Low | Low | Skip calculation is O(1) with modulo arithmetic |

---

## Open Questions

**None** - All clarifications resolved in `/speckit.clarify` phase:
- ✅ Jack as winning card: No, enters cardless state
- ✅ Cardless player in skip count: Not counted
- ✅ Starting card behavior: Allowed, no skip effect
- ✅ Draw amount from cardless: One card
- ✅ Validation pattern: Dedicated function like King

---

## References

- Existing code: `lib/kadi/card_games.ex` (King implementation, lines 654-750)
- Existing code: `lib/kadi/games/play_validator.ex` (King validation, lines 69-97)
- Feature 006 spec: `specs/006-king-card/spec.md`
- Constitution: `.specify/memory/constitution.md` (Section 1.5: Feature Reuse)
