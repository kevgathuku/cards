# Quickstart: King Card Reversal Feature

**References**: 
- Complete requirements: `spec.md`
- Schema design: `data-model.md`
- Events contract: `contracts/events.md`
- Design decisions: `research.md`

---

## Implementation Sequence

**Dependencies**: Each phase depends on the previous phase completing.

### Phase 1: Data Layer (no code dependencies)
1. Create migrations → Run migrations → Update schemas

### Phase 2: Business Logic (depends on Phase 1)
2. Extend validator → Add direction-aware turn logic → Implement King reversal → Add cardless handling

### Phase 3: Observability (depends on Phase 2)
3. Add telemetry emission → Attach handlers

### Phase 4: UI (depends on Phase 2, 3)
4. Update LiveView → Add indicators → Add toast

### Phase 5: Testing (depends on all above)
5. Unit tests → Integration tests → LiveView tests → Telemetry tests

---

## 1. Apply Migrations

### 1.1 Create Direction Migration
**File**: `priv/repo/migrations/YYYYMMDDHHMMSS_add_direction_to_game_sessions.exs`  
**Template**: See `priv/repo/migrations/20251107172808_add_top_card_to_game_sessions.exs` for structure  
**Reference**: data-model.md §2.1

```elixir
defmodule Kadi.Repo.Migrations.AddDirectionToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :direction, :string, default: "clockwise", null: false
    end

    create constraint(:game_sessions, :direction_must_be_valid,
             check: "direction IN ('clockwise', 'counter_clockwise')"
           )
  end
end
```

### 1.2 Create Status Migration
**File**: `priv/repo/migrations/YYYYMMDDHHMMSS_add_status_to_game_session_players.exs`  
**Reference**: data-model.md §2.2

```elixir
defmodule Kadi.Repo.Migrations.AddStatusToGameSessionPlayers do
  use Ecto.Migration

  def change do
    alter table(:game_session_players) do
      add :status, :string, default: "normal", null: false
    end

    create constraint(:game_session_players, :status_must_be_valid,
             check: "status IN ('normal', 'cardless')"
           )
  end
end
```

### 1.3 Run Migrations
```bash
mix ecto.migrate
```

---

## 2. Update Schemas

### 2.1 GameSession Schema
**File**: `lib/kadi/games/game_session.ex`  
**Current**: Lines 1-30  
**Reference**: data-model.md §2.1

**Add module attribute** (after line 5):
```elixir
@directions ["clockwise", "counter_clockwise"]
```

**Add field** to schema block (after line 8, after `status` field):
```elixir
field :direction, :string, default: "clockwise"
```

**Update changeset** (line 23, update cast and validate):
```elixir
# Change from:
|> cast(attrs, [:short_code, :created_by_id, :status, :current_turn_player_id, :top_card_id])

# To:
|> cast(attrs, [:short_code, :created_by_id, :status, :direction, :current_turn_player_id, :top_card_id])
|> validate_required([:short_code, :created_by_id, :status, :direction])
|> validate_inclusion(:direction, @directions)
```

### 2.2 GameSessionPlayer Schema
**File**: `lib/kadi/games/game_session_player.ex`  
**Current**: Lines 1-20  
**Reference**: data-model.md §2.2, events.md §2.4

**Add module attribute** (after line 4):
```elixir
@player_statuses ["normal", "cardless"]
```

**Add field** to schema block (after line 8, after `player_id`):
```elixir
field :status, :string, default: "normal"
```

**Update changeset** (line 14):
```elixir
# Change from:
|> cast(attrs, [:game_session_id, :player_id])

# To:
|> cast(attrs, [:game_session_id, :player_id, :status])
|> validate_inclusion(:status, @player_statuses)

```

---

## 3. Implement King Logic

### 3.1 Extend PlayValidator
**File**: `lib/kadi/games/play_validator.ex`  
**Current**: Lines 1-107 (regular cards only)  
**Integration Point**: Add after line 44, before `player_has_cards?/2`  
**Reference**: spec.md FR-001, FR-004, FR-005

**Add to module attributes** (after line 18):
```elixir
@special_ranks ["king"]
```

