# Design Document: Three Card Draw Penalty

## Overview

This design implements the "3 card" special card mechanic for the Kadi card game, following the same architectural patterns established by the 2 card feature (spec 009). The 3 card forces the next player to draw 3 cards from the deck as a penalty, which can be blocked by playing an Ace or another 3 card. The key distinction from the 2 card is that **2 cards and 3 cards are not compatible** - they cannot block each other's penalties.

### Design Principles

- **Database-Driven State**: All penalty state persists in PostgreSQL via the existing `game_sessions.draw_penalty` map field
- **Reuse Existing Infrastructure**: Leverage the penalty system already built for 2 cards
- **Broadcast-Only Updates**: LiveView handlers trigger database changes and rely on PubSub broadcasts for UI updates
- **Atomic Transactions**: Use `Ecto.Multi` for all state changes to ensure consistency
- **Pure Validation Logic**: Keep validation logic side-effect free in `PlayValidator` module

## Architecture

### High-Level Flow

```
Player plays 3 card
    ↓
CardGames.play_cards/3 validates and applies penalty
    ↓
Database transaction updates game_session.draw_penalty
    ↓
PubSub broadcasts game_updated event
    ↓
All connected LiveViews receive broadcast and update UI
    ↓
Next player sees "Draw 3 Cards" button or can play blocking card
```

### Key Architectural Decisions

1. **Reuse draw_penalty field**: The existing `draw_penalty` map in `game_sessions` table already supports variable penalty counts. No schema changes needed.

2. **Penalty Type Tracking**: Add a `penalty_type` field to the `draw_penalty` map to distinguish between "two" and "three" penalties. This enables validation that prevents cross-blocking.

3. **Validation Layer**: Extend `PlayValidator` to check penalty type when validating blocking cards.

4. **Starting Card Exclusion**: Update the starting card selection logic to exclude both 2s and 3s.

## Components and Interfaces

### 1. Data Model (No Schema Changes)

**Existing Schema**: `game_sessions.draw_penalty` (`:map` field)

**Updated Structure**:
```elixir
%{
  active: boolean,
  penalty_type: string,    # "two" or "three" - determines count via penalty_count/1
  target_player_id: integer,
  created_by_player_id: integer  # optional, for tracking
}
```

**Default Value**:
```elixir
%{active: false, penalty_type: nil, target_player_id: nil}
```

**Note**: The `count` field has been removed. The penalty count is derived dynamically using the `penalty_count/1` helper function based on `penalty_type`.

**Helper Function** (in `CardGames` module):
```elixir
@doc """
Returns the number of cards to draw for a given penalty type.
Handles nil penalty_type (inactive penalties) by returning 0.
"""
def penalty_count(penalty_type) do
  case penalty_type do
    "two" -> 2
    "three" -> 3
    _ -> 0  # nil or unknown penalty type
  end
end
```

This eliminates redundancy by deriving the count from the penalty_type. When `penalty_type` is `nil` (inactive penalty), it returns 0.

### 2. PlayValidator Module Extensions

**Location**: `lib/kadi/games/play_validator.ex`

**New Functions**:

```elixir
# Check if all cards are 3s
defp all_threes?(cards)

# Validate 3 card play when penalty is active
# Returns false if penalty_type is "two" (incompatible)
def valid_three_play?(cards, top_card, action_suit, penalty_type)
```

**Modified Functions**:

```elixir
# Update to accept penalty_type parameter
def valid_play?(cards, top_card, opts)
  # opts now includes:
  # - :action_suit
  # - :penalty_active?
  # - :penalty_type  # NEW

# When penalty is active, check penalty_type:
# - If penalty_type == "two", only accept "ace" or "2"
# - If penalty_type == "three", only accept "ace" or "3"
# - Reject cross-blocking attempts
```

**Validation Logic**:

```elixir
# Single card validation when penalty active
if penalty_active? do
  case {single_card.rank, penalty_type} do
    {"ace", _} -> valid_ace_play?([single_card], top_card, action_suit)
    {"2", "two"} -> validate_single_card(single_card, top_card, action_suit)
    {"3", "three"} -> validate_single_card(single_card, top_card, action_suit)
    _ -> false  # Reject cross-blocking and non-blocking cards
  end
end

# Combo validation when penalty active
if penalty_active? do
  case penalty_type do
    "two" -> all_twos?(cards) and validate_combo(cards, top_card, action_suit)
    "three" -> all_threes?(cards) and validate_combo(cards, top_card, action_suit)
    _ -> false
  end
end
```

