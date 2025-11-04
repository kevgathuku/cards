# Task Breakdown: Draw Card from Deck

**Feature**: 003-pick-card-from-deck  
**Generated**: 2025-11-04  
**Status**: Ready for Implementation

---

## Overview

This document breaks down the implementation of the "Draw Card from Deck" feature into discrete, actionable tasks. Each task is designed to be completable independently with clear acceptance criteria.

**Total Estimated Time**: 6-8 hours  
**Complexity**: Medium  
**Dependencies**: None (all prerequisites met)

---

## Task List

### Phase 1: Critical Bug Fix & Foundation (Est: 1 hour)

#### Task 1.1: Fix `get_game_session_players/1` Ordering Bug 🔴 CRITICAL
**Priority**: P0 (Must be done first)  
**Estimated Time**: 15 minutes  
**File**: `lib/kadi/card_games.ex`

**Description**: Add explicit ordering to `get_game_session_players/1` to ensure deterministic turn order by join time.

**Changes Required**:
```elixir
# CURRENT (line 252-259):
defp get_game_session_players(game_session_id) do
  query =
    from gsp in GameSessionPlayer,
      where: gsp.game_session_id == ^game_session_id,
      select: gsp.player_id
  
  Repo.all(from p in Player, where: p.id in subquery(query))
end

# CHANGE TO:
defp get_game_session_players(game_session_id) do
  query =
    from gsp in GameSessionPlayer,
      where: gsp.game_session_id == ^game_session_id,
      order_by: [asc: gsp.inserted_at],  # ← ADD THIS
      select: gsp.player_id
  
  Repo.all(from p in Player, where: p.id in subquery(query))
end
```

**Acceptance Criteria**:
- ✅ Query includes `order_by: [asc: gsp.inserted_at]`
- ✅ Existing tests still pass
- ✅ Players are returned in consistent order across calls

**Testing**:
- Run existing test suite to ensure no regressions
- Manually verify order is consistent with `iex -S mix`

---

#### Task 1.2: Implement `get_next_player/2` Helper Function
**Priority**: P0  
**Estimated Time**: 30 minutes  
**File**: `lib/kadi/card_games.ex`

**Description**: Create a pure helper function to calculate the next player in turn order.

**Implementation**:
```elixir
@doc """
Returns the next player in turn order after the current player.

Players are ordered by join time (inserted_at), and the order wraps around
(last player → first player).

## Examples

    iex> players = [player1, player2, player3]
    iex> get_next_player(players, player2.id)
    player3
    
    iex> get_next_player(players, player3.id)
    player1  # wraps around

"""
defp get_next_player(players, current_player_id) do
  current_index = Enum.find_index(players, &(&1.id == current_player_id))
  next_index = rem(current_index + 1, length(players))
  Enum.at(players, next_index)
end
```

**Acceptance Criteria**:
- ✅ Function is private (`defp`)
- ✅ Returns next player in sequential order
- ✅ Wraps around when current player is last
- ✅ Handles 2, 3, 4+ player scenarios
- ✅ Documented with @doc and examples

**Testing**: See Task 4.2

---

### Phase 2: Core Implementation (Est: 2-3 hours)

#### Task 2.1: Implement `draw_card_from_deck/2` Function
**Priority**: P0  
**Estimated Time**: 90 minutes  
**File**: `lib/kadi/card_games.ex`

**Description**: Create the main function that handles drawing a card from the deck.

