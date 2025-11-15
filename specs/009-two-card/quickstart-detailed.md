# Detailed Quickstart Guide: Two Card Penalty UI Implementation

## Overview
This guide provides comprehensive step-by-step instructions for implementing the Two Card penalty acceptance UI improvements. The backend penalty logic already exists (`CardGames.process_draw_penalty/2`), so this work focuses entirely on the LiveView presentation layer.

**Estimated Time**: 2-3 hours  
**Difficulty**: Moderate (LiveView + CSS animations)  
**Prerequisites**: Familiarity with Phoenix LiveView, basic CSS

---

## Phase 1: Backend Verification (5 minutes)

### Verify Existing Penalty Logic

```bash
# 1. Confirm process_draw_penalty/2 exists
grep -n "def process_draw_penalty" lib/kadi/card_games.ex
# Expected: Line 487 (or similar)

# 2. Verify draw_penalty field in schema
grep -n "field :draw_penalty" lib/kadi/games/game_session.ex
# Expected: Line 16 (or similar)

# 3. Check existing tests
grep -n "describe \"process_draw_penalty" test/kadi/card_games/special_cards_two_test.exs
# Expected: Multiple test blocks
```

✅ **Checkpoint**: All three commands should return results. If not, review CLAUDE.md or AGENTS.md for context.

---

## Phase 2: LiveView Event Handler (30 minutes)

### Step 1: Add accept_penalty Event Handler

**File**: `lib/kadi_web/live/game_live.ex`

**Location**: Add after existing `handle_event` clauses (around line 200+)

```elixir
@doc """
Handle explicit acceptance of Two Card draw penalty.

Calls existing CardGames.process_draw_penalty/2 backend function.
Does NOT update socket directly - waits for PubSub broadcast.
"""
def handle_event("accept_penalty", _params, socket) do
  game_session = socket.assigns.game_session
  player_id = socket.assigns.current_player.id
  
  case CardGames.process_draw_penalty(game_session, player_id) do
    {:ok, _updated_game_session} ->
      # Don't update socket - wait for broadcast
      {:noreply, socket}
      
    {:error, :not_current_turn} ->
      {:noreply, put_flash(socket, :error, "It's not your turn")}
      
    {:error, :no_penalty} ->
      {:noreply, put_flash(socket, :error, "No penalty to accept")}
      
    {:error, :insufficient_cards} ->
      {:noreply, put_flash(socket, :error, "Not enough cards in deck to draw penalty")}
      
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Cannot draw penalty: #{inspect(reason)}")}
  end
end
```

**Key Pattern**: Notice the handler does NOT update the socket on success. It waits for the PubSub broadcast in `handle_info({:game_updated, game_session}, socket)` to update all connected clients simultaneously.

### Step 2: Add Animation Trigger in handle_info

**File**: `lib/kadi_web/live/game_live.ex`

**Location**: Update existing `handle_info({:game_updated, game_session}, socket)` clause

**Before**:
```elixir
def handle_info({:game_updated, game_session}, socket) do
  {:noreply, assign(socket, game_session: game_session)}
end
```

**After**:
```elixir
def handle_info({:game_updated, game_session}, socket) do
  # Check if penalty was just cleared (cards were drawn)
  old_penalty = socket.assigns.game_session.draw_penalty
  new_penalty = game_session.draw_penalty
  show_animation = old_penalty != %{} and new_penalty == %{}
  
  socket =
    socket
    |> assign(game_session: game_session)
    |> assign(show_penalty_animation: show_animation)
  
  {:noreply, socket}
end
```

**Rationale**: This triggers the animation only when a penalty was cleared (cards were drawn), not on every game update.

✅ **Checkpoint**: Run `mix format` and verify no compilation errors with `mix compile`

---

## Phase 3: Template Updates (45 minutes)

### Step 3: Add Penalty Button to Template

**File**: `lib/kadi_web/live/game_live.html.heex`

**Location**: Find the existing "Draw Card" button section (search for `phx-click="draw_card"`)

**Before** (simplified):
```heex
<button phx-click="draw_card" class="btn-primary">
  Draw Card
</button>
```