### 3. CardGames Context Extensions

**Location**: `lib/kadi/card_games.ex`

**Modified Functions**:

```elixir
# Update to handle 3 card penalty creation
def play_cards(game_session, player_id, card_ids)
  # Detect if cards contain 3s
  # Set draw_penalty with penalty_type: "three", count: 3
  # Clear action_suit if present
  # Advance turn to next player

# Update to pass penalty_type to validator
defp validate_play(cards, top_card, game_session)
  # Extract penalty_type from game_session.draw_penalty
  # Pass to PlayValidator.valid_play?/3

# Update to handle 3 card blocking
def process_draw_penalty(game_session, player_id)
  # Check penalty_type
  # If "three", draw 3 cards
  # Clear penalty after drawing

# Update starting card selection
defp select_starting_card(deck_cards)
  # Exclude ranks "2" and "3"
```

**Penalty Creation Logic**:

```elixir
# In play_cards/3, after validating the play:
cond do
  Enum.any?(cards, &(&1.rank == "3")) ->
    # Create 3 card penalty
    next_player = get_next_player(game_session, player_id)
    draw_penalty = %{
      active: true,
      penalty_type: "three",
      target_player_id: next_player.id,
      created_by_player_id: player_id
    }
    
  Enum.any?(cards, &(&1.rank == "2")) ->
    # Existing 2 card penalty logic
    next_player = get_next_player(game_session, player_id)
    draw_penalty = %{
      active: true,
      penalty_type: "two",
      target_player_id: next_player.id,
      created_by_player_id: player_id
    }
    
  true ->
    # No penalty
    draw_penalty = %{active: false, penalty_type: nil}
end
```

**Penalty Blocking Logic**:

```elixir
# When a 3 is played while penalty is active:
if game_session.draw_penalty["active"] do
  case game_session.draw_penalty["penalty_type"] do
    "three" ->
      # Transfer penalty to next player
      next_player = get_next_player(game_session, player_id)
      draw_penalty = %{
        active: true,
        penalty_type: "three",
        target_player_id: next_player.id,
        created_by_player_id: player_id
      }
      
    "two" ->
      # Reject - 3 cannot block 2
      {:error, "Cannot block 2 card penalty with 3 card"}
  end
end

# When an Ace is played while penalty is active:
if game_session.draw_penalty["active"] do
  # Clear penalty regardless of type (no count field needed)
  draw_penalty = %{
    active: false,
    penalty_type: nil,
    target_player_id: nil
  }
  # Set action_suit to the suit of the most recent penalty card
end
```

### 4. LiveView Extensions

**Location**: `lib/kadi_web/live/game_live.ex`

**Modified Functions**:

```elixir
# Update to handle "Draw 3 Cards" button
def handle_event("accept_penalty", _params, socket)
  # Get penalty_type from game_session.draw_penalty
  # Calculate count using CardGames.penalty_count/1
  # Display appropriate button text: "Draw 2 Cards" or "Draw 3 Cards"
  # Call CardGames.process_draw_penalty/2

# Update UI rendering
defp render_penalty_indicator(assigns)
  # Check penalty_type
  # Display "Draw 2 penalty active" or "Draw 3 penalty active"
```

**UI Components**:

```heex
<!-- Penalty button (replaces normal Draw button) -->
<%= if @game_session.draw_penalty["active"] and 
       @game_session.draw_penalty["target_player_id"] == @current_player.id do %>
  <% penalty_count = CardGames.penalty_count(@game_session.draw_penalty["penalty_type"]) %>
  <button phx-click="accept_penalty">
    Draw <%= penalty_count %> Cards
  </button>
<% end %>

<!-- Penalty indicator badge -->
<%= if @game_session.draw_penalty["active"] do %>
  <% penalty_count = CardGames.penalty_count(@game_session.draw_penalty["penalty_type"]) %>
  <div class="penalty-indicator">
    Draw <%= penalty_count %> penalty active
  </div>
<% end %>
```

### 5. Starting Card Selection

**Location**: `lib/kadi/card_games.ex`

**Modified Function**:

```elixir
defp select_starting_card(deck_cards) do
  # Exclude ranks "2" and "3" from starting card selection
  eligible_cards = 
    Enum.reject(deck_cards, fn dc -> 
      dc.card.rank in ["2", "3"]
    end)
    
  if Enum.empty?(eligible_cards) do
    # Fallback: use any card (edge case)
    Enum.random(deck_cards)
  else
    Enum.random(eligible_cards)
  end
end
```

