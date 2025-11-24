# Task Breakdown: Recycle Played Stack into Deck

**Feature**: 004-recycle-played-stack  
**Generated**: 2025-11-05  
**Status**: Ready for Implementation

---

## Overview

This document breaks down the implementation of the "Recycle Played Stack into Deck" feature into discrete, actionable tasks. Each task is designed to be completable independently with clear acceptance criteria.

**Total Estimated Time**: 4-5 hours  
**Complexity**: Medium  
**Dependencies**: Feature 003 (draw card from deck) - ✅ Complete

---

## Task List

### Phase 1: Core Implementation (Est: 2 hours)

#### Task 1.1: Implement `recycle_played_stack/1` Function
**Priority**: P0 (Critical)  
**Estimated Time**: 60 minutes  
**File**: `lib/kadi/card_games.ex`

**Description**: Create the main function that recycles played stack cards back into the deck.

**Implementation**:
```elixir
@doc """
Recycles cards from the played stack back into the deck.

Takes all cards from played_stack except the topmost card, shuffles them,
assigns new order_index values (1..N), and moves them to deck location.

Minimum 2 cards required in played stack (1 to recycle + 1 topmost to keep).

Returns `{:ok, updated_game_session}` or `{:error, reason}`.

## Examples

    iex> recycle_played_stack(game_session)
    {:ok, %GameSession{}}
    
    iex> recycle_played_stack(one_card_game)
    {:error, :insufficient_cards_to_recycle}
"""
def recycle_played_stack(game_session) do
  # 1. Preload associations
  game_session = Repo.preload(game_session, [deck: [deck_cards: :card]])
  
  # 2. Get played cards
  played_cards = 
    game_session.deck.deck_cards
    |> Enum.filter(&(&1.location_type == "played_stack"))
  
  # 3. Validate minimum cards
  case length(played_cards) do
    0 -> {:error, :no_cards_in_played_stack}
    1 -> {:error, :insufficient_cards_to_recycle}
    _ -> do_recycle(game_session, played_cards)
  end
end
```

**Location**: Add after `draw_card_from_deck/2` (around line 285)

**Acceptance Criteria**:
- ✅ Function signature: `recycle_played_stack(game_session)`
- ✅ Preloads deck with deck_cards and cards
- ✅ Filters for `location_type = "played_stack"`
- ✅ Returns `{:error, :no_cards_in_played_stack}` when empty
- ✅ Returns `{:error, :insufficient_cards_to_recycle}` when 1 card
- ✅ Calls `do_recycle/2` when >= 2 cards
- ✅ Documented with @doc and examples

**Testing**: See Task 3.1

---

#### Task 1.2: Implement `do_recycle/2` Helper Function
**Priority**: P0 (Critical)  
**Estimated Time**: 60 minutes  
**File**: `lib/kadi/card_games.ex`

**Description**: Implement the private helper that performs the actual recycling logic.

**Implementation**:
```elixir
defp do_recycle(game_session, played_cards) do
  # 1. Identify topmost card (keep visible)
  topmost_card = Enum.max_by(played_cards, &(&1.order_index))
  
  # 2. Get recyclable cards (all except topmost)
  recyclable_cards = Enum.reject(played_cards, &(&1.id == topmost_card.id))
  
  # 3. Shuffle and assign indices
  num_cards = length(recyclable_cards)
  shuffled_indices = Enum.shuffle(1..num_cards)
  
  # 4. Create changesets
  changesets =
    Enum.zip(recyclable_cards, shuffled_indices)
    |> Enum.map(fn {card, index} ->
      DeckCard.changeset(card, %{
        location_type: "deck",
        order_index: index,
        player_id: nil
      })
    end)
  
  # 5. Build and execute transaction
  multi =
    changesets
    |> Enum.with_index()
    |> Enum.reduce(Ecto.Multi.new(), fn {changeset, idx}, multi ->
      Ecto.Multi.update(multi, "card_#{idx}", changeset)
    end)
  
  case Repo.transaction(multi) do
    {:ok, _results} ->
      # 6. Reload and return (NO BROADCAST)
      reloaded = Repo.get!(GameSession, game_session.id)
      {:ok, reloaded}
    
    {:error, _op, failed_value, _changes} ->
      {:error, failed_value}
  end
end
```

