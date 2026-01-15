# Design Document: Question Cards (Q and 8)

## Overview

This design document outlines the implementation approach for Q (Queen) and 8 card mechanics in the Kadi card game. Question cards prompt players to draw unless they include an answer card in the same play, creating strategic combo opportunities.

## Architecture

### High-Level Flow

```
Player plays cards → Validator checks combo → Question cards detected?
                                                    ↓
                                          Yes: Has answer card?
                                                    ↓
                                    Yes: Execute play normally
                                    No: Prompt player to draw
```

### Key Design Decisions

1. **No Persistent State**: Unlike penalty cards, question cards don't create a persistent game state. The prompt to draw is immediate and doesn't survive across plays.

2. **Combo-Based Validation**: Question cards can be played in combos with answer cards in a single play (e.g., `8H 8D 2D`).

3. **Answer Cards Can Be Combos**: Answer cards can themselves be combos (e.g., `8H 8D 4D 4H`).

4. **Q and 8 Cannot Be Answers**: If a play ends with Q or 8, the entire play is treated as questions, prompting a draw.

5. **Normal Matching for Next Player**: After a question card is played and answered (or drawn), the next player plays normally against the top card.

## Components and Interfaces

### 1. PlayValidator Module

**Location**: `lib/kadi/games/play_validator.ex`

**New Functions**:

```elixir
@doc """
Validates a question card combo with optional answer cards.

Returns:
- {:ok, :complete} - Valid combo with answer cards
- {:ok, :incomplete} - Valid question cards without answer, needs draw
- {:error, reason} - Invalid combo
"""
def validate_question_combo(cards, top_card, opts \\ [])

@doc """
Checks if a list of cards are all question cards (Q or 8).
"""
def all_question_cards?(cards)

@doc """
Splits a card list into question cards and answer cards.
Returns {question_cards, answer_cards}.
"""
def split_question_and_answer(cards)

@doc """
Validates that question cards in a combo match each other by suit or rank.
"""
def valid_question_sequence?(question_cards)

@doc """
Validates that answer cards form a valid combo and match the last question card.
"""
def valid_answer_for_question?(answer_cards, last_question_card)
```

**Integration Points**:
- Modify `valid_play?/3` to detect and handle question card combos
- Add question card detection before regular validation
- Ensure Q and 8 are excluded from starting card selection

### 2. CardGames Context

**Location**: `lib/kadi/card_games.ex`

**Modified Functions**:

```elixir
@doc """
Executes a card play, handling question cards specially.

If play contains only question cards, sets a flag to prompt draw.
If play contains question + answer cards, executes normally.
"""
def play_cards(game_session, player_id, card_ids)

@doc """
Draws a card as an answer to a question.
Only callable when player has pending question draw.
"""
def answer_question_by_drawing(game_session, player_id)

@doc """
Selects a starting card, excluding Q and 8 cards.
"""
def select_starting_card(deck_id)
```

**New Fields** (temporary, not persisted):

The question prompt state will be tracked in the LiveView socket, not in the database. This keeps the design simple since the state doesn't need to persist across sessions.

### 3. LiveView Integration

**Location**: `lib/kadi_web/live/game_live.ex`

**Socket Assigns**:

```elixir
socket
|> assign(:pending_question_draw, false)  # True when player needs to draw for question
```

Note: The question suit can be derived from the top card on the played pile, so no separate tracking is needed.

**Event Handlers**:

```elixir
def handle_event("play_cards", %{"card_ids" => card_ids}, socket)
  # Check if play is incomplete question combo
  # If so, set pending_question_draw flag
  # Otherwise, execute play normally

def handle_event("answer_question_draw", _params, socket)
  # Draw one card
  # Clear pending_question_draw flag
  # Advance turn
```

**UI Updates**:
- Show "Draw Card (Answer Question)" button when `pending_question_draw` is true
- Highlight valid answer cards when question is pending
- Display message indicating player must draw

### 4. Database Schema

**No Schema Changes Required**

Question cards don't require persistent state in the database. The prompt to draw is handled entirely in the LiveView layer.

## Data Models

### Card Validation Flow

```elixir
# Example: 8H 8D 2D
cards = [
  %Card{rank: "8", suit: "hearts"},
  %Card{rank: "8", suit: "diamonds"},
  %Card{rank: "2", suit: "diamonds"}
]

# Step 1: Split into questions and answers
{questions, answers} = split_question_and_answer(cards)
# questions = [8H, 8D]
# answers = [2D]

# Step 2: Validate question sequence
valid_question_sequence?(questions)
# Check: 8D matches 8H by rank ✓

# Step 3: Validate answer
valid_answer_for_question?(answers, last_question_card)
# Check: 2D matches 8D by suit ✓

# Result: {:ok, :complete}
```