## Data Flow Diagrams

### Playing a 3 Card

```
Player clicks 3 card
    ↓
LiveView: handle_event("play_cards")
    ↓
CardGames.play_cards(game_session, player_id, [3_card_id])
    ↓
PlayValidator.valid_play?([3_card], top_card, opts)
    ↓
Ecto.Multi transaction:
  - Move card from hand to played_pile
  - Update game_session.draw_penalty = %{active: true, penalty_type: "three", ...}
  - Update current_turn_player_id to next player
    ↓
PubSub.broadcast("game:#{game_id}", {:game_updated, updated_game_session})
    ↓
All LiveViews: handle_info({:game_updated, game_session})
    ↓
UI updates:
  - Next player sees "Draw 3 Cards" button
  - Penalty indicator shows "Draw 3 penalty active"
  - Cards in hand are clickable (for blocking)
```

### Blocking with Another 3

```
Player clicks 3 card (while penalty active)
    ↓
LiveView: handle_event("play_cards")
    ↓
CardGames.play_cards(game_session, player_id, [3_card_id])
    ↓
PlayValidator.valid_play?([3_card], top_card, penalty_active?: true, penalty_type: "three")
    ↓
Validation passes (3 can block 3)
    ↓
Ecto.Multi transaction:
  - Move card from hand to played_pile
  - Update draw_penalty.target_player_id to next player
  - Keep penalty_type: "three"
  - Update current_turn_player_id
    ↓
PubSub.broadcast
    ↓
UI updates for new target player
```

### Blocking with Ace

```
Player clicks Ace (while 3 penalty active)
    ↓
LiveView: handle_event("play_cards")
    ↓
CardGames.play_cards(game_session, player_id, [ace_card_id])
    ↓
PlayValidator.valid_play?([ace], top_card, penalty_active?: true, penalty_type: "three")
    ↓
Validation passes (Ace blocks any penalty)
    ↓
Ecto.Multi transaction:
  - Move card from hand to played_pile
  - Clear draw_penalty: %{active: false, count: 0, penalty_type: nil}
  - Set action_suit to suit of the 3 card that was blocked
  - Update current_turn_player_id
    ↓
PubSub.broadcast
    ↓
UI updates: penalty cleared, suit requirement active
```

### Accepting Penalty

```
Player clicks "Draw 3 Cards" button
    ↓
LiveView: handle_event("accept_penalty")
    ↓
CardGames.process_draw_penalty(game_session, player_id)
    ↓
Ecto.Multi transaction:
  - Move 3 cards from deck to player's hand
  - Clear draw_penalty
  - Update current_turn_player_id to next player
  - Handle deck recycling if needed
    ↓
PubSub.broadcast
    ↓
UI updates:
  - Penalty indicator disappears
  - Card drawing animation plays
  - Turn advances automatically
```

## Error Handling

### Validation Errors

1. **Cross-blocking attempt**: Player tries to play 3 when 2 penalty is active
   - **Detection**: `PlayValidator.valid_play?/3` checks penalty_type
   - **Response**: Return `{:error, "Cannot block 2 card penalty with 3 card"}`
   - **UI**: Display error message via flash

2. **Non-blocking card played**: Player tries to play regular card when penalty active
   - **Detection**: `PlayValidator.valid_play?/3` rejects non-blocking cards
   - **Response**: Return `{:error, "Penalty Active. You must play blocking card or draw penalty cards"}`
   - **UI**: Display error message via flash

3. **Invalid 3 card play**: 3 doesn't match top card suit/rank
   - **Detection**: `validate_single_card/3` checks matching rules
   - **Response**: Return `{:error, "Card doesn't match top card"}`
   - **UI**: Display error message via flash

### Edge Cases

1. **Insufficient deck cards**: Need to draw 3 but deck has fewer
   - **Handling**: `process_draw_penalty/2` calls `draw_card_from_deck/2` three times
   - **Recycling**: Each draw attempt triggers recycling if needed
   - **Fallback**: If no cards available after recycling, log anomaly and skip turn

2. **3 played as last card**: Player becomes cardless
   - **Handling**: Update player status to "cardless"
   - **Penalty**: Still applies to next player
   - **Game continues**: Cardless ≠ winner (winning logic not yet implemented)

3. **Multiple 3s played**: Combo of 3s
   - **Validation**: `all_threes?/1` checks all cards are 3s
   - **Penalty**: Fixed at 3 cards (not cumulative)
   - **Implementation**: Set `count: 3` regardless of combo size