**Location**: Add immediately after `recycle_played_stack/1`

**Acceptance Criteria**:
- ✅ Uses `Enum.max_by(&(&1.order_index))` to find topmost card
- ✅ Filters recyclable cards (reject topmost)
- ✅ Shuffles indices: `Enum.shuffle(1..num_cards)`
- ✅ Creates changesets with `location_type: "deck"`, `player_id: nil`
- ✅ Uses `Ecto.Multi` for atomic transaction
- ✅ Updates all cards in single transaction
- ✅ Reloads game session after transaction
- ✅ Does NOT broadcast (parent will handle)
- ✅ Returns `{:ok, game_session}` or `{:error, reason}`

**Testing**: See Task 3.1

---

### Phase 2: Integration with Draw Flow (Est: 45 minutes)

#### Task 2.1: Modify `draw_card_from_deck/2` to Call Recycle
**Priority**: P0 (Critical)  
**Estimated Time**: 45 minutes  
**File**: `lib/kadi/card_games.ex`

**Description**: Update the draw function to automatically recycle when deck is empty.

**Current Code** (line ~237):
```elixir
case deck_cards do
  [] ->
    {:error, :deck_empty}
  
  [card_to_draw | _] ->
    # ... existing logic ...
end
```

**New Code**:
```elixir
case deck_cards do
  [] ->
    # NEW: Try recycling before returning error
    case recycle_played_stack(game_session) do
      {:ok, recycled_game_session} ->
        # Guard: verify deck has cards after recycle
        recycled_game_session = 
          Repo.preload(recycled_game_session, [deck: [deck_cards: :card]], force: true)
        
        recycled_deck_cards = 
          recycled_game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "deck"))
          |> Enum.sort_by(& &1.order_index)
        
        if length(recycled_deck_cards) > 0 do
          # Retry draw (will broadcast after success)
          draw_card_from_deck(recycled_game_session, player_id)
        else
          {:error, :deck_empty_after_recycle}
        end
      
      {:error, reason} ->
        # Cannot recycle - return error
        {:error, reason}
    end
  
  [card_to_draw | _] ->
    # ... existing logic (unchanged) ...
end
```

**Acceptance Criteria**:
- ✅ Detects empty deck (`[] ->` case)
- ✅ Calls `recycle_played_stack(game_session)`
- ✅ On success: force reloads deck_cards
- ✅ Guards against infinite recursion (checks deck size > 0)
- ✅ Recursively calls `draw_card_from_deck/2` after successful recycle
- ✅ Returns `{:error, :deck_empty_after_recycle}` if still empty
- ✅ Propagates recycle errors to caller
- ✅ Existing draw logic unchanged (for non-empty deck case)

**Testing**: See Task 3.2

---

### Phase 3: Testing (Est: 1.5 hours)

#### Task 3.1: Unit Tests for `recycle_played_stack/1`
**Priority**: P0 (Critical)  
**Estimated Time**: 60 minutes  
**File**: `test/kadi/card_games_test.exs`

**Description**: Comprehensive unit tests for the recycle function.

**Test Cases**:

```elixir
describe "recycle_played_stack/1" do
  setup do
    player = player_fixture()
    {:ok, game_session} = CardGames.create_game_session(player, %{short_code: "recycle-test"})
    
    # Create game with custom card setup
    game_session = Repo.preload(game_session, [deck: [deck_cards: :card]])
    
    %{player: player, game_session: game_session}
  end
  
  test "successfully recycles cards from played stack", %{game_session: game_session} do
    # Setup: Move 5 cards to played_stack
    deck_cards = game_session.deck.deck_cards |> Enum.take(5)
    
    Enum.with_index(deck_cards, 1)
    |> Enum.each(fn {dc, idx} ->
      DeckCard.changeset(dc, %{location_type: "played_stack", order_index: idx})
      |> Repo.update!()
    end)
    
    # Empty the deck
    remaining_cards = game_session.deck.deck_cards |> Enum.drop(5)
    Enum.each(remaining_cards, fn dc ->
      DeckCard.changeset(dc, %{location_type: "player_hand", player_id: nil, order_index: nil})
      |> Repo.update!()
    end)
    
    game_session = Repo.get!(GameSession, game_session.id)
    
    # Execute recycle
    {:ok, recycled} = CardGames.recycle_played_stack(game_session)
    
    # Verify: 4 cards in deck, 1 in played_stack
    recycled = Repo.preload(recycled, [deck: [deck_cards: :card]], force: true)
    
    deck_count = 
      recycled.deck.deck_cards
      |> Enum.count(&(&1.location_type == "deck"))
    
    played_count = 
      recycled.deck.deck_cards
      |> Enum.count(&(&1.location_type == "played_stack"))
    
    assert deck_count == 4
    assert played_count == 1
  end
  
  test "keeps topmost card (highest order_index) in played stack", %{game_session: game_session} do
    # Setup: 5 cards in played_stack with order_index 1-5
    deck_cards = game_session.deck.deck_cards |> Enum.take(5)
    
    Enum.with_index(deck_cards, 1)
    |> Enum.each(fn {dc, idx} ->
      DeckCard.changeset(dc, %{location_type: "played_stack", order_index: idx})
      |> Repo.update!()
    end)
    
    topmost_card_id = Enum.at(deck_cards, 4).id  # Card with order_index 5
    
    game_session = Repo.get!(GameSession, game_session.id)
    {:ok, recycled} = CardGames.recycle_played_stack(game_session)
    
    # Verify topmost card still in played_stack
    recycled = Repo.preload(recycled, [deck: [deck_cards: :card]], force: true)
    
    topmost_card = 
      recycled.deck.deck_cards
      |> Enum.find(&(&1.location_type == "played_stack"))
    
    assert topmost_card.id == topmost_card_id
    assert topmost_card.order_index == 5
  end
  
  test "assigns sequential shuffled indices to recycled cards", %{game_session: game_session} do
    # Setup: 10 cards in played_stack
    deck_cards = game_session.deck.deck_cards |> Enum.take(10)
    
    Enum.with_index(deck_cards, 1)
    |> Enum.each(fn {dc, idx} ->
      DeckCard.changeset(dc, %{location_type: "played_stack", order_index: idx})
      |> Repo.update!()
    end)
    
    game_session = Repo.get!(GameSession, game_session.id)
    {:ok, recycled} = CardGames.recycle_played_stack(game_session)
    
    # Verify: 9 cards in deck with order_index 1..9
    recycled = Repo.preload(recycled, [deck: [deck_cards: :card]], force: true)
    
    deck_indices = 
      recycled.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.map(& &1.order_index)
      |> Enum.sort()
    
    assert deck_indices == Enum.to_list(1..9)
  end
  
  test "returns error when played stack is empty", %{game_session: game_session} do
    # Setup: no cards in played_stack (all in deck)
    assert {:error, :no_cards_in_played_stack} = 
      CardGames.recycle_played_stack(game_session)
  end
  
  test "returns error when only 1 card in played stack", %{game_session: game_session} do
    # Setup: 1 card in played_stack
    [card | _] = game_session.deck.deck_cards
    
    DeckCard.changeset(card, %{location_type: "played_stack", order_index: 1})
    |> Repo.update!()
    
    game_session = Repo.get!(GameSession, game_session.id)
    
    assert {:error, :insufficient_cards_to_recycle} = 
      CardGames.recycle_played_stack(game_session)
  end
  
  test "clears player_id on recycled cards", %{game_session: game_session, player: player} do
    # Setup: 3 cards in played_stack (simulate edge case with player_id)
    deck_cards = game_session.deck.deck_cards |> Enum.take(3)
    
    Enum.with_index(deck_cards, 1)
    |> Enum.each(fn {dc, idx} ->
      # Intentionally set player_id (edge case)
      DeckCard.changeset(dc, %{
        location_type: "played_stack", 
        order_index: idx,
        player_id: if(idx < 3, do: player.id, else: nil)
      })
      |> Repo.update!()
    end)
    
    game_session = Repo.get!(GameSession, game_session.id)
    {:ok, recycled} = CardGames.recycle_played_stack(game_session)
    
    # Verify all recycled cards have player_id = nil
    recycled = Repo.preload(recycled, [deck: [deck_cards: :card]], force: true)
    
    deck_player_ids = 
      recycled.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.map(& &1.player_id)
    
    assert Enum.all?(deck_player_ids, &is_nil/1)
  end
end
```