**Add new validation function** (after line 44):
```elixir
@doc """
Validates if a King card play is valid.

Rules:
- Single King: Must match suit OR rank of top card
- Multiple Kings: Rejected (only one King per turn - FR-005)
- King in combo with other cards: Rejected (Phase 1 limitation)
"""
def valid_king_play?([], _top_card), do: false
def valid_king_play?(_cards, nil), do: false

def valid_king_play?([%{rank: "king"} = king_card], top_card) do
  matches_suit_or_rank?(king_card, top_card)
end

def valid_king_play?([%{rank: "king"} | _rest], _top_card) do
  false  # Multiple Kings or King in combo - reject per FR-005
end

def valid_king_play?(_cards, _top_card), do: false

# Helper (add if not already present at line 85)
defp matches_suit_or_rank?(card, top_card) do
  card.suit == top_card.suit or card.rank == top_card.rank
end
```

**Update main validation** (modify `valid_play?/2` around line 33-44):
```elixir
def valid_play?(cards, top_card) when is_list(cards) do
  cond do
    Enum.any?(cards, &(&1.rank == "king")) ->
      valid_king_play?(cards, top_card)
    
    all_regular_cards?(cards) and length(cards) == 1 ->
      validate_single_card(hd(cards), top_card)
    
    all_regular_cards?(cards) ->
      validate_combo(cards, top_card)
    
    true ->
      false  # Other special cards not yet implemented
  end
end
```

### 3.2 Add Direction-Aware Turn Progression
**File**: `lib/kadi/card_games.ex`  
**Current**: `get_next_player/2` at line 697-706  
**Integration Point**: Add new functions after line 706  
**Reference**: spec.md FR-002, FR-008, FR-009

**Add new helper functions** (after line 706):
```elixir
@doc """
Returns the next player based on current game direction.

In clockwise: player1 → player2 → player3 → player1
In counter_clockwise: player1 → player3 → player2 → player1

For 2-player games, direction has no effect (FR-009).
"""
defp get_next_player_with_direction(players, current_player_id, direction) do
  player_count = length(players)
  
  if player_count == 2 do
    # 2-player: direction irrelevant per FR-009
    get_next_player(players, current_player_id)
  else
    case direction do
      "clockwise" ->
        get_next_player(players, current_player_id)
      
      "counter_clockwise" ->
        get_previous_player(players, current_player_id)
    end
  end
end

defp get_previous_player(players, current_player_id) do
  current_index = Enum.find_index(players, &(&1.id == current_player_id))
  prev_index = rem(current_index - 1 + length(players), length(players))
  Enum.at(players, prev_index)
end

defp reverse_direction("clockwise"), do: "counter_clockwise"
defp reverse_direction("counter_clockwise"), do: "clockwise"
```

### 3.3 Implement King Reversal in play_cards
**File**: `lib/kadi/card_games.ex`  
**Current**: `execute_play/3` at lines 571-615  
**Replace entire function** with King-aware version  
**Reference**: spec.md FR-002, FR-003, FR-011, FR-015, FR-020

```elixir
defp execute_play(game_session, player, cards_to_play) do
  require Logger
  
  # Get current max order_index in played_stack
  max_order = get_max_played_stack_order(game_session)

  # Detect King play (FR-002)
  king_played? = Enum.any?(cards_to_play, &(&1.rank == "king"))
  
  # Calculate new direction (FR-002)
  new_direction = if king_played? do
    reverse_direction(game_session.direction)
  else
    game_session.direction
  end

  # Get next player with new direction (FR-008)
  players = get_game_session_players(game_session.id)
  player_count = length(players)
  next_player = get_next_player_with_direction(players, player.id, new_direction)

  # Check if player will be cardless after this play (FR-011)
  player_hand = get_player_hand_count(game_session, player.id)
  cards_played_count = length(cards_to_play)
  will_be_cardless = (player_hand == cards_played_count) and king_played?

  # Build transaction
  multi = Ecto.Multi.new()

  # Move each card to played_stack
  multi_with_cards =
    cards_to_play
    |> Enum.with_index(1)
    |> Enum.reduce(multi, fn {card, idx}, acc_multi ->
      deck_card = find_player_deck_card(game_session, player.id, card.id)
      new_order = max_order + idx

      changeset =
        DeckCard.changeset(deck_card, %{
          location_type: "played_stack",
          order_index: new_order,
          player_id: nil
        })

      Ecto.Multi.update(acc_multi, {:move_card, idx}, changeset)
    end)

  # Update game_session with new direction and turn (FR-002, FR-015)
  last_card = List.last(cards_to_play)
  
  multi_with_game =
    Ecto.Multi.update(
      multi_with_cards,
      :game_session,
      GameSession.changeset(game_session, %{
        top_card_id: last_card.id,
        current_turn_player_id: next_player.id,
        direction: new_direction
      })
    )

  # Update player status if cardless (FR-011, FR-026)
  multi_with_status = if will_be_cardless do
    player_session = Repo.get_by!(GameSessionPlayer, 
      game_session_id: game_session.id,
      player_id: player.id
    )
    
    Ecto.Multi.update(
      multi_with_game,
      :player_status,
      GameSessionPlayer.changeset(player_session, %{status: "cardless"})
    )
  else
    multi_with_game
  end

  # Execute transaction
  case Repo.transaction(multi_with_status) do
    {:ok, results} ->
      updated_game = results.game_session
      
      # Emit telemetry events (FR-020)
      if king_played? do
        emit_direction_change_event(
          game_session.id,
          player.id,
          game_session.direction,
          new_direction,
          last_card.id,
          player_count == 2  # neutral flag for 2-player (FR-009)
        )
      end
      
      if will_be_cardless do
        emit_cardless_event(game_session.id, player.id, last_card.id)
      end
      
      # Reload with fresh associations
      reloaded =
        GameSession
        |> Repo.get!(updated_game.id)
        |> Repo.preload(:created_by)

      {:ok, reloaded}

    {:error, _op, failed_value, _changes} ->
      {:error, failed_value}
  end
end

# Helper to count player's hand
defp get_player_hand_count(game_session, player_id) do
  game_session.deck.deck_cards
  |> Enum.count(&(&1.location_type == "player_hand" and &1.player_id == player_id))
end
```