**After** (conditional rendering):
```heex
<%= if show_penalty_button?(@game_session, @current_player) do %>
  <!-- Penalty acceptance button (replaces normal draw button) -->
  <button 
    phx-click="accept_penalty" 
    class="btn-penalty bg-red-600 hover:bg-red-700 text-white font-bold py-2 px-4 rounded shadow-lg transition-all duration-200"
  >
    Draw <%= @game_session.draw_penalty.pending_count %> Cards
  </button>
<% else %>
  <!-- Normal draw button (only show if player's turn and no penalty) -->
  <%= if current_player_turn?(@game_session, @current_player) do %>
    <button 
      phx-click="draw_card" 
      class="btn-primary bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded transition-all duration-200"
    >
      Draw Card
    </button>
  <% end %>
<% end %>
```

### Step 4: Add Helper Functions

**File**: `lib/kadi_web/live/game_live.ex`

**Location**: Add to private functions section (around line 300+)

```elixir
# Helper to determine if penalty button should be shown
defp show_penalty_button?(game_session, current_player) do
  game_session.draw_penalty != %{} and
  game_session.current_turn_player_id == current_player.id and
  game_session.status == "live"
end

# Helper to check if it's the current player's turn
defp current_player_turn?(game_session, current_player) do
  game_session.current_turn_player_id == current_player.id and
  game_session.status == "live"
end
```

### Step 5: Update Penalty Indicator Clearing

**File**: `lib/kadi_web/live/game_live.html.heex`

**Location**: Find penalty indicator display (search for "Penalty active" or similar)

**Add clearing logic** (FR-008: Clear before animation):
```heex
<%= if @game_session.draw_penalty != %{} and not @show_penalty_animation do %>
  <div class="penalty-indicator bg-red-100 border-red-500 text-red-700 p-3 rounded">
    <p class="font-bold">Penalty Active!</p>
    <p>Draw <%= @game_session.draw_penalty.pending_count %> cards or play a 2/Ace</p>
  </div>
<% end %>
```

**Key Logic**: Indicator hidden when `@show_penalty_animation == true` (cleared before animation starts per FR-008).

✅ **Checkpoint**: Verify template compiles with `mix phx.server`, check for syntax errors in browser console

---

## Phase 4: CSS Animations (30 minutes)

### Step 6: Add Animation Styles

**File**: `assets/css/app.css`

**Location**: Add at the end of the file (or in a custom section)

```css
/* Two Card Penalty Acceptance Animation */
.penalty-card-animation {
  animation: penalty-card-draw 400ms ease-out;
}

@keyframes penalty-card-draw {
  0% {
    transform: translateY(-100px) scale(0.8);
    opacity: 0;
  }
  60% {
    transform: translateY(10px) scale(1.05);
    opacity: 0.7;
  }
  100% {
    transform: translateY(0) scale(1);
    opacity: 1;
  }
}

/* Button styling (already in template classes, but can customize here) */
.btn-penalty {
  /* Tailwind classes applied in template - add custom styles if needed */
  animation: pulse-red 1s ease-in-out infinite;
}

@keyframes pulse-red {
  0%, 100% {
    box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.7);
  }
  50% {
    box-shadow: 0 0 0 10px rgba(239, 68, 68, 0);
  }
}
```

### Step 7: Apply Animation to Card Elements

**File**: `lib/kadi_web/live/game_live.html.heex`

**Location**: Find card rendering in player hand (search for card display loop)

**Before**:
```heex
<div class="card">
  <!-- card content -->
</div>
```

**After** (add animation class when triggered):
```heex
<div class={"card #{if @show_penalty_animation, do: "penalty-card-animation", else: ""}"}>
  <!-- card content -->
</div>
```

**Note**: The animation will only apply to newly added cards when `@show_penalty_animation` is true. You may want to add LiveView JS hooks for more precise control (see research.md for details).

✅ **Checkpoint**: Rebuild assets with `mix assets.build`, refresh browser to see animations

---

## Phase 5: Testing (45 minutes)

### Step 8: Add LiveView UI Tests

**File**: `test/kadi_web/live/game_live_test.exs`

**Location**: Add new describe block for penalty UI