**Implementation Structure**:
```elixir
@doc """
Draws a card from the deck for the specified player.

Validates that it's the player's turn, moves one card from deck to player's hand,
advances turn to next player (by join order), and broadcasts update.

Returns `{:ok, updated_game_session}` or `{:error, reason}`.

## Examples

    iex> draw_card_from_deck(game_session, player.id)
    {:ok, %GameSession{}}
    
    iex> draw_card_from_deck(game_session, wrong_player.id)
    {:error, :not_your_turn}
    
    iex> draw_card_from_deck(empty_deck_game, player.id)
    {:error, :deck_empty}
"""
def draw_card_from_deck(game_session, player_id) do
  # 1. Preload necessary associations
  game_session = 
    game_session
    |> Repo.preload([:created_by, deck: [deck_cards: :card]])
  
  # 2. Validate player's turn
  if game_session.current_turn_player_id != player_id do
    {:error, :not_your_turn}
  else
    # 3. Get deck cards and validate not empty
    deck_cards = 
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.sort_by(& &1.order_index)
    
    case deck_cards do
      [] -> 
        {:error, :deck_empty}
      
      [card_to_draw | _] ->
        # 4. Get all players in order and calculate next player
        players = get_game_session_players(game_session.id)
        next_player = get_next_player(players, player_id)
        
        # 5. Build transaction
        multi =
          Ecto.Multi.new()
          |> Ecto.Multi.update(
            :deck_card,
            DeckCard.changeset(card_to_draw, %{
              location_type: "player_hand",
              player_id: player_id
            })
          )
          |> Ecto.Multi.update(
            :game_session,
            GameSession.changeset(game_session, %{
              current_turn_player_id: next_player.id
            })
          )
        
        # 6. Execute transaction
        case Repo.transaction(multi) do
          {:ok, %{game_session: updated_game_session}} ->
            # 7. Reload with all associations
            reloaded_game_session =
              GameSession
              |> Repo.get!(updated_game_session.id)
              |> Repo.preload(:created_by)
            
            # 8. Broadcast update
            KadiWeb.Endpoint.broadcast(
              "game:" <> to_string(reloaded_game_session.id),
              "game_updated",
              %{game_session: reloaded_game_session}
            )
            
            {:ok, reloaded_game_session}
          
          {:error, _failed_op, failed_value, _changes} ->
            {:error, failed_value}
        end
    end
  end
end
```

**Acceptance Criteria**:
- ✅ Function signature: `draw_card_from_deck(game_session, player_id)`
- ✅ Validates player's turn (returns `{:error, :not_your_turn}`)
- ✅ Validates deck not empty (returns `{:error, :deck_empty}`)
- ✅ Selects card with lowest `order_index`
- ✅ Updates card location to `"player_hand"` with `player_id`
- ✅ Calculates next player using `get_next_player/2`
- ✅ Updates `current_turn_player_id` to next player
- ✅ Uses `Ecto.Multi` for atomic transaction
- ✅ Reloads game session with `created_by` preload
- ✅ Broadcasts `game_updated` event
- ✅ Returns `{:ok, game_session}` on success
- ✅ Documented with @doc and examples

**Testing**: See Task 4.1

---

### Phase 3: LiveView Integration (Est: 1 hour)

#### Task 3.1: Add `handle_event("draw_card", ...)` to GameLive
**Priority**: P0  
**Estimated Time**: 30 minutes  
**File**: `lib/kadi_web/live/game_live.ex`

**Description**: Add LiveView event handler for draw card action. No direct socket update (wait for broadcast).

**Implementation**:
```elixir
@impl true
def handle_event("draw_card", _params, socket) do
  game_session = socket.assigns.game_session
  current_player = socket.assigns.current_player
  
  case CardGames.draw_card_from_deck(game_session, current_player.id) do
    {:ok, _updated_game_session} ->
      # Don't update socket directly - wait for broadcast
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

**Acceptance Criteria**:
- ✅ Event handler matches "draw_card"
- ✅ Calls `CardGames.draw_card_from_deck/2`
- ✅ Does NOT call `assign_game_state` on success (waits for broadcast)
- ✅ Handles `:not_your_turn` error with flash message
- ✅ Handles `:deck_empty` error with flash message
- ✅ Handles generic errors

**Testing**: See Task 4.3

---

#### Task 3.2: Add "Draw Card" Button to Template
**Priority**: P0  
**Estimated Time**: 30 minutes  
**File**: `lib/kadi_web/live/game_live.html.heex`

**Description**: Add button to UI with proper visibility conditions and loading state.

**Implementation**:
```heex
<%= if @game_session.status == "live" do %>
  <%= if @current_turn_player do %>
    <div class="mt-4 p-4 bg-blue-100 border border-blue-300 rounded-lg text-center">
      <p class="text-lg font-semibold">
        Current Turn: <span class="text-blue-700">{@current_turn_player.email}</span>
      </p>
      <%= if @current_turn_player.id == @current_player.id do %>
        <p class="text-sm text-blue-600 mt-1">It's your turn!</p>
        
        <%# Draw Card Button - Only visible when it's player's turn AND deck has cards %>
        <%= if @deck_size > 0 do %>
          <.button 
            phx-click="draw_card" 
            phx-disable-with="Drawing..." 
            class="mt-2">
            Draw Card
          </.button>
        <% end %>
      <% end %>
    </div>
  <% end %>
  
  <%# Rest of game board... %>