---

## 4. Player Status Handling (Cardless Auto-Draw)

### 4.1 Update draw_card_from_deck
**File**: `lib/kadi/card_games.ex`  
**Current**: Lines 215-285  
**Integration Point**: Insert after line 227 (after turn validation)  
**Reference**: spec.md FR-012, FR-013, FR-014

**Add cardless check** (after turn validation around line 227):
```elixir
# Check if player is cardless and handle auto-draw (FR-012)
player_session = Repo.get_by!(GameSessionPlayer,
  game_session_id: game_session.id,
  player_id: player_id
)

is_cardless = player_session.status == "cardless"
```

**Update transaction builder** (modify around line 262):
```elixir
multi =
  Ecto.Multi.new()
  |> Ecto.Multi.update(
    :deck_card,
    DeckCard.changeset(card_to_draw, %{
      location_type: "player_hand",
      player_id: player_id,
      order_index: nil
    })
  )

# If player was cardless, reset status (FR-013)
multi_with_status = if is_cardless do
  Ecto.Multi.update(
    multi,
    :player_status,
    GameSessionPlayer.changeset(player_session, %{status: "normal"})
  )
else
  multi
end

multi_with_game = Ecto.Multi.update(
  multi_with_status,
  :game_session,
  GameSession.changeset(game_session, %{
    current_turn_player_id: next_player.id
  })
)
```

---

## 5. Telemetry Events

### 5.1 Add Telemetry Helper Functions
**File**: `lib/kadi/card_games.ex`  
**Location**: Add at end of module (after line 730)  
**Reference**: contracts/events.md, spec.md FR-020

```elixir
# Telemetry event emission helpers

defp emit_direction_change_event(game_id, player_id, old_dir, new_dir, card_id, neutral?) do
  :telemetry.execute(
    [:kadi, :king, :direction_change],
    %{},
    %{
      game_id: game_id,
      player_id: player_id,
      previous_direction: old_dir,
      new_direction: new_dir,
      card_id: card_id,
      neutral: neutral?,
      timestamp: DateTime.utc_now()
    }
  )
end

defp emit_cardless_event(game_id, player_id, card_id) do
  :telemetry.execute(
    [:kadi, :king, :cardless_entered],
    %{},
    %{
      game_id: game_id,
      player_id: player_id,
      reason: "king_last_card",
      card_id: card_id,
      timestamp: DateTime.utc_now()
    }
  )
end

defp emit_anomaly_skip_event(game_id, player_id, deck_state) do
  :telemetry.execute(
    [:kadi, :king, :anomaly_skip],
    %{},
    %{
      game_id: game_id,
      player_id: player_id,
      deck_state: deck_state,
      timestamp: DateTime.utc_now()
    }
  )
end
```

### 5.2 Attach Telemetry Handlers
**File**: `lib/kadi/application.ex`  
**Location**: In `start/2` after children definition  
**Reference**: contracts/events.md §3

