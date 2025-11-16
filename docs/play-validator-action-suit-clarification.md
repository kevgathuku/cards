# PlayValidator Action Suit Clarification

## Overview

The PlayValidator has been refactored to clearly differentiate between two distinct game scenarios involving suit requirements:

## Two Distinct Scenarios

### 1. Regular Ace Play - Requesting a Suit (`:action_suit`)

**When it happens:**
- A player plays an Ace during normal gameplay (no penalty active)
- The Ace player requests a specific suit for the next play

**Behavior:**
- The next player MUST play a card matching the requested suit
- Exception: Playing another Ace overrides the requirement
- ALL cards (including penalty cards 2s and 3s) must match the requested suit

**Example:**
```elixir
# Player plays Ace of Hearts and requests "clubs"
PlayValidator.valid_play?(
  [%Card{suit: "clubs", rank: "5"}],  # Must match clubs
  top_card,
  action_suit: "clubs"
)

# Even penalty cards must match the requested suit
PlayValidator.valid_play?(
  [%Card{suit: "clubs", rank: "2"}],  # 2 of clubs is valid
  top_card,
  action_suit: "clubs"
)

PlayValidator.valid_play?(
  [%Card{suit: "hearts", rank: "2"}],  # 2 of hearts is INVALID
  top_card,
  action_suit: "clubs"
)
```

### 2. Ace Blocks Penalty - Penalty Card Suit Applies (`:penalty_blocked_suit`)

**When it happens:**
- A penalty is active (from a 2 or 3 card)
- A player plays an Ace to block the penalty
- The suit of the blocked penalty card becomes the required suit

**Behavior:**
- The next player should match the penalty card's suit
- BUT penalty cards (2s and 3s) can bypass this by matching rank
- This allows chaining penalty blocks

**Example:**
```elixir
# Ace blocked a 2 of Hearts penalty
PlayValidator.valid_play?(
  [%Card{suit: "diamonds", rank: "2"}],  # Can play another 2 (rank match)
  %Card{suit: "hearts", rank: "ace"},    # Top card is the Ace
  penalty_blocked_suit: "hearts"         # Suit of the blocked 2
)
```

## Key Differences

| Aspect | `:action_suit` | `:penalty_blocked_suit` |
|--------|----------------|-------------------------|
| **Origin** | Regular Ace play | Ace blocking a penalty |
| **Purpose** | Request specific suit | Preserve penalty card's suit |
| **Penalty Card Bypass** | NO - All cards must match suit | YES - Penalty cards can match by rank |
| **Regular Cards** | Must match suit exactly | Must match suit exactly |

## Implementation Details

### New Helper Functions

The refactoring introduced specialized validation functions:

1. **`validate_single_card/3`** - Regular cards with action_suit
2. **`validate_penalty_card/3`** - Penalty cards with penalty_blocked_suit
3. **`validate_regular_or_penalty_card/4`** - Penalty cards in regular gameplay
4. **`validate_penalty_combo/3`** - Penalty card combos blocking penalties
5. **`validate_combo_with_penalty_bypass/4`** - Penalty combos bypassing action_suit

### Code Organization

The code is now organized into clear sections:
- Card Type Checkers
- Single Card Validation
- Combo Validation
- Helper Functions
- First Card Matching (for combos)

## Backward Compatibility

The refactoring maintains full backward compatibility:
- Existing tests pass without modification
- The `:action_suit` option still works as before
- The new `:penalty_blocked_suit` option is optional
- When both are provided, `penalty_blocked_suit` takes priority

### Legacy Behavior Detection

For backward compatibility with existing code that uses `:action_suit` for both scenarios:
- If `:action_suit` is set and the top card is an Ace, the validator assumes this is a penalty block scenario
- In this case, penalty cards (2s and 3s) can match by rank (legacy behavior)
- This allows existing code to work while new code can use `:penalty_blocked_suit` for clarity

## Future Usage

When implementing the CardGames module updates (Task 4), use:
- `:action_suit` when an Ace is played in regular gameplay
- `:penalty_blocked_suit` when an Ace blocks a penalty

This makes the code intent clear and easier to maintain.