<% end %>
```

**Acceptance Criteria**:
- ✅ Button labeled "Draw Card"
- ✅ Button only visible when `@current_turn_player.id == @current_player.id`
- ✅ Button only visible when `@deck_size > 0`
- ✅ Button has `phx-click="draw_card"` event
- ✅ Button has `phx-disable-with="Drawing..."` loading state
- ✅ Button uses Phoenix component `<.button>` for consistency

**Testing**: See Task 4.3

---

### Phase 4: Testing (Est: 2-3 hours)

#### Task 4.1: Unit Tests for `draw_card_from_deck/2`
**Priority**: P0  
**Estimated Time**: 60 minutes  
**File**: `test/kadi/card_games_test.exs`

**Description**: Comprehensive unit tests for the draw card function.

**Tests to Add**:
```elixir
describe "draw_card_from_deck/2" do
  setup do
    player1 = player_fixture()
    player2 = player_fixture(%{email: "player2@example.com"})
    player3 = player_fixture(%{email: "player3@example.com"})
    
    {:ok, game_session} = 
      CardGames.create_game_session(player1, %{short_code: "draw-test"})
    
    {:ok, _} = CardGames.join_game_session(player2, game_session.id)
    {:ok, _} = CardGames.join_game_session(player3, game_session.id)
    {:ok, game_session} = CardGames.start_game(game_session)
    
    %{
      player1: player1,
      player2: player2,
      player3: player3,
      game_session: game_session
    }
  end
  
  test "successfully draws a card when it's player's turn", %{
    game_session: game_session
  } do
    current_player_id = game_session.current_turn_player_id
    
    {:ok, updated_session} = 
      CardGames.draw_card_from_deck(game_session, current_player_id)
    
    # Reload to check database state
    updated_session = Repo.preload(updated_session, [deck: [deck_cards: :card]])
    
    # Player should have one more card
    player_cards = 
      updated_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == current_player_id))
    
    assert length(player_cards) == 5  # Started with 4, drew 1
    
    # Turn should have advanced
    assert updated_session.current_turn_player_id != current_player_id
  end
  
  test "advances turn to next player in sequence (2 players)", %{
    player1: player1,
    player2: player2
  } do
    {:ok, game_session} = 
      CardGames.create_game_session(player1, %{short_code: "two-player"})
    {:ok, _} = CardGames.join_game_session(player2, game_session.id)
    {:ok, game_session} = CardGames.start_game(game_session)
    
    first_player_id = game_session.current_turn_player_id
    
    {:ok, updated_session} = 
      CardGames.draw_card_from_deck(game_session, first_player_id)
    
    second_player_id = updated_session.current_turn_player_id
    
    # Turn should advance to other player
    assert second_player_id != first_player_id
    assert second_player_id in [player1.id, player2.id]
  end
  
  test "turn wraps around from last player to first", %{
    player1: player1,
    player2: player2,
    player3: player3,
    game_session: game_session
  } do
    # Draw cards until we cycle through all players
    players = [player1.id, player2.id, player3.id]
    
    session = game_session
    seen_order = []
    
    # Draw 3 times to complete one full cycle
    Enum.each(1..3, fn _ ->
      current_id = session.current_turn_player_id
      seen_order = seen_order ++ [current_id]
      {:ok, session} = CardGames.draw_card_from_deck(session, current_id)
      session = Repo.get!(GameSession, session.id)
    end)
    
    # After 3 draws, should be back to first player
    assert session.current_turn_player_id == hd(seen_order)
  end
  
  test "returns error when it's not player's turn", %{
    game_session: game_session,
    player1: player1
  } do
    wrong_player_id = 
      if game_session.current_turn_player_id == player1.id do
        # Find a different player
        players = get_game_session_players(game_session.id)
        Enum.find(players, &(&1.id != player1.id)).id
      else
        player1.id
      end
    
    assert {:error, :not_your_turn} = 
      CardGames.draw_card_from_deck(game_session, wrong_player_id)
  end
  
  test "returns error when deck is empty" do
    player = player_fixture()
    {:ok, game_session} = 
      CardGames.create_game_session(player, %{short_code: "empty-deck"})
    
    # Manually empty the deck for testing
    game_session = Repo.preload(game_session, [deck: :deck_cards])
    
    Enum.each(game_session.deck.deck_cards, fn dc ->
      DeckCard.changeset(dc, %{location_type: "player_hand", player_id: player.id})
      |> Repo.update!()
    end)
    
    game_session = 
      GameSession.changeset(game_session, %{
        status: "live",
        current_turn_player_id: player.id
      })
      |> Repo.update!()
    
    assert {:error, :deck_empty} = 
      CardGames.draw_card_from_deck(game_session, player.id)
  end
