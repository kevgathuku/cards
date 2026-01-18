# Elixir Phoenix LiveView Implementation Reference

## Overview

This document provides a reference for the archived Elixir/Phoenix LiveView implementation of Kadi, which exists in the `archive/elixir-implementation` branch. The LiveView version uses real-time WebSocket connections for multiplayer gameplay, compared to the current Clojure implementation which uses HTMX with polling.

## Accessing the Archived Implementation

### View Individual Files

```bash
# View any file from the archived branch
git show archive/elixir-implementation:path/to/file

# Examples:
git show archive/elixir-implementation:lib/kadi_web/live/lobby_live.ex
git show archive/elixir-implementation:lib/kadi_web/live/game_live.ex
git show archive/elixir-implementation:lib/kadi_web/router.ex
```

### List All Files

```bash
# List all files in a directory
git ls-tree -r --name-only archive/elixir-implementation:lib/kadi_web/live/

# List entire project structure
git ls-tree -r --name-only archive/elixir-implementation
```

### Checkout the Branch (Temporary)

```bash
# Create a temporary branch to explore
git checkout -b temp-elixir archive/elixir-implementation

# When done, switch back
git checkout main
git branch -D temp-elixir
```

### Compare Files

```bash
# Compare Elixir vs Clojure implementations
git show archive/elixir-implementation:lib/kadi_web/live/game_live.ex > /tmp/elixir_game.ex
# Then manually compare with src/kadi/views.clj
```

---

## Architecture Comparison

| Aspect | Elixir LiveView | Clojure HTMX |
|--------|-----------------|--------------|
| **Framework** | Phoenix LiveView 1.7 | Ring + Reitit + Hiccup |
| **Real-time** | WebSocket (bidirectional) | HTTP polling (3s intervals) |
| **State** | Server-side socket assigns | Database + session |
| **UI Updates** | Automatic DOM diffing | Manual HTML swap |
| **Events** | `phx-click`, `phx-submit` | `hx-post`, `hx-get` |
| **Database** | PostgreSQL + Ecto | SQLite |
| **Authentication** | `bcrypt_elixir` + sessions | Magic links (stubbed) |

---

## Key LiveView Files

### 1. Lobby Page
**File**: `lib/kadi_web/live/lobby_live.ex`

```bash
git show archive/elixir-implementation:lib/kadi_web/live/lobby_live.ex
```

**Purpose**: Main landing page after login showing in-progress games

**Key Features**:
- Lists all games for current player
- "Create Game" button → generates short code
- Shows game details: short code, creator, player count, status
- Real-time updates (no polling needed)

**Socket Assigns**:
- `games` - List of player's game sessions
- `current_player` - Authenticated player record

**Events**:
- `"create_game"` - Creates new game with random short code, redirects to game page

**Template**: `lib/kadi_web/live/lobby_live.html.heex`
```bash
git show archive/elixir-implementation:lib/kadi_web/live/lobby_live.html.heex
```

---

### 2. Join Game Page
**File**: `lib/kadi_web/live/join_live.ex`

```bash
git show archive/elixir-implementation:lib/kadi_web/live/join_live.ex
```

**Purpose**: Enter short code to join existing game

**Key Features**:
- Simple form with short code input
- Validates code exists in database
- Handles already-joined players (redirects without error)
- Flash messages for errors

**Events**:
- `"join_game"` - Looks up game by short code, adds player, redirects

**Template**: Inline render function using `~H"""` sigil

---

### 3. Game Play Page
**File**: `lib/kadi_web/live/game_live.ex` (primary gameplay logic, ~300 LOC)

```bash
git show archive/elixir-implementation:lib/kadi_web/live/game_live.ex
```

**Purpose**: Real-time multiplayer gameplay interface

#### Socket Assigns (Client State)
```elixir
@impl true
def mount(_params, _session, socket) do
  {:ok, assign(socket,
    game_session: nil,              # Full game state
    player_hand: [],                # Current player's cards
    played_pile: [],                # Cards on table
    deck_size: 0,                   # Remaining deck cards
    current_turn_player: nil,       # Whose turn it is
    other_players_hands: [],        # Other players (counts only)
    selected_cards: [],             # Cards clicked for playing
    direction: "clockwise",         # Turn order
    toast: nil,                     # Toast notification
    toast_timer: nil,               # Auto-dismiss timer
    show_penalty_animation: false,  # Animation trigger
    ace_blocked_penalty_info: %{}   # Ace blocking state
  )}
end
```