```elixir
# Attach telemetry handlers for King feature
:telemetry.attach_many(
  "king-card-telemetry",
  [
    [:kadi, :king, :direction_change],
    [:kadi, :king, :cardless_entered],
    [:kadi, :king, :anomaly_skip]
  ],
  &handle_king_telemetry/4,
  nil
)

# Add handler function (private, at end of module)
defp handle_king_telemetry(event, _measurements, metadata, _config) do
  require Logger
  event_name = Enum.join(event, ".")
  Logger.info("#{event_name}: #{inspect(metadata)}")
end
```

---

## 6. LiveView UI Updates

### 6.1 Update GameLive Assigns
**File**: `lib/kadi_web/live/game_live.ex`  
**Reference**: contracts/events.md §2

**Add to mount or game_updated handler**:
```elixir
assign(socket,
  direction: game_session.direction,
  player_statuses: build_player_statuses_map(game_session),
  toast: nil,
  banner: nil
)

defp build_player_statuses_map(game_session) do
  game_session.game_session_players
  |> Enum.into(%{}, fn gsp -> {gsp.player_id, gsp.status} end)
end
```

### 6.2 Add Direction Indicator
**File**: `lib/kadi_web/live/game_live.html.heex`  
**Reference**: spec.md FR-022, SC-010

```heex
<div class="direction-indicator" role="status" aria-live="polite">
  <.icon name={direction_icon(@direction)} class="w-5 h-5" />
  <span class="font-medium text-gray-900">
    <%= direction_label(@direction) %>
  </span>
</div>
```

**Add helpers in game_live.ex**:
```elixir
defp direction_icon("clockwise"), do: "arrow-rotate-right"
defp direction_icon("counter_clockwise"), do: "arrow-rotate-left"

defp direction_label("clockwise"), do: gettext("Clockwise")
defp direction_label("counter_clockwise"), do: gettext("Counter-clockwise")
```

### 6.3 Add Toast Coalescing
**File**: `lib/kadi_web/live/game_live.ex`  
**Reference**: spec.md FR-025, SC-013

```elixir
@toast_coalesce_ms 2000

def handle_info(%{event: "game_updated", payload: %{game_session: game}}, socket) do
  old_direction = socket.assigns.direction
  new_direction = game.direction
  
  socket = if old_direction != new_direction do
    # Cancel existing toast timer if any
    if socket.assigns[:toast_timer] do
      Process.cancel_timer(socket.assigns.toast_timer)
    end
    
    # Set new toast with timer (FR-025)
    timer_ref = Process.send_after(self(), :clear_toast, @toast_coalesce_ms)
    
    assign(socket,
      direction: new_direction,
      toast: %{
        message: gettext("Direction reversed: now %{direction}", 
                         direction: direction_label(new_direction)),
        updated_at: System.monotonic_time()
      },
      toast_timer: timer_ref
    )
  else
    assign(socket, direction: new_direction)
  end
  
  {:noreply, socket}
end

def handle_info(:clear_toast, socket) do
  {:noreply, assign(socket, toast: nil, toast_timer: nil)}
end
```

---

## 7. Tests

### 7.1 Unit Tests - PlayValidator
**File**: `test/kadi/games/play_validator_test.exs`

```elixir
describe "valid_king_play?/2" do
  test "accepts single King matching suit" do
    top_card = %Card{suit: "hearts", rank: "5"}
    king = %Card{suit: "hearts", rank: "king"}
    assert PlayValidator.valid_king_play?([king], top_card)
  end
  
  test "accepts single King matching rank" do
    top_card = %Card{suit: "hearts", rank: "king"}
    king = %Card{suit: "spades", rank: "king"}
    assert PlayValidator.valid_king_play?([king], top_card)
  end
  
  test "rejects King not matching suit or rank" do
    top_card = %Card{suit: "hearts", rank: "5"}
    king = %Card{suit: "spades", rank: "king"}
    refute PlayValidator.valid_king_play?([king], top_card)
  end
  
  test "rejects multiple Kings (FR-005)" do
    top_card = %Card{suit: "hearts", rank: "king"}
    kings = [
      %Card{suit: "hearts", rank: "king"},
      %Card{suit: "spades", rank: "king"}
    ]
    refute PlayValidator.valid_king_play?(kings, top_card)
  end
end
```

### 7.2 Integration Tests - Direction Reversal
**File**: `test/kadi/card_games_test.exs`