end
```

**Acceptance Criteria**:
- ✅ Test: Happy path (card drawn, turn advanced)
- ✅ Test: 2-player turn rotation
- ✅ Test: Turn wrapping (3+ players)
- ✅ Test: Error when not player's turn
- ✅ Test: Error when deck empty
- ✅ All tests pass
- ✅ No test flakiness

**Estimated Time**: 60 minutes

---

#### Task 4.2: Unit Tests for `get_next_player/2`
**Priority**: P1  
**Estimated Time**: 20 minutes  
**File**: `test/kadi/card_games_test.exs`

**Description**: Test the turn order calculation helper function.

**Tests to Add**:
```elixir
describe "get_next_player/2" do
  test "returns next player in sequence" do
    player1 = player_fixture()
    player2 = player_fixture(%{email: "p2@example.com"})
    player3 = player_fixture(%{email: "p3@example.com"})
    
    players = [player1, player2, player3]
    
    assert CardGames.get_next_player(players, player1.id) == player2
    assert CardGames.get_next_player(players, player2.id) == player3
  end
  
  test "wraps around from last to first player" do
    player1 = player_fixture()
    player2 = player_fixture(%{email: "p2@example.com"})
    player3 = player_fixture(%{email: "p3@example.com"})
    
    players = [player1, player2, player3]
    
    assert CardGames.get_next_player(players, player3.id) == player1
  end
  
  test "handles 2-player game" do
    player1 = player_fixture()
    player2 = player_fixture(%{email: "p2@example.com"})
    
    players = [player1, player2]
    
    assert CardGames.get_next_player(players, player1.id) == player2
    assert CardGames.get_next_player(players, player2.id) == player1
  end