#### Real-time Subscription
```elixir
@impl true
def handle_params(%{"game_id" => game_id}, _uri, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(Kadi.PubSub, "game:#{game_id}")
  end
  # ...
end

@impl true
def handle_info(%Broadcast{event: "game_updated", payload: %{game_session: game}}, socket) do
  # Server pushes updates to all connected clients
  # Automatically updates DOM via LiveView diffing
end
```

#### Event Handlers

| Event | Purpose | Server Action |
|-------|---------|---------------|
| `"start_game"` | Transition lobby → live | Deal cards, set first player |
| `"draw_card"` | Draw from deck/recycle | Add card to hand, advance turn |
| `"toggle_card"` | Select/deselect card | Client-side only (assigns) |
| `"play_cards"` | Play selected cards | Validate, apply effects, broadcast |
| `"select_suit"` | Choose suit after Ace | Set `action_suit`, advance turn |
| `"accept_penalty"` | Draw penalty voluntarily | Draw N cards, clear penalty, advance turn |

#### Smart UI Features

**Conditional Rendering**:
```elixir
# Start button (only for creator in lobby)
<%= if @game_session.status == "lobby" and @current_player.id == @game_session.created_by_id do %>
  <.button phx-click="start_game">Start Game</.button>
<% end %>

# Penalty accept button (only when penalty active on you)
<%= if show_penalty_button?(@game_session, @current_player.id) do %>
  <.button phx-click="accept_penalty">Draw {count} Cards</.button>
<% end %>

# Suit selector (only after playing Ace)
<%= if @game_session.action_type == "select_suit" and @current_turn_player.id == @current_player.id do %>
  <.button phx-click="select_suit" phx-value-suit="hearts">♥ Hearts</.button>
  <!-- ... -->
<% end %>
```

**Card Highlighting**:
```elixir
defp card_class(is_selected, matches_required_suit, is_blocking_card) do
  cond do
    is_selected -> "bg-blue-100 border-blue-500 border-2 -translate-y-2"  # Selected
    matches_required_suit -> "bg-green-100 border-green-500 border-2"    # Valid play
    is_blocking_card -> "bg-green-100 border-green-500 border-2"         # Can block penalty
    true -> "bg-white hover:bg-gray-50"                                   # Default
  end
end
```

**Toast Notification System**:
```elixir
# Auto-dismiss after 2 seconds, prevents spam via coalescing
@toast_coalesce_ms 2000

# Set toast with timer
timer_ref = Process.send_after(self(), :clear_toast, @toast_coalesce_ms)
assign(socket, toast: %{message: "...", type: :info}, toast_timer: timer_ref)

# Auto-clear handler
@impl true
def handle_info(:clear_toast, socket) do
  {:noreply, assign(socket, toast: nil, toast_timer: nil)}
end
```

**Penalty Animation**:
- Cards animate when penalty drawn
- Penalty indicator hides during animation
- CSS class: `"penalty-card-animation"`

**Error Handling** (context-aware):
```elixir
error_msg = if draw_penalty["active"] == true do
  "Penalty Active. You must play blocking card or draw penalty cards"
else
  if game_session.action_suit do
    "Invalid play - must match suit (#{action_suit}) or play Ace"
  else
    "Invalid play - card(s) don't match"
  end
end
```

#### Helper Functions
```elixir
# Display helpers
defp direction_label("clockwise"), do: "Clockwise ↻"
defp direction_label("counterclockwise"), do: "Counterclockwise ↺"
defp suit_symbol("hearts"), do: "♥"
defp suit_symbol("diamonds"), do: "♦"
# ...

# Business logic helpers
defp show_penalty_button?(game_session, current_player_id)
defp check_and_show_penalty_notification(socket, game_session, player_id)
defp find_penalty_creator(game_session)
```

**Template**: `lib/kadi_web/live/game_live.html.heex` (~300 LOC)
```bash
git show archive/elixir-implementation:lib/kadi_web/live/game_live.html.heex
```

---

### 4. Router Configuration
**File**: `lib/kadi_web/router.ex`

```bash
git show archive/elixir-implementation:lib/kadi_web/router.ex
```

**LiveView Sessions** (authentication scopes):