```elixir
describe "play_cards/3 with King (FR-002)" do
  test "reverses direction clockwise to counter_clockwise" do
    # Setup game with King matching top card
    {:ok, game} = setup_game_with_king()
    
    {:ok, updated_game} = CardGames.play_cards(game, player.id, [king.id])
    
    assert updated_game.direction == "counter_clockwise"
  end
  
  test "2-player game direction has no turn effect (FR-009)" do
    {:ok, game} = setup_two_player_game_with_king()
    
    {:ok, updated_game} = CardGames.play_cards(game, p1.id, [king.id])
    
    # Direction changes but turn goes to other player normally
    assert updated_game.direction == "counter_clockwise"
    assert updated_game.current_turn_player_id == p2.id
  end
end
```

### 7.3 Integration Tests - Cardless Flow
**File**: `test/kadi/card_games_test.exs`

```elixir
describe "cardless player flow (FR-011, FR-012, FR-013)" do
  test "playing King as last card sets status to cardless" do
    {:ok, game} = setup_player_with_only_king()
    
    {:ok, updated_game} = CardGames.play_cards(game, player.id, [king.id])
    
    player_session = get_player_session(updated_game, player.id)
    assert player_session.status == "cardless"
  end
  
  test "cardless player auto-draws and resets status" do
    {:ok, game} = setup_cardless_player()
    
    {:ok, updated_game} = CardGames.draw_card_from_deck(game, player.id)
    
    player_session = get_player_session(updated_game, player.id)
    assert player_session.status == "normal"
  end
end
```

### 7.4 Telemetry Tests
**File**: `test/kadi/telemetry_test.exs`

```elixir
setup do
  test_pid = self()
  
  :telemetry.attach_many(
    "test-king-telemetry",
    [
      [:kadi, :king, :direction_change],
      [:kadi, :king, :cardless_entered]
    ],
    fn event, measurements, metadata, _config ->
      send(test_pid, {:telemetry_event, event, measurements, metadata})
    end,
    nil
  )
  
  on_exit(fn -> :telemetry.detach("test-king-telemetry") end)
  :ok
end

test "emits direction_change event with metadata (FR-020)" do
  {:ok, _game} = play_king_card()
  
  assert_receive {:telemetry_event, [:kadi, :king, :direction_change], _, metadata}
  assert metadata.previous_direction == "clockwise"
  assert metadata.new_direction == "counter_clockwise"
  assert is_boolean(metadata.neutral)
end
```

---

## 8. i18n Keys

**File**: `priv/gettext/en/LC_MESSAGES/default.po`  
**Reference**: spec.md FR-023

```gettext
msgid "Clockwise"
msgstr "Clockwise"

msgid "Counter-clockwise"
msgstr "Counter-clockwise"

msgid "Direction reversed: now %{direction}"
msgstr "Direction reversed: now %{direction}"

msgid "Deck exhausted. Skipping %{player}"
msgstr "Deck exhausted. Skipping %{player}"
```

---

## 9. Anomaly Handling

### 9.1 Deck Exhaustion Guard
**File**: `lib/kadi/card_games.ex`  
**Location**: In `draw_card_from_deck/2` after recycle attempt (around line 240)  
**Reference**: spec.md FR-018, FR-019

```elixir
case recycle_played_stack(game_session) do
  {:ok, recycled_game} ->
    # Retry draw logic...
    
  {:error, :insufficient_cards_to_recycle} ->
    # Anomaly: skip player (FR-018)
    players = get_game_session_players(game_session.id)
    next_player = get_next_player_with_direction(
      players, player_id, game_session.direction
    )
    
    emit_anomaly_skip_event(game_session.id, player_id, "no_cards_after_recycle")
    
    updated_game = GameSession.changeset(game_session, %{
      current_turn_player_id: next_player.id
    }) |> Repo.update!()
    
    broadcast_game_update(updated_game)
    {:ok, updated_game}
end
```

---

## 10. Deployment

### Pre-Deploy Checklist
- [ ] All tests passing (`mix test`)
- [ ] Migrations tested locally
- [ ] i18n keys compiled (`mix gettext.extract --merge`)

### Deploy Sequence
```bash
# 1. Run migrations FIRST
mix ecto.migrate

# 2. Deploy new code
# ... your deployment process

# 3. Monitor telemetry events in logs
```

### Post-Deploy Monitoring
- Check error rate for `:invalid_play`
- Monitor `anomaly_skip` events (should be near-zero)
- Verify direction changes logged correctly