**Acceptance Criteria**:
- ✅ Test: Successfully recycles 5 cards (4 to deck, 1 topmost kept)
- ✅ Test: Topmost card (max order_index) remains in played_stack
- ✅ Test: Sequential indices (1..N) assigned after shuffle
- ✅ Test: Error when played stack empty
- ✅ Test: Error when only 1 card in played stack
- ✅ Test: Clears player_id on all recycled cards
- ✅ All tests pass
- ✅ No test flakiness

**Estimated Time**: 60 minutes

---

#### Task 3.2: Integration Tests for Draw + Recycle Flow
**Priority**: P0 (Critical)  
**Estimated Time**: 30 minutes  
**File**: `test/kadi/card_games_test.exs`

**Description**: Test the complete flow of drawing from empty deck (triggering recycle).

**Test Cases**:

```elixir
describe "draw_card_from_deck/2 with automatic recycle" do
  setup do
    player1 = player_fixture()
    player2 = player_fixture(%{email: "player2@example.com"})
    
    {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "draw-recycle"})
    {:ok, _} = CardGames.join_game_session(player2, game_session.id)
    {:ok, game_session} = CardGames.start_game(game_session)
    
    %{player1: player1, player2: player2, game_session: game_session}
  end
  
  test "drawing from empty deck triggers recycle and succeeds", %{
    player1: player1,
    game_session: game_session
  } do
    # Setup: Empty deck, 5 cards in played_stack
    game_session = Repo.preload(game_session, [deck: [deck_cards: :card]])
    
    # Move all deck cards to played_stack
    deck_cards = 
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.take(5)
    
    Enum.with_index(deck_cards, 1)
    |> Enum.each(fn {dc, idx} ->
      DeckCard.changeset(dc, %{location_type: "played_stack", order_index: idx})
      |> Repo.update!()
    end)
    
    # Set current turn to player1
    game_session = 
      GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
      |> Repo.update!()
      |> Repo.get!(game_session.id)
    
    # Execute draw (should trigger recycle)
    {:ok, updated} = CardGames.draw_card_from_deck(game_session, player1.id)
    
    # Verify: player has 1 more card, deck has 3 cards (4 recycled - 1 drawn)
    updated = Repo.preload(updated, [deck: [deck_cards: :card]], force: true)
    
    player_cards = 
      updated.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player1.id))
    
    deck_cards_after = 
      updated.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
    
    assert length(player_cards) == 5  # Started with 4, drew 1
    assert length(deck_cards_after) == 3  # 4 recycled - 1 drawn
  end
  
  test "returns error when cannot recycle (only 1 card in played stack)", %{
    player1: player1,
    game_session: game_session
  } do
    # Setup: Empty deck, 1 card in played_stack
    game_session = Repo.preload(game_session, [deck: [deck_cards: :card]])
    
    # Move 1 card to played_stack
    [card | _] = 
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
    
    DeckCard.changeset(card, %{location_type: "played_stack", order_index: 1})
    |> Repo.update!()
    
    # Empty rest of deck
    game_session.deck.deck_cards
    |> Enum.filter(&(&1.location_type == "deck" && &1.id != card.id))
    |> Enum.each(fn dc ->
      DeckCard.changeset(dc, %{location_type: "player_hand", player_id: player1.id, order_index: nil})
      |> Repo.update!()
    end)
    
    game_session = 
      GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
      |> Repo.update!()
      |> Repo.get!(game_session.id)
    
    # Execute draw (should fail to recycle)
    assert {:error, :insufficient_cards_to_recycle} = 
      CardGames.draw_card_from_deck(game_session, player1.id)
  end
  
  test "topmost card remains visible after recycle", %{
    player1: player1,
    game_session: game_session
  } do
    # Setup: Empty deck, 5 cards in played_stack
    game_session = Repo.preload(game_session, [deck: [deck_cards: :card]])
    
    deck_cards = 
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.take(5)
    
    Enum.with_index(deck_cards, 1)
    |> Enum.each(fn {dc, idx} ->
      DeckCard.changeset(dc, %{location_type: "played_stack", order_index: idx})
      |> Repo.update!()
    end)
    
    topmost_id = Enum.at(deck_cards, 4).id  # Card with order_index 5
    
    game_session = 
      GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
      |> Repo.update!()
      |> Repo.get!(game_session.id)
    
    # Draw (triggers recycle)
    {:ok, updated} = CardGames.draw_card_from_deck(game_session, player1.id)
    
    # Verify topmost card still in played_stack
    updated = Repo.preload(updated, [deck: [deck_cards: :card]], force: true)
    
    played_cards = 
      updated.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "played_stack"))
    
    assert length(played_cards) == 1
    assert hd(played_cards).id == topmost_id
  end
end
```