4. **Requested suit + 3 penalty**: Both active simultaneously
   - **Validation**: Blocking card must match requested suit
   - **3 card**: Must match requested suit to be valid
   - **Ace**: Clears penalty and sets new suit requirement

## Testing Strategy

### Unit Tests

**PlayValidator Tests** (`test/kadi/games/play_validator_test.exs`):

```elixir
describe "valid_play?/3 with 3 card penalty active" do
  test "accepts Ace when 3 penalty active"
  test "accepts 3 card when 3 penalty active"
  test "rejects 2 card when 3 penalty active"
  test "rejects regular card when 3 penalty active"
  test "accepts multiple 3s when 3 penalty active"
end

describe "valid_play?/3 with 2 card penalty active" do
  test "rejects 3 card when 2 penalty active"
end

describe "valid_play?/3 with 3 cards (no penalty)" do
  test "accepts 3 matching suit"
  test "accepts 3 matching rank"
  test "rejects 3 not matching suit or rank"
  test "accepts combo of 3s when first matches"
end
```

**CardGames Tests** (`test/kadi/card_games_test.exs`):

```elixir
describe "play_cards/3 with 3 card" do
  test "creates 3 card penalty for next player"
  test "sets penalty_type to 'three'"
  test "clears action_suit when 3 is played"
end

describe "penalty_count/1" do
  test "returns 2 for 'two' penalty type"
  test "returns 3 for 'three' penalty type"
  test "returns 0 for nil or unknown penalty type"
end

describe "play_cards/3 blocking 3 penalty" do
  test "transfers penalty when 3 blocks 3"
  test "clears penalty when Ace blocks 3"
  test "rejects 2 card blocking 3 penalty"
  test "sets action_suit to 3's suit when Ace blocks"
end

describe "process_draw_penalty/2 with 3 penalty" do
  test "draws 3 cards from deck"
  test "clears penalty after drawing"
  test "advances turn to next player"
  test "handles deck recycling when needed"
end

describe "start_game/1 starting card" do
  test "excludes 3 cards from starting card selection"
  test "excludes 2 cards from starting card selection"
end
```

### Integration Tests

**LiveView Tests** (`test/kadi_web/live/game_live_test.exs`):

```elixir
describe "3 card penalty UI" do
  test "displays 'Draw 3 Cards' button when penalty active"
  test "displays 'Draw 3 penalty active' indicator"
  test "allows clicking blocking cards when penalty active"
  test "shows error when non-blocking card clicked"
  test "removes penalty indicator after accepting penalty"
end

describe "3 card gameplay flow" do
  test "complete flow: play 3 → block with 3 → accept penalty"
  test "complete flow: play 3 → block with Ace → match suit"
  test "complete flow: play 3 → accept penalty → draw 3 cards"
end
```

### Test Data Setup

```elixir
# Helper function for creating 3 card penalty state
def create_three_penalty_state(game_session, target_player_id) do
  game_session
  |> Ecto.Changeset.change(%{
    draw_penalty: %{
      active: true,
      penalty_type: "three",
      target_player_id: target_player_id,
      created_by_player_id: 1
    }
  })
  |> Repo.update!()
end
```

## Performance Considerations

1. **Database Queries**: No additional queries needed - reuses existing penalty infrastructure
2. **Transaction Size**: Same as 2 card feature - single `Ecto.Multi` transaction
3. **Broadcast Frequency**: One broadcast per card play (unchanged)
4. **UI Rendering**: Conditional rendering based on penalty state (minimal overhead)

## Security Considerations

1. **Validation**: All plays validated server-side in `PlayValidator`
2. **Authorization**: Player can only play cards from their own hand
3. **Turn Enforcement**: Only current turn player can play cards
4. **Penalty Targeting**: Penalty always targets next player (no player selection)

## Migration Strategy

**No database migration required** - the existing `draw_penalty` map field supports the new structure. The `penalty_type` field is added as a new key in the map.

### Backward Compatibility

**Migration Strategy**: Use a one-time data migration script instead of runtime normalization.

**Why**: 
- Cleaner approach - no runtime overhead checking for old format
- Explicit migration - clear audit trail of data changes
- Simpler code - no need for `normalize_penalty/1` helper in production code

**Migration Script**: `priv/repo/migrate_penalty_data.exs`