```elixir
# 1. Redirect if already authenticated (login/register pages)
live_session :redirect_if_player_is_authenticated,
  on_mount: [{KadiWeb.PlayerAuth, :redirect_if_player_is_authenticated}] do
  live "/players/register", PlayerRegistrationLive, :new
  live "/players/log_in", PlayerLoginLive, :new
end

# 2. Require authentication (game pages)
live_session :require_authenticated_player,
  on_mount: [{KadiWeb.PlayerAuth, :ensure_authenticated}] do
  live "/lobby", LobbyLive, :index
  live "/games/:game_id", GameLive, :show
  live "/join", JoinLive, :index
end

# 3. Current player context (email confirmation)
live_session :current_player,
  on_mount: [{KadiWeb.PlayerAuth, :mount_current_player}] do
  live "/players/confirm/:token", PlayerConfirmationLive, :edit
end
```

**Key Difference**: All game interactions are LiveView events, **no REST API endpoints** for gameplay.

---

### 5. Authentication
**File**: `lib/kadi_web/player_auth.ex`

```bash
git show archive/elixir-implementation:lib/kadi_web/player_auth.ex
```

**Features**:
- `bcrypt` password hashing
- Session-based authentication
- `on_mount` hooks for LiveView protection
- Remember me token support

**Callbacks**:
- `mount_current_player` - Fetch player from session
- `ensure_authenticated` - Redirect if not logged in
- `redirect_if_player_is_authenticated` - Skip login if already authenticated

---

## Database Schema (PostgreSQL + Ecto)

### Core Tables

```bash
# View migration files
git show archive/elixir-implementation:priv/repo/migrations/
```

**`players`**:
- `id`, `email`, `hashed_password`, `confirmed_at`

**`game_sessions`**:
- `id`, `short_code`, `status` (lobby/live/completed)
- `current_turn_player_id`, `direction`, `action_type`, `action_suit`
- `draw_penalty` (JSONB) - `{active: bool, target_player_id: int, penalty_type: string}`
- `created_by_id` (FK to players)

**`game_session_players`** (join table):
- `game_session_id`, `player_id`, `status` (cardless/playing)

**`deck_cards`** (deck state):
- `game_session_id`, `card_id`, `position`

**`player_hand_cards`** (hands):
- `game_session_id`, `player_id`, `card_id`, `position`

**`played_pile_cards`** (played stack):
- `game_session_id`, `card_id`, `position`

**`cards`** (reference data):
- `id`, `rank`, `suit`

---

## Key Patterns & Techniques

### 1. **Optimistic UI Updates**
LiveView waits for server broadcast instead of updating socket immediately:
```elixir
def handle_event("play_cards", _params, socket) do
  case CardGames.play_cards(game_session, player_id, cards) do
    {:ok, _updated_game_session} ->
      # Don't assign here - wait for PubSub broadcast
      {:noreply, assign(socket, selected_cards: [])}
  end
end
```

### 2. **Toast Coalescing**
Prevents notification spam by canceling previous timer:
```elixir
if socket.assigns.toast_timer do
  Process.cancel_timer(socket.assigns.toast_timer)
end
timer_ref = Process.send_after(self(), :clear_toast, 2000)
```

### 3. **Auto-clear Selection on Turn Change**
```elixir
socket = if old_turn_player_id != new_turn_player_id and 
            new_turn_player_id != current_player_id do
  assign(socket, selected_cards: [])
else
  socket
end
```

### 4. **Preloaded Associations**
Backend sends fully preloaded game state to avoid N+1 queries in LiveView:
```elixir
# In CardGames context
def get_game_session_preloaded(id) do
  Repo.get(GameSession, id)
  |> Repo.preload([:created_by, :current_turn_player, 
                   game_session_players: :player])
end
```

### 5. **Form State in LiveView**
No hidden inputs needed - state lives in socket assigns:
```elixir
# Toggle card selection
def handle_event("toggle_card", %{"card_id" => card_id_str}, socket) do
  card_id = String.to_integer(card_id_str)
  updated = if card_id in socket.assigns.selected_cards do
    List.delete(socket.assigns.selected_cards, card_id)
  else
    [card_id | socket.assigns.selected_cards]
  end
  {:noreply, assign(socket, selected_cards: updated)}
end
```

---

## Features Not in Clojure Implementation

### 1. **Direction Reversal Indicator**
Visual feedback when King played:
```elixir
<div class="flex items-center justify-center gap-2">
  <.icon name={direction_icon(@direction)} class="w-5 h-5" />
  <span>Turn Order: {direction_label(@direction)}</span>
</div>
```

### 2. **Persistent Penalty Indicator**
Always visible red box when penalty active:
```elixir
<div class="penalty-indicator border-2 border-red-400 bg-red-50">
  <p>Draw {penalty_count} Penalty Active</p>
  <p>{target_player} must draw or block with {blocking_cards}</p>
</div>
```