**Acceptance Criteria**:
- ✅ Test: Draw from empty deck triggers recycle, draw succeeds
- ✅ Test: Error when cannot recycle (1 card in played stack)
- ✅ Test: Topmost card remains in played_stack after recycle
- ✅ All tests pass
- ✅ No test flakiness

**Estimated Time**: 30 minutes

---

### Phase 4: Optional Enhancements (Est: 30 minutes)

#### Task 4.1: Add Error Handling in LiveView (Optional)
**Priority**: P2 (Nice to have)  
**Estimated Time**: 15 minutes  
**File**: `lib/kadi_web/live/game_live.ex`

**Description**: Add flash messages for new error types (rare edge cases).

**Current Code** (line ~59):
```elixir
def handle_event("draw_card", _params, socket) do
  # ...
  case CardGames.draw_card_from_deck(game_session, current_player.id) do
    {:ok, _updated_game_session} ->
      {:noreply, socket}
    
    {:error, :not_your_turn} ->
      {:noreply, put_flash(socket, :error, "It's not your turn")}
    
    {:error, :deck_empty} ->
      {:noreply, put_flash(socket, :error, "No cards left in deck")}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Error: #{reason}")}
  end
end
```

**Add Cases**:
```elixir
{:error, :insufficient_cards_to_recycle} ->
  {:noreply, put_flash(socket, :error, "Cannot recycle: not enough cards in play")}

{:error, :no_cards_in_played_stack} ->
  {:noreply, put_flash(socket, :error, "No cards available to draw")}

{:error, :deck_empty_after_recycle} ->
  {:noreply, put_flash(socket, :error, "Unable to draw card")}
```

**Acceptance Criteria**:
- ✅ Added flash messages for 3 new error types
- ✅ Messages are user-friendly
- ✅ Existing error handling unchanged

**Note**: These errors should rarely occur in normal gameplay.

**Estimated Time**: 15 minutes

---

#### Task 4.2: Performance Test (Optional)
**Priority**: P2 (Nice to have)  
**Estimated Time**: 15 minutes  
**File**: `test/kadi/card_games_test.exs`

**Description**: Verify recycle completes within 1 second for 50 cards.

**Test Case**:
```elixir
test "recycle_played_stack completes within 1 second for 50 cards", %{
  game_session: game_session
} do
  # Setup: 50 cards in played_stack
  deck_cards = game_session.deck.deck_cards |> Enum.take(50)
  
  Enum.with_index(deck_cards, 1)
  |> Enum.each(fn {dc, idx} ->
    DeckCard.changeset(dc, %{location_type: "played_stack", order_index: idx})
    |> Repo.update!()
  end)
  
  game_session = Repo.get!(GameSession, game_session.id)
  
  # Measure performance
  {time_microseconds, {:ok, _}} = 
    :timer.tc(fn ->
      CardGames.recycle_played_stack(game_session)
    end)
  
  time_ms = time_microseconds / 1000
  
  assert time_ms < 1000, "Recycle took #{time_ms}ms (expected < 1000ms)"
end
```

**Acceptance Criteria**:
- ✅ Test completes within 1 second for 95% of runs
- ✅ Performance logged for monitoring

**Estimated Time**: 15 minutes

---

### Phase 5: Verification (Est: 30 minutes)

#### Task 5.1: Run Full Test Suite
**Priority**: P0 (Critical)  
**Estimated Time**: 10 minutes

**Commands**:
```bash
mix test
mix test --warnings-as-errors
```