end
```

**Acceptance Criteria**:
- ✅ Test: Sequential order (player 1 → 2 → 3)
- ✅ Test: Wrap around (player 3 → player 1)
- ✅ Test: 2-player scenario
- ✅ All tests pass

**Note**: This function is private, so tests should be added to a module that can access private functions, or test it indirectly through `draw_card_from_deck/2`.

---

#### Task 4.3: Integration Tests in GameLiveTest
**Priority**: P0  
**Estimated Time**: 60 minutes  
**File**: `test/kadi_web/live/game_live_test.exs`

**Description**: Test the full draw card flow through LiveView.

**Tests to Add**:
```elixir
describe "draw card action" do
  setup do
    player1 = player_fixture()
    player2 = player_fixture(%{email: "player2@example.com"})
    
    {:ok, game_session} = 
      CardGames.create_game_session(player1, %{short_code: "draw-live-test"})
    {:ok, _} = CardGames.join_game_session(player2, game_session.id)
    {:ok, game_session} = CardGames.start_game(game_session)
    
    %{player1: player1, player2: player2, game_session: game_session}
  end
  
  test "player can draw card on their turn", %{
    player1: player1,
    game_session: game_session
  } do
    # Ensure it's player1's turn
    game_session = 
      if game_session.current_turn_player_id != player1.id do
        GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Repo.update!()
      else
        game_session
      end
    
    conn = log_in_player(build_conn(), player1)
    {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")
    
    # Get initial hand size
    initial_html = render(view)
    # Should show "Draw Card" button
    assert initial_html =~ "Draw Card"
    
    # Click draw card
    render_click(view, "draw_card")
    Process.sleep(100)  # Wait for broadcast
    
    # Verify state updated
    updated_html = render(view)
    
    # Should have one more card now
    # (This test assumes we can see card count in the UI)
  end
  
  test "draw card button hidden when not player's turn", %{
    player1: player1,
    player2: player2,
    game_session: game_session
  } do
    # Ensure it's player2's turn
    game_session = 
      GameSession.changeset(game_session, %{current_turn_player_id: player2.id})
      |> Repo.update!()
    
    conn = log_in_player(build_conn(), player1)
    {:ok, view, html} = live(conn, ~p"/games/#{game_session.id}")
    
    # Should NOT show "Draw Card" button
    refute html =~ "Draw Card"
  end
  
  test "draw card button hidden when deck is empty", %{
    player1: player1,
    game_session: game_session
  } do
    # Empty the deck
    game_session = Repo.preload(game_session, [deck: :deck_cards])
    
    Enum.each(game_session.deck.deck_cards, fn dc ->
      if dc.location_type == "deck" do
        DeckCard.changeset(dc, %{location_type: "played_stack"})
        |> Repo.update!()
      end
    end)
    
    game_session = 
      GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
      |> Repo.update!()
    
    conn = log_in_player(build_conn(), player1)
    {:ok, view, html} = live(conn, ~p"/games/#{game_session.id}")
    
    # Should NOT show "Draw Card" button
    refute html =~ "Draw Card"
  end
  
  test "multiple players see updated state after draw", %{
    player1: player1,
    player2: player2,
    game_session: game_session
  } do
    game_session = 
      GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
      |> Repo.update!()
    
    conn1 = log_in_player(build_conn(), player1)
    conn2 = log_in_player(build_conn(), player2)
    
    {:ok, view1, _html1} = live(conn1, ~p"/games/#{game_session.id}")
    {:ok, view2, _html2} = live(conn2, ~p"/games/#{game_session.id}")
    
    # Player1 draws card
    render_click(view1, "draw_card")
    Process.sleep(100)
    
    # Both views should update
    html1 = render(view1)
    html2 = render(view2)
    
    # Current turn should have changed to player2
    assert html1 =~ player2.email
    assert html2 =~ player2.email
    
    # Player2 should now see the "Draw Card" button
    assert html2 =~ "Draw Card"
    
    # Player1 should NOT see the button
    refute html1 =~ "Draw Card"
  end
end
```

**Acceptance Criteria**:
- ✅ Test: Player can draw on their turn
- ✅ Test: Button hidden when not player's turn
- ✅ Test: Button hidden when deck empty
- ✅ Test: Multiple players see updated state
- ✅ All tests pass
- ✅ No flakiness in broadcast timing

---

### Phase 5: Verification & Documentation (Est: 30 minutes)

#### Task 5.1: Run Full Test Suite
**Priority**: P0  
**Estimated Time**: 10 minutes

**Description**: Verify all tests pass, including existing tests.

**Commands**:
```bash
mix test
mix test --warnings-as-errors
```

**Acceptance Criteria**:
- ✅ All new tests pass
- ✅ All existing tests still pass
- ✅ No compiler warnings
- ✅ No test warnings

---

#### Task 5.2: Performance Verification
**Priority**: P1  
**Estimated Time**: 15 minutes

**Description**: Verify draw card action completes within 500ms.

**Test**:
```elixir
test "draw card completes within 500ms" do
  # Setup game
  player1 = player_fixture()
  player2 = player_fixture(%{email: "p2@example.com"})
  {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "perf"})
  {:ok, _} = CardGames.join_game_session(player2, game_session.id)
  {:ok, game_session} = CardGames.start_game(game_session)
  
  # Measure performance
  {time_microseconds, {:ok, _}} = 
    :timer.tc(fn ->
      CardGames.draw_card_from_deck(game_session, game_session.current_turn_player_id)
    end)
  
  time_ms = time_microseconds / 1000
  
  assert time_ms < 500, "Draw card took #{time_ms}ms (expected < 500ms)"