### 3. **Required Suit Display**
Purple box showing active suit requirement:
```elixir
<%= if @game_session.action_suit do %>
  <div class="bg-purple-100 border-purple-300">
    <p>Required Suit: {suit_symbol(action_suit)} {action_suit}</p>
  </div>
<% end %>
```

### 4. **Cardless Player Badges**
Visual indicator for players with no cards:
```elixir
<%= if Map.get(@player_statuses, player.id) == "cardless" do %>
  <span class="bg-purple-100 text-purple-800">Cardless</span>
<% end %>
```

### 5. **Penalty Acceptance Animation**
Cards animate when penalty drawn, indicator temporarily hides.

### 6. **Smart Card Highlighting**
Three states: selected (blue), valid play (green), default (white)

### 7. **Context-Aware Error Messages**
Different messages based on game state (penalty active vs suit requirement vs general invalid)

---

## Testing Patterns

**File**: `test/kadi_web/live/game_live_test.exs`

```bash
git show archive/elixir-implementation:test/kadi_web/live/game_live_test.exs
```

**LiveView Testing**:
```elixir
test "renders lobby for unauthenticated player", %{conn: conn} do
  {:ok, _view, html} = live(conn, ~p"/lobby")
  assert html =~ "Create game"
end

test "handles play_cards event", %{conn: conn, game_session: game} do
  {:ok, view, _html} = live(conn, ~p"/games/#{game.id}")
  
  view
  |> element("button", "Play Selected Cards")
  |> render_click()
  
  assert has_element?(view, ".played-pile")
end
```

**Async Testing** (simulates real-time):
```elixir
# Subscribe to PubSub in test
Phoenix.PubSub.subscribe(Kadi.PubSub, "game:#{game.id}")

# Trigger action in one process
Task.start(fn -> CardGames.play_cards(game, player_id, cards) end)

# Assert broadcast received
assert_receive %Broadcast{event: "game_updated"}
```

---

## Advantages of LiveView Architecture

1. **Real-time by Default**: No polling needed, instant updates for all players
2. **Server-side State**: No client-side state management complexity
3. **Automatic DOM Updates**: LiveView diffs and patches DOM efficiently
4. **Type Safety**: Ecto schemas provide compile-time guarantees
5. **Connection Management**: Phoenix handles WebSocket reconnection automatically
6. **Presence Tracking**: Can see when players disconnect (not implemented)
7. **Minimal JavaScript**: No React/Vue/Alpine needed for interactivity

---

## Migration Path (Elixir → Clojure)

If implementing LiveView patterns in Clojure/HTMX:

### Already Implemented ✅
- Lobby with game list
- Join by short code
- Start game button
- Turn-based play validation
- Flash messages

### Could Add 🚀
1. **WebSocket Updates**: Use Sente (already in deps.edn) instead of polling
2. **Toast System**: Auto-dismissing notifications with timers
3. **Direction Indicator**: Show clockwise/counterclockwise with icon
4. **Penalty Indicator**: Persistent red box when penalty active
5. **Required Suit Display**: Purple box for Ace suit requirement
6. **Card Highlighting**: Green border for valid plays
7. **Cardless Badges**: Visual indicator for players with no cards
8. **Better Error Messages**: Context-aware based on game state
9. **Selection State**: Track selected cards in session
10. **Penalty Animation**: Visual feedback when drawing cards

---

## Useful Git Commands Reference

```bash
# Browse all LiveView files
git ls-tree -r --name-only archive/elixir-implementation:lib/kadi_web/live/

# View specific file
git show archive/elixir-implementation:lib/kadi_web/live/game_live.ex

# Compare two branches (file by file)
git diff archive/elixir-implementation main -- path/to/file

# Search for keyword in archived branch
git grep "penalty" archive/elixir-implementation -- "*.ex"

# Show file at specific commit
git show <commit-hash>:path/to/file

# List all commits on archived branch
git log archive/elixir-implementation --oneline

# Diff entire directory structure
git diff --name-status archive/elixir-implementation main
```

---

## Related Documentation

- [CLOJURE_BOOTSTRAP_BRIEF.md](./CLOJURE_BOOTSTRAP_BRIEF.md) - Current Clojure implementation spec
- [README.md](../README.md) - Current project setup
- Phoenix LiveView Docs: https://hexdocs.pm/phoenix_live_view

---

**Last Updated**: January 18, 2026  
**Branch**: `archive/elixir-implementation`  
**Archived Reason**: Migrated to Clojure for simpler deployment and functional purity