### Incomplete Question Example

```elixir
# Example: 8H 8D (no answer)
cards = [
  %Card{rank: "8", suit: "hearts"},
  %Card{rank: "8", suit: "diamonds"}
]

# Step 1: Split
{questions, answers} = split_question_and_answer(cards)
# questions = [8H, 8D]
# answers = []

# Step 2: Validate question sequence
valid_question_sequence?(questions)
# Check: 8D matches 8H by rank ✓

# Step 3: Check for answer
answers == []
# Result: {:ok, :incomplete} - prompt player to draw
```

### Question with Answer Combo Example

```elixir
# Example: 8H 8D 4D 4H
cards = [
  %Card{rank: "8", suit: "hearts"},
  %Card{rank: "8", suit: "diamonds"},
  %Card{rank: "4", suit: "diamonds"},
  %Card{rank: "4", suit: "hearts"}
]

# Step 1: Split
{questions, answers} = split_question_and_answer(cards)
# questions = [8H, 8D]
# answers = [4D, 4H]

# Step 2: Validate question sequence
valid_question_sequence?(questions)
# Check: 8D matches 8H by rank ✓

# Step 3: Validate answer combo
valid_answer_for_question?(answers, last_question_card)
# Check: 4D matches 8D by suit ✓
# Check: All answers have same rank (4) ✓

# Result: {:ok, :complete}
```

## Error Handling

### Validation Errors

| Scenario | Error Message | Handling |
|----------|--------------|----------|
| Question cards don't match each other | "Invalid question combo: cards must match by suit or rank" | Reject play, show error |
| Answer doesn't match last question | "Answer must match suit or rank of last question card" | Reject play, show error |
| Answer cards don't form valid combo | "Invalid answer combo: all cards must have same rank" | Reject play, show error |
| First question doesn't match top card | "First card must match top card by suit or rank" | Reject play, show error |
| Player tries to play when draw pending | "You must draw a card to answer the question" | Reject play, show error |

### Edge Cases

1. **Q or 8 at end of combo**: Treat entire play as questions, prompt draw
   - Example: `8H 8D QD` → All questions, prompt draw

2. **Last card is question without answer**: Player must draw, removing cardless status
   - Example: Player plays last card `8H` → Prompt draw → Player has 1 card again

3. **Deck exhaustion during question draw**: Recycle played pile before drawing
   - Use existing `recycle_played_stack/1` function

4. **Multiple question cards with Ace answer**: Ace triggers suit selection after play
   - Example: `8H 8D AH` → Play executes, then suit selection prompt

5. **Multiple question cards with penalty answer**: Penalty activates for next player
   - Example: `8H 8D 2D` → Play executes, next player has penalty

6. **Multiple question cards with Jack answer**: Next player is skipped
   - Example: `8H 8D JD` → Play executes, next player skipped, turn advances to player after

7. **Multiple question cards with King answer**: Game direction is reversed
   - Example: `8H 8D KD` → Play executes, direction reversed, turn advances in new direction

## Testing Strategy

### Unit Tests (PlayValidator)

**File**: `test/kadi/games/play_validator_test.exs`