```elixir
describe "Two Card penalty acceptance UI" do
  setup do
    # Create game with 2 players
    player1 = AccountsFixtures.player_fixture()
    player2 = AccountsFixtures.player_fixture()
    
    {:ok, game_session} = 
      CardGames.create_game_session(player1.id, %{name: "Test Game"})
    {:ok, game_session} = 
      CardGames.join_game_session(game_session.id, player2.id)
    {:ok, game_session} = 
      CardGames.start_game(game_session.id)
    
    # Set up penalty state
    game_session = %{game_session | draw_penalty: %{pending_count: 2, source_player_id: player2.id}}
    game_session = Repo.update!(Ecto.Changeset.change(game_session))
    
    %{game_session: game_session, player1: player1, player2: player2}
  end
  
  test "shows penalty button when penalty active and player's turn", %{
    game_session: game_session, 
    player1: player1
  } do
    {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")
    
    # Should show "Draw 2 Cards" button, not normal "Draw Card"
    assert view |> element("button", "Draw 2 Cards") |> has_element?()
    refute view |> element("button", "Draw Card") |> has_element?()
  end
  
  test "accepts penalty and draws cards on button click", %{
    game_session: game_session,
    player1: player1
  } do
    {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")
    
    initial_hand_size = length(CardGames.get_player_hand(game_session.id, player1.id))
    
    # Click penalty button
    view |> element("button", "Draw 2 Cards") |> render_click()
    
    # Wait for broadcast and re-fetch game state
    :timer.sleep(100)
    updated_game = Repo.get!(GameSession, game_session.id) |> Repo.preload(:players)
    
    # Verify penalty cleared
    assert updated_game.draw_penalty == %{}
    
    # Verify cards drawn
    final_hand_size = length(CardGames.get_player_hand(updated_game.id, player1.id))
    assert final_hand_size == initial_hand_size + 2
    
    # Verify turn advanced
    refute updated_game.current_turn_player_id == player1.id
  end
  
  test "shows error when not player's turn", %{
    game_session: game_session,
    player2: player2
  } do
    # player2 is NOT the current turn player
    game_session = %{game_session | current_turn_player_id: player1.id}
    game_session = Repo.update!(Ecto.Changeset.change(game_session))
    
    {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")
    
    # Try to click penalty button (should fail)
    view |> element("button", "Draw 2 Cards") |> render_click()
    
    # Should show error flash
    assert view |> element(".alert-error", "It's not your turn") |> has_element?()
  end
end
```

### Step 9: Run Tests

```bash
# Run all tests
mix test

# Run specific UI tests
mix test test/kadi_web/live/game_live_test.exs

# Run with warnings as errors
mix test --warnings-as-errors
```

✅ **Checkpoint**: All tests should pass. If not, review error messages and check against contracts in liveview_events.md

---

## Phase 6: Manual QA (15 minutes)

### Step 10: Manual Testing Checklist

Start the server:
```bash
mix phx.server
```

Open browser to `http://localhost:4000`

**Test Scenario 1: Happy Path**
1. Create account and log in as Player 1
2. Create new game
3. Join as Player 2 (open incognito window)
4. Start game as Player 1
5. Play a '2' card as Player 1 (current turn)
6. Verify:
   - ✅ Penalty indicator shows "Draw 2 cards or play a 2/Ace"
   - ✅ "Draw 2 Cards" button visible for Player 2
   - ✅ Normal "Draw Card" button hidden
7. Click "Draw 2 Cards" as Player 2
8. Verify:
   - ✅ Animation shows cards moving to hand (300-500ms)
   - ✅ Penalty indicator cleared BEFORE animation
   - ✅ 2 cards added to Player 2's hand
   - ✅ Turn advances to next player
   - ✅ Button changes back to "Draw Card" for new turn player

**Test Scenario 2: Strategic Choice (User Story 6)**
1. Same setup as Scenario 1
2. When penalty active, verify:
   - ✅ "Draw 2 Cards" button clickable
   - ✅ Player's own 2 or Ace cards also clickable
3. Click player's '2' card instead of button
4. Verify:
   - ✅ Penalty count increases to 4
   - ✅ Button updates to "Draw 4 Cards"
   - ✅ Turn advances without drawing

**Test Scenario 3: Error Handling**
1. Try clicking penalty button when not your turn
2. Verify:
   - ✅ Error flash: "It's not your turn"
   - ✅ No cards drawn
   - ✅ Game state unchanged

**Test Scenario 4: Multi-Device Sync (SPR-002)**
1. Open game in 2 browser windows (Player 1 and Player 2)
2. Player 1 plays a '2'
3. Verify:
   - ✅ Both windows show penalty indicator
   - ✅ Only Player 2's window shows "Draw 2 Cards" button