end
```

**Acceptance Criteria**:
- ✅ Draw card completes in <500ms for 95% of runs
- ✅ Performance test passes consistently

---

#### Task 5.3: Update CLAUDE.md (Optional)
**Priority**: P2  
**Estimated Time**: 5 minutes  
**File**: `CLAUDE.md`

**Description**: Update agent context if significant patterns were added.

**Changes**:
- Document turn order algorithm (by join time)
- Note that `get_game_session_players/1` bug was fixed
- Add example of broadcast-only update pattern (if different from existing)

**Acceptance Criteria**:
- ✅ CLAUDE.md updated with relevant context
- ✅ No outdated information remains

---

## Task Dependencies

```
Task 1.1 (Fix ordering bug)
  ↓
Task 1.2 (get_next_player)
  ↓
Task 2.1 (draw_card_from_deck)
  ↓
├─→ Task 3.1 (LiveView handler)
│     ↓
│   Task 3.2 (UI template)
│     ↓
│   Task 4.3 (Integration tests)
│
├─→ Task 4.1 (Unit tests: draw_card)
│
└─→ Task 4.2 (Unit tests: get_next_player)
      ↓
    Task 5.1 (Full test suite)
      ↓
    Task 5.2 (Performance test)
      ↓
    Task 5.3 (Documentation)
```

---

## Checklist Summary

### Implementation
- [ ] Task 1.1: Fix `get_game_session_players/1` ordering
- [ ] Task 1.2: Implement `get_next_player/2`
- [ ] Task 2.1: Implement `draw_card_from_deck/2`
- [ ] Task 3.1: Add LiveView event handler
- [ ] Task 3.2: Add "Draw Card" button to template

### Testing
- [ ] Task 4.1: Unit tests for `draw_card_from_deck/2`
- [ ] Task 4.2: Unit tests for `get_next_player/2`
- [ ] Task 4.3: Integration tests in GameLiveTest

### Verification
- [ ] Task 5.1: Full test suite passes
- [ ] Task 5.2: Performance test passes
- [ ] Task 5.3: Documentation updated (if needed)

---

## Success Criteria

**Feature is complete when**:
1. ✅ All tasks marked complete
2. ✅ All tests passing (new + existing)
3. ✅ Performance requirement met (<500ms)
4. ✅ Code reviewed and follows Elixir conventions
5. ✅ Manual testing confirms:
   - Button appears only when appropriate
   - Drawing works for 2, 3, 4 players
   - Turn order is consistent
   - UI updates for all connected players

---

## Notes

- **Critical Path**: Tasks 1.1 → 1.2 → 2.1 must be done in order
- **Parallel Work**: After Task 2.1, testing tasks can be done in parallel with LiveView tasks
- **Testing Strategy**: Unit tests first, then integration tests
- **Performance**: If performance test fails, profile with `:timer.tc` to identify bottleneck

---

**Ready to Start**: Begin with Task 1.1 (Fix ordering bug)