Test cases:
- Single Q or 8 matching top card
- Multiple Q cards in sequence
- Multiple 8 cards in sequence
- Mixed Q and 8 cards matching by suit/rank
- Question cards with single answer card
- Question cards with answer combo
- Invalid question sequences (cards don't match)
- Invalid answers (wrong suit/rank)
- Q or 8 at end of combo (treated as question)
- Q and 8 excluded from starting card selection

### Integration Tests (CardGames)

**File**: `test/kadi/card_games/special_cards_question_test.exs`

Test cases:
- Play question cards without answer → prompt draw
- Play question cards with answer → execute normally
- Answer question by drawing → turn advances
- Question cards with Ace answer → suit selection triggered
- Question cards with penalty answer → penalty activated
- Question cards with Jack answer → skip triggered
- Question cards with King answer → direction reversed
- Last card is question without answer → draw required
- Deck exhaustion during question draw → recycle works

### LiveView Tests

**File**: `test/kadi_web/live/game_live_test.exs`

Test cases:
- Draw button appears when question pending
- Draw button hidden when no question pending
- Clicking draw button draws card and advances turn
- Playing cards when draw pending is rejected
- UI highlights valid answer cards
- Question banner displays correct suit

### Manual Testing Checklist

- [ ] Play single Q or 8 → prompted to draw
- [ ] Play multiple Q or 8 → prompted to draw once
- [ ] Play Q/8 with answer → no draw prompt, turn advances
- [ ] Play Q/8 with answer combo → works correctly
- [ ] Try to play cards when draw pending → rejected
- [ ] Draw card when prompted → turn advances
- [ ] Play Q/8 as last card without answer → draw required
- [ ] Play Q/8 with answer as last cards → valid finish
- [ ] Next player plays normally after question
- [ ] Deck exhaustion during draw → recycle works

## Integration with Existing Features

### Ace Card (Feature 008)

- Question cards with Ace answer trigger suit selection
- Ace can be used as answer to question cards
- After suit selection, next player follows suit requirement

### Penalty Cards (Features 009, 010)

- Question cards with 2 or 3 answer activate penalty for next player
- Penalty cards can be used as answers to question cards
- Penalty state is independent of question mechanics

### Jack Card (Feature 007)

- Question cards with Jack answer trigger skip effect
- Jack can be used as answer to question cards
- Skip calculation happens after question is answered
- Next player is skipped, turn advances to player after that

### King Card (Feature 006)

- Question cards with King answer trigger direction reversal
- King can be used as answer to question cards
- Direction change happens after question is answered
- Game direction is reversed, turn advances in new direction

### Starting Card Selection

- Q and 8 cards are excluded from starting card selection
- Only regular cards (4, 5, 6, 7, 9, 10) can be starting cards
- Modify `select_starting_card/1` to filter out Q and 8

## Performance Considerations

- Question validation is O(n) where n is number of cards in play
- No database writes for question state (LiveView only)
- Splitting questions and answers is O(n) single pass
- No additional database queries required
- Minimal memory overhead (1 boolean flag in socket)

## Security Considerations

- Validate player owns all cards being played
- Ensure only current turn player can play cards
- Verify player has pending question before allowing draw
- Prevent playing cards when draw is pending
- Use existing authorization checks from CardGames context

## UI/UX Design

### Question Prompt Button

```heex
<%= if @pending_question_draw and @current_player_id == @player_id do %>
  <button
    phx-click="answer_question_draw"
    class="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 pulse-animation"
  >
    Draw Card (Answer Question)
  </button>
<% end %>
```

### Question Banner

```heex
<%= if @pending_question_draw do %>
  <div class="bg-blue-100 border-l-4 border-blue-500 p-4 mb-4">
    <div class="flex items-center">
      <svg class="h-6 w-6 text-blue-500 mr-2" ...>...</svg>
      <p class="text-blue-700">
        Question Active: Draw a card or play a matching card
      </p>
    </div>
  </div>
<% end %>
```

### Card Highlighting

When question is pending, highlight valid answer cards:
- Cards matching the question suit get green border
- Other cards remain unselectable
- Visual feedback helps player identify valid answers

## Migration Strategy

### Phase 1: Validator Implementation
1. Add question card detection functions
2. Implement combo splitting logic
3. Add validation for question sequences
4. Add validation for answer cards
5. Update `valid_play?/3` to handle questions

### Phase 2: Context Integration
1. Modify `play_cards/3` to detect incomplete questions
2. Add `answer_question_by_drawing/2` function
3. Update `select_starting_card/1` to exclude Q and 8
4. Add tests for question card plays

### Phase 3: LiveView Integration
1. Add socket assigns for question state
2. Implement "answer_question_draw" event handler
3. Add UI components (button, banner)
4. Add card highlighting logic
5. Add LiveView tests

### Phase 4: Testing & Polish
1. Run full test suite
2. Manual testing of all scenarios
3. Fix any edge cases discovered
4. Update documentation

## Rollback Plan

If issues are discovered:
1. Question cards can be temporarily disabled by rejecting them in validator
2. No database migrations to rollback
3. LiveView changes can be reverted without data loss
4. Feature can be toggled off with minimal impact

## Future Enhancements

Potential improvements for future iterations:
- Sound effects when question is played
- Animation for question card plays
- Statistics tracking for question card usage
- Tournament mode with question card scoring
- Custom question card rules (game configuration)
- Question card combos with multiple answer types

## Open Questions

None - all requirements have been clarified with the user.

## References

- Requirements: `.kiro/specs/question-cards/requirements.md`
- Ace Card Feature: `docs/ace-card-feature.md`
- Two Card Feature: `docs/two-card-feature.md`
- Three Card Feature: `docs/three-card-feature.md`
- PlayValidator: `lib/kadi/games/play_validator.ex`
- CardGames Context: `lib/kadi/card_games.ex`