4. Player 2 clicks button
5. Verify:
   - ✅ Both windows update simultaneously
   - ✅ Both windows show animation
   - ✅ Both windows clear penalty indicator before animation

✅ **Checkpoint**: All manual tests pass. If issues found, review contracts and implementation.

---

## Phase 7: Code Quality (10 minutes)

### Step 11: Format and Compile Check

```bash
# Format all code
mix format

# Check compilation with warnings as errors
mix compile --warnings-as-errors

# Run Credo (if configured)
mix credo --strict
```

### Step 12: Commit Changes

```bash
# Stage changes
git add lib/kadi_web/live/game_live.ex
git add lib/kadi_web/live/game_live.html.heex
git add assets/css/app.css
git add test/kadi_web/live/game_live_test.exs

# Commit with descriptive message
git commit -m "Add explicit Two Card penalty acceptance button with animations

- Add accept_penalty event handler to GameLive
- Replace normal draw button with penalty button when active
- Implement 300-500ms card draw animation
- Clear penalty indicator before animation starts (FR-008)
- Add strategic choice: button + blocking cards both clickable
- Add specific error messages for edge cases
- Add LiveView UI tests for penalty acceptance flow
- Reuse existing CardGames.process_draw_penalty/2 backend

Closes: Feature 009 UI improvements
Tests: All passing (mix test)
Refs: specs/009-two-card/spec.md Session 2025-11-15"
```

✅ **Checkpoint**: Changes committed, ready for PR or deployment

---

## Troubleshooting

### Issue: Button not showing when penalty active

**Check**:
1. Is `game_session.draw_penalty` a non-empty map? (Debug in IEx: `game_session.draw_penalty`)
2. Is `current_turn_player_id` matching `current_player.id`? (Check socket assigns)
3. Is game status "live"? (Check `game_session.status`)

**Solution**: Review `show_penalty_button?/2` logic in game_live.ex

### Issue: Animation not playing

**Check**:
1. Are assets rebuilt? (Run `mix assets.build`)
2. Is `@show_penalty_animation` set to true? (Check LiveView inspector)
3. Are CSS classes applied to correct elements? (Inspect browser DevTools)

**Solution**: Review `handle_info({:game_updated, ...})` and template classes

### Issue: Cards not drawn after button click

**Check**:
1. Is `CardGames.process_draw_penalty/2` being called? (Add `IO.inspect` in event handler)
2. Are there enough cards in deck? (Check deck_cards count)
3. Is PubSub broadcast firing? (Check `handle_info` receives message)

**Solution**: Review backend logs, verify transaction completes successfully

### Issue: Error flash shows but still draws cards

**Check**:
1. Is error returned from backend? (Check `case` statement branches)
2. Is socket updated on error path? (Should only update on success via broadcast)

**Solution**: Ensure `{:error, reason}` paths return `{:noreply, put_flash(socket, :error, ...)}`

---

## Next Steps

After completing this implementation:

1. **Deploy to staging**: Test with multiple concurrent users
2. **Monitor performance**: Verify <100ms response times (FR-007)
3. **Gather feedback**: User testing for animation smoothness and clarity
4. **Iterate**: Adjust animation duration or button styling based on feedback
5. **Document**: Update README.md with new UI behavior

---

## References

- **Specification**: `spec.md` (Session 2025-11-15)
- **Plan**: `plan.md`
- **Contracts**: `contracts/liveview_events.md`
- **Research**: `research.md`
- **Data Model**: `data-model.md`
- **Backend Implementation**: `lib/kadi/card_games.ex` lines 487-543
- **Existing Tests**: `test/kadi/card_games/special_cards_two_test.exs` lines 856-959 (SPR-002)

---

## Estimated Time Breakdown

| Phase | Duration | Complexity |
|-------|----------|------------|
| 1. Backend Verification | 5 min | Low |
| 2. LiveView Event Handler | 30 min | Medium |
| 3. Template Updates | 45 min | Medium |
| 4. CSS Animations | 30 min | Medium |
| 5. Testing | 45 min | High |
| 6. Manual QA | 15 min | Low |
| 7. Code Quality | 10 min | Low |
| **Total** | **3 hours** | **Moderate** |

Good luck with the implementation! 🎴