**Acceptance Criteria**:
- ✅ All new tests pass (9 test cases)
- ✅ All existing tests still pass
- ✅ No compiler warnings
- ✅ No test warnings

---

#### Task 5.2: Manual Testing
**Priority**: P0 (Critical)  
**Estimated Time**: 20 minutes

**Test Scenarios**:
1. **Empty deck scenario**:
   - Start game with 2 players
   - Manually empty deck (via IEx or test setup)
   - Add 5 cards to played_stack
   - Player draws → deck should recycle, draw succeeds

2. **Edge case: 1 card in played stack**:
   - Empty deck
   - 1 card in played_stack
   - Player draws → should get error message

3. **Normal gameplay**:
   - Play full game until deck empties naturally
   - Verify recycle happens automatically
   - Verify game continues normally

**Acceptance Criteria**:
- ✅ Empty deck triggers recycle automatically
- ✅ Topmost card remains visible
- ✅ Draw succeeds after recycle
- ✅ Error handling works for edge cases
- ✅ UI updates correctly for all players

---

## Task Dependencies

```
Task 1.1 (recycle_played_stack/1)
  │
  └─→ Task 1.2 (do_recycle/2)
        │
        └─→ Task 2.1 (modify draw_card_from_deck/2)
              │
              ├─→ Task 3.1 (unit tests)
              │
              ├─→ Task 3.2 (integration tests)
              │
              ├─→ Task 4.1 (LiveView errors - optional)
              │
              └─→ Task 4.2 (performance test - optional)
                    │
                    └─→ Task 5.1 (full test suite)
                          │
                          └─→ Task 5.2 (manual testing)
```

**Critical Path**: 1.1 → 1.2 → 2.1 → 3.1/3.2 → 5.1 → 5.2

---

## Checklist Summary

### Implementation
- [ ] Task 1.1: Implement `recycle_played_stack/1`
- [ ] Task 1.2: Implement `do_recycle/2`
- [ ] Task 2.1: Modify `draw_card_from_deck/2`

### Testing
- [ ] Task 3.1: Unit tests for recycle (6 tests)
- [ ] Task 3.2: Integration tests (3 tests)

### Optional
- [ ] Task 4.1: LiveView error handling
- [ ] Task 4.2: Performance test

### Verification
- [ ] Task 5.1: Full test suite passes
- [ ] Task 5.2: Manual testing complete

---

## Success Criteria

**Feature is complete when**:
1. ✅ All mandatory tasks marked complete (1.1, 1.2, 2.1, 3.1, 3.2, 5.1, 5.2)
2. ✅ All tests passing (9+ test cases)
3. ✅ Performance requirement met (<1 second)
4. ✅ Code reviewed and follows Elixir conventions
5. ✅ Manual testing confirms:
   - Recycle triggers automatically on empty deck
   - Topmost card remains visible
   - Draw succeeds after recycle
   - Turn advances normally
   - UI updates for all players

---

## Notes

- **Critical Path**: Tasks 1.1 → 1.2 → 2.1 must be done in order
- **Parallel Work**: After Task 2.1, testing tasks (3.1, 3.2) can be done in parallel
- **Optional Tasks**: 4.1 and 4.2 are nice-to-have but not required
- **No UI Changes**: Feature is entirely backend, transparent to users
- **No Broadcasting**: recycle_played_stack does NOT broadcast (draw function handles it)

---

**Ready to Start**: Begin with Task 1.1 (Implement recycle_played_stack/1)

**Estimated Total Time**: 4-5 hours (including testing and verification)

**Files Changed**: 
- `lib/kadi/card_games.ex` (~80 lines added)
- `test/kadi/card_games_test.exs` (~200 lines added)
- `lib/kadi_web/live/game_live.ex` (optional, ~10 lines added)

---

## Quick Reference

**Key Pattern**:
```elixir
topmost = Enum.max_by(played_cards, &(&1.order_index))
recyclable = Enum.reject(played_cards, &(&1.id == topmost.id))
indices = Enum.shuffle(1..length(recyclable))
```

**Error Codes**:
- `:no_cards_in_played_stack` - played stack empty
- `:insufficient_cards_to_recycle` - only 1 card
- `:deck_empty_after_recycle` - edge case guard

**Remember**: NO broadcast in recycle function!