```elixir
# Data migration script to convert old penalty format to new format
# Run with: mix run priv/repo/migrate_penalty_data.exs
#
# This script migrates the draw_penalty field from the old format:
#   %{active: true, count: 2, target_player_id: 123}
# To the new format:
#   %{active: true, penalty_type: "two", target_player_id: 123}

alias Kadi.Repo
alias Kadi.Games.GameSession
import Ecto.Query

IO.puts("\n=== Starting Penalty Data Migration ===\n")

# Find all game sessions with old penalty format (has count field)
# Using the ?| operator to check if the jsonb object has the 'count' key
query =
  from gs in GameSession,
    where: fragment("? \\?| array['count']", gs.draw_penalty)

game_sessions = Repo.all(query)

IO.puts("Found #{length(game_sessions)} game sessions with old penalty format")

if length(game_sessions) == 0 do
  IO.puts("No game sessions to migrate. Migration complete!")
  System.halt(0)
end

IO.puts("\nMigrating game sessions...\n")

results =
  Enum.map(game_sessions, fn gs ->
    updated_penalty =
      cond do
        # Active penalty with count=2 -> set penalty_type to "two"
        gs.draw_penalty["active"] == true and gs.draw_penalty["count"] == 2 ->
          gs.draw_penalty
          |> Map.put("penalty_type", "two")
          |> Map.delete("count")

        # Inactive penalty -> just remove count field, set penalty_type to nil
        gs.draw_penalty["active"] == false ->
          %{active: false, penalty_type: nil, target_player_id: nil}

        # Other cases (shouldn't happen, but handle gracefully)
        true ->
          IO.puts(
            "  ⚠️  Game session #{gs.id} has unexpected penalty state: #{inspect(gs.draw_penalty)}"
          )

          %{active: false, penalty_type: nil, target_player_id: nil}
      end

    case gs
         |> Ecto.Changeset.change(%{draw_penalty: updated_penalty})
         |> Repo.update() do
      {:ok, _updated_gs} ->
        IO.puts("  ✓ Migrated game session #{gs.id} (#{gs.short_code})")
        :ok

      {:error, changeset} ->
        IO.puts("  ✗ Failed to migrate game session #{gs.id}: #{inspect(changeset.errors)}")
        :error
    end
  end)

migrated_count = Enum.count(results, &(&1 == :ok))
error_count = Enum.count(results, &(&1 == :error))

IO.puts("\n=== Migration Summary ===")
IO.puts("Total found: #{length(game_sessions)}")
IO.puts("Successfully migrated: #{migrated_count}")
IO.puts("Errors: #{error_count}")

if error_count > 0 do
  IO.puts("\n⚠️  Migration completed with errors. Please review the error messages above.")
  System.halt(1)
else
  IO.puts("\n✓ Migration completed successfully!")
  System.halt(0)
end
```

**Migration Features**:
- Detects game sessions with old `count` field using PostgreSQL's `?|` operator
- Converts `count: 2` to `penalty_type: "two"`
- Removes the redundant `count` field
- Handles inactive penalties by clearing all fields
- Provides detailed progress output with success/error indicators
- Returns appropriate exit codes for CI/CD integration
- Gracefully handles edge cases with warning messages

**Note**: This migration script is only needed if you have existing games with the old penalty format. New games created after the 3 card feature implementation will use the correct format from the start.

**Deployment Steps**:
1. Deploy new code (with `penalty_count/1` helper)
2. Run migration script: `mix run priv/repo/migrate_penalty_data.exs`
3. Verify: Check that all active penalties have `penalty_type` set
4. Monitor: Ensure no errors in production logs

**Rollback Plan**:
If issues arise, the old `count` field is preserved in the database (just not used by new code), so rolling back the code deployment will restore old behavior.

### Deployment Steps

1. Deploy code changes (no downtime required)
2. Existing games continue with 2 card penalties
3. New games can use both 2 and 3 card penalties
4. No data migration needed

## Future Enhancements

1. **Penalty history**: Track who created penalties for analytics
2. **Penalty statistics**: Display penalty success/block rates per player
3. **Custom penalty rules**: Game creator can configure penalty behavior

## Dependencies

- **Existing Features**:
  - Feature 009 (Two Card): Reuses penalty infrastructure
  - Feature 008 (Ace Card): Reuses action_suit clearing logic
  - Feature 004 (Recycle Played Stack): Reuses deck recycling for penalty draws
  - Feature 003 (Pick Card from Deck): Reuses card drawing logic

- **External Libraries**:
  - Ecto: Database transactions
  - Phoenix.PubSub: Real-time broadcasts
  - Phoenix.LiveView: UI updates

## Open Questions

None - all requirements clarified in requirements document.
