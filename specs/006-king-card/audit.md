# Implementation Plan Audit: King Card Feature

**Date**: 2025-11-07  
**Branch**: `006-king-card`  
**Audited By**: AI Assistant  
**Purpose**: Identify gaps, missing cross-references, and unclear sequencing in implementation artifacts

---

## Executive Summary

The implementation artifacts (plan.md, research.md, data-model.md, quickstart.md, events.md) provide comprehensive guidance but have **gaps in cross-referencing** and **unclear task sequencing**. The quickstart mentions optimistic locking concepts that were removed from other docs. Core implementation steps need explicit pointers to detail sections.

### Critical Findings

1. **Quickstart outdated**: Still references `lock_version` and optimistic locking despite resolution to use turn gating only
2. **Missing cross-references**: Core implementation steps don't reference where to find specific logic (e.g., "see data-model.md §2.3 for status enum values")
3. **Unclear sequencing**: No explicit dependency graph (e.g., "migrations must run before schema updates")
4. **No concrete code examples**: Quickstart has pseudo-code; needs actual Elixir snippets or file:line references
5. **Missing integration points**: Doesn't specify where in existing `play_cards/3` to insert King detection logic

---

## Artifact-by-Artifact Analysis

### 1. plan.md

**Strengths**:
- Clear summary and technical context
- Constitution gates documented
- Open questions resolved

**Gaps**:
1. "Derived Components" section lists modules but doesn't link to implementation details
2. No reference to data-model.md for schema field specifications
3. Missing pointer to quickstart.md for step-by-step guidance
4. "Extend existing Games context" decision not linked to affected files
5. No mention of which existing functions need modification (e.g., `play_cards/3`, `get_next_player/2`)

**Recommendations**:
```markdown
### Derived Components / Modules (with references)
- `Kadi.Games.GameSession`: add `direction` field → see data-model.md §2.1
- `Kadi.Games.GameSessionPlayer`: add `status` enum → see data-model.md §2.2
- `Kadi.Games.PlayValidator`: extend with King validation → see quickstart.md §3
- Integration points: CardGames.play_cards/3 lines 415-560 → see quickstart.md §3.2
```

---

### 2. research.md

**Strengths**:
- All unknowns resolved
- Clear decisions with rationale
- Best practices table

**Gaps**:
1. Decision "Extend PlayValidator" doesn't reference where PlayValidator lives (file path)
2. "Turn gating" decision doesn't link to existing implementation (`validate_current_turn/2` in card_games.ex:715)
3. Migration plan summary lacks references to actual migration file structure
4. No pointer to existing migration naming convention or directory

**Recommendations**:
```markdown
### 1. Separate King Rules Module vs Extend PlayValidator
- Decision: Extend `lib/kadi/games/play_validator.ex` with King-specific clauses
- Implementation: Add `validate_king_play/3` function after line 42 (see quickstart.md §3.1)
- Existing validation pattern: lines 33-42 in play_validator.ex

### 2. Concurrency Strategy
- Decision: Use existing turn gating in `lib/kadi/card_games.ex:validate_current_turn/2` (line 715)
- No new concurrency primitives needed; reject non-turn plays via existing pattern
```

---

### 3. data-model.md

**Strengths**:
- Complete schema additions documented
- Invariants clearly stated
- Migration summary included

**Gaps**:
1. Migration summary doesn't reference actual migration file naming convention (timestamp prefix)
2. No pointer to existing migration directory (`priv/repo/migrations/`)
3. Status enum values not linked from quickstart's status transition logic
4. "Validation & Error Modes" mentions atoms like `:cardless_wait` but doesn't link to events.md error table
5. Example Telemetry metadata doesn't reference events.md full contract

**Recommendations**:
```markdown
## Migration Summary (with file references)
1. Migration A: Create `priv/repo/migrations/YYYYMMDDHHMMSS_add_direction_to_game_sessions.exs`
   - Template: see existing pattern in `20251107172808_add_top_card_to_game_sessions.exs`
   - Fields: direction (string, default 'clockwise'), CHECK constraint
   
2. Migration B: Create `priv/repo/migrations/YYYYMMDDHHMMSS_add_status_to_game_session_players.exs`
   - Fields: status (string, default 'normal', NOT NULL)
   - CHECK constraint: status IN ('normal','cardless')
   - Status values referenced in events.md §2.4 and quickstart.md §4

## Validation & Error Modes (cross-referenced)
- Error atoms defined in events.md "Error Payloads" table
- `:cardless_wait` → see events.md line 48
- `:invalid_play` → see events.md line 49
```

---

### 4. quickstart.md

**CRITICAL ISSUES**:

**Gaps**:
1. **OUTDATED**: Section §1 still includes `lock_version` migration despite research.md decision to use turn gating only
2. **OUTDATED**: Section §10 mentions "Retry Strategy" which contradicts research.md decision (no optimistic locking)
3. Missing file paths for "Update Schemas" (§2) - which files to edit?
4. "Implement King Logic" (§3) doesn't specify WHERE in existing code to add logic
5. No reference to existing `play_cards/3` structure (lines 415-560 in card_games.ex)
6. "Player Status Handling" (§4) lacks integration point reference
7. Pseudo-code examples not aligned with actual codebase patterns (e.g., `validate_king_play/3` function signature unclear)
8. No pointer to existing telemetry attachment pattern in application.ex
9. i18n keys example (§9) doesn't reference Gettext module path or domain

**Recommendations - Complete Rewrite Needed**:

```markdown
# Quickstart: King Card Reversal Feature

## Prerequisites
- Review spec.md for complete requirements
- Review data-model.md for schema changes
- Review events.md for LiveView & Telemetry contracts

## Implementation Sequence (dependencies explicit)

### Phase 1: Data Layer (no code dependencies)
1. Create migrations (§1)
2. Run migrations (§1)
3. Update schemas (§2)

### Phase 2: Business Logic (depends on Phase 1)
4. Extend validator (§3.1)
5. Add direction-aware turn progression (§3.2)
6. Implement King reversal in play_cards (§3.3)
7. Add cardless status handling (§4)

### Phase 3: Observability (depends on Phase 2)
8. Add telemetry emission (§5)
9. Attach telemetry handlers (§5.1)

### Phase 4: UI (depends on Phase 2, 3)
10. Update LiveView assigns (§6.1)
11. Add direction indicator (§6.2)
12. Add toast coalescing (§6.3)

### Phase 5: Testing (depends on Phase 2, 3, 4)
13. Unit tests (§7.1)
14. Integration tests (§7.2)
15. LiveView tests (§7.3)
16. Telemetry tests (§7.4)

---

## §1. Apply Migrations

### §1.1 Create Direction Migration
**File**: `priv/repo/migrations/YYYYMMDDHHMMSS_add_direction_to_game_sessions.exs`
**Template**: See `priv/repo/migrations/20251107172808_add_top_card_to_game_sessions.exs` for structure
**Reference**: data-model.md §2.1 for field spec

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

### §1.2 Create Status Migration
**File**: `priv/repo/migrations/YYYYMMDDHHMMSS_add_status_to_game_session_players.exs`
**Reference**: data-model.md §2.2 for enum values

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

### §1.3 Run Migrations
```bash
mix ecto.migrate
```

---

## §2. Update Schemas

### §2.1 GameSession Schema
**File**: `lib/kadi/games/game_session.ex`
**Current**: Lines 1-30
**Reference**: data-model.md §2.1 for validation rules

**Add module attribute** (after line 5):
```elixir
@directions ["clockwise", "counter_clockwise"]
```

**Add field** to schema block (after line 8):
```elixir
field :direction, :string, default: "clockwise"
```

**Update changeset** (line 23, add to cast/validate):
```elixir
|> cast(attrs, [:short_code, :created_by_id, :status, :direction, :current_turn_player_id, :top_card_id])
|> validate_required([:short_code, :created_by_id, :status, :direction])
|> validate_inclusion(:direction, @directions)
```

### §2.2 GameSessionPlayer Schema
**File**: `lib/kadi/games/game_session_player.ex`
**Current**: Lines 1-20
**Reference**: data-model.md §2.2, events.md §2.4

**Add module attribute** (after line 4):
```elixir
@player_statuses ["normal", "cardless"]
```

**Add field** to schema block (after line 8):
```elixir
field :status, :string, default: "normal"
```

**Update changeset** (line 14, add to cast/validate):
```elixir
|> cast(attrs, [:game_session_id, :player_id, :status])
|> validate_inclusion(:status, @player_statuses)
```

---

## §3. Implement King Logic

### §3.1 Extend PlayValidator
**File**: `lib/kadi/games/play_validator.ex`
**Current**: Lines 1-107 (regular cards only)
**Reference**: spec.md FR-001, FR-004, FR-005

**Add to module attributes** (after line 18):
```elixir
@special_ranks ["king"]  # Extend later for other special cards
```

**Add new function** (after line 44, before `player_has_cards?/2`):
```elixir
@doc """
Validates if a King card play is valid.

## Rules
- Single King: Must match suit OR rank of top card
- Multiple Kings: Rejected (only one King per turn)
- King in combo with other cards: Rejected (Phase 1 limitation)

## Returns
- `true` if valid King play
- `false` otherwise
"""
def valid_king_play?([], _top_card), do: false
def valid_king_play?(_cards, nil), do: false

def valid_king_play?([%{rank: "king"} = king_card], top_card) do
  matches_suit_or_rank?(king_card, top_card)
end

def valid_king_play?([%{rank: "king"} | _rest], _top_card) do
  # Multiple Kings or King in combo - reject
  false
end

def valid_king_play?(_cards, _top_card), do: false

# Add helper (if not already defined)
defp matches_suit_or_rank?(card, top_card) do
  card.suit == top_card.suit or card.rank == top_card.rank
end
```

**Update main `valid_play?/2`** (replace lines 33-44):
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
      false  # Special cards other than King not yet implemented
  end
end
```

---

### §3.2 Add Direction-Aware Turn Progression
**File**: `lib/kadi/card_games.ex`
**Current**: `get_next_player/2` at line 697
**Reference**: spec.md FR-002, FR-008, FR-009

**Add new helper function** (after line 697):
```elixir
@doc """
Returns the next player based on current game direction.

In clockwise: player1 → player2 → player3 → player1
In counter_clockwise: player1 → player3 → player2 → player1

For 2-player games, direction has no effect (always alternates).
"""
defp get_next_player_with_direction(players, current_player_id, direction) do
  player_count = length(players)
  
  if player_count == 2 do
    # 2-player: direction irrelevant, just alternate
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
```

---

### §3.3 Implement King Reversal in play_cards
**File**: `lib/kadi/card_games.ex`
**Current**: `play_cards/3` at lines 415-465, `execute_play/3` at lines 571-615
**Reference**: spec.md FR-002, FR-003, FR-015, FR-020

**Update execute_play function** (replace lines 571-615):
```elixir
defp execute_play(game_session, player, cards_to_play) do
  # Get current max order_index in played_stack
  max_order = get_max_played_stack_order(game_session)

  # Detect King play
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
  
  # FR-009: 2-player games ignore direction change
  next_player = get_next_player_with_direction(players, player.id, new_direction)

  # Check if player will be cardless after this play
  player_hand = get_player_hand_count(game_session, player.id)
  cards_played_count = length(cards_to_play)
  will_be_cardless = (player_hand == cards_played_count)

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

  # Update game_session with new direction and turn
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
  multi_with_status = if will_be_cardless and king_played? do
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
          player_count == 2  # neutral flag
        )
      end
      
      if will_be_cardless and king_played? do
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

# Helper functions
defp reverse_direction("clockwise"), do: "counter_clockwise"
defp reverse_direction("counter_clockwise"), do: "clockwise"

defp get_player_hand_count(game_session, player_id) do
  game_session.deck.deck_cards
  |> Enum.count(&(&1.location_type == "player_hand" and &1.player_id == player_id))
end
```

---

## §4. Player Status Handling (Cardless Auto-Draw)

### §4.1 Update draw_card_from_deck
**File**: `lib/kadi/card_games.ex`
**Current**: Lines 215-285
**Reference**: spec.md FR-012, FR-013, FR-014

**Add cardless check and auto-reset** (insert after line 227, after turn validation):
```elixir
# Check if player is cardless and handle auto-draw
player_session = Repo.get_by!(GameSessionPlayer,
  game_session_id: game_session.id,
  player_id: player_id
)

is_cardless = player_session.status == "cardless"
```

**Update transaction builder** (modify Ecto.Multi, around line 262):
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

**Add telemetry emission** (after transaction success, before broadcast):
```elixir
if is_cardless do
  :telemetry.execute(
    [:kadi, :king, :cardless_draw],
    %{},
    %{game_id: game_session.id, player_id: player_id}
  )
end
```

---

## §5. Telemetry Events

### §5.1 Add Telemetry Helper Functions
**File**: `lib/kadi/card_games.ex`
**Location**: Add at end of module (after line 730)
**Reference**: events.md, spec.md FR-020

```elixir
# Telemetry Helpers

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

### §5.2 Attach Telemetry Handlers
**File**: `lib/kadi/application.ex`
**Location**: In `start/2` after children definition (around line 30)
**Reference**: events.md §3

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

# ... rest of start/2

# Add handler function (private)
defp handle_king_telemetry(event, _measurements, metadata, _config) do
  require Logger
  
  event_name = Enum.join(event, ".")
  Logger.info("#{event_name}: #{inspect(metadata)}")
end
```

---

## §6. LiveView UI Updates

### §6.1 Update GameLive Assigns
**File**: `lib/kadi_web/live/game_live.ex`
**Reference**: events.md §2

**Add to mount or game_updated handler** (update assigns):
```elixir
assign(socket,
  direction: game_session.direction,
  player_statuses: build_player_statuses_map(game_session),
  toast: nil,  # will be set by direction change handler
  banner: nil  # for anomaly skip
)

defp build_player_statuses_map(game_session) do
  game_session.game_session_players
  |> Enum.into(%{}, fn gsp -> {gsp.player_id, gsp.status} end)
end
```

### §6.2 Add Direction Indicator Template
**File**: `lib/kadi_web/live/game_live.html.heex`
**Reference**: spec.md FR-022, SC-010

```heex
<div class="direction-indicator" role="status" aria-live="polite">
  <.icon name={direction_icon(@direction)} class="w-5 h-5" />
  <span class="font-medium text-gray-900">
    <%= direction_label(@direction) %>
  </span>
</div>

<%# Helper functions in game_live.ex %>
defp direction_icon("clockwise"), do: "arrow-rotate-right"
defp direction_icon("counter_clockwise"), do: "arrow-rotate-left"

defp direction_label("clockwise"), do: gettext("Clockwise")
defp direction_label("counter_clockwise"), do: gettext("Counter-clockwise")
```

### §6.3 Add Toast Coalescing
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
    
    # Set new toast with timer
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

## §7. Tests

### §7.1 Unit Tests - PlayValidator
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
  
  test "rejects multiple Kings" do
    top_card = %Card{suit: "hearts", rank: "king"}
    kings = [
      %Card{suit: "hearts", rank: "king"},
      %Card{suit: "spades", rank: "king"}
    ]
    refute PlayValidator.valid_king_play?(kings, top_card)
  end
end
```

### §7.2 Integration Tests - Direction Reversal
**File**: `test/kadi/card_games_test.exs`

```elixir
describe "play_cards/3 with King" do
  test "reverses direction from clockwise to counter_clockwise", %{game: game, players: [p1, p2, p3]} do
    # Setup: game in clockwise, p1's turn, has King of Hearts
    game = setup_game_with_king(game, p1, "hearts")
    
    {:ok, updated_game} = CardGames.play_cards(game, p1.id, [king.id])
    
    assert updated_game.direction == "counter_clockwise"
    assert updated_game.current_turn_player_id == p3.id  # counter_clockwise
  end
  
  test "reverses direction from counter_clockwise to clockwise" do
    # Similar test in opposite direction
  end
  
  test "2-player game direction change has no effect on turn order" do
    # Setup 2-player game
    # Play King
    # Assert turn goes to other player regardless of direction
  end
end
```

### §7.3 Integration Tests - Cardless Flow
**File**: `test/kadi/card_games_test.exs`

```elixir
describe "cardless player flow" do
  test "playing King as last card sets player to cardless", %{game: game, player: p1} do
    # Setup: p1 has only King card left
    game = setup_player_with_only_king(game, p1)
    
    {:ok, updated_game} = CardGames.play_cards(game, p1.id, [king.id])
    
    player_session = Repo.get_by!(GameSessionPlayer, 
      game_session_id: updated_game.id,
      player_id: p1.id
    )
    
    assert player_session.status == "cardless"
  end
  
  test "cardless player auto-draws on their turn and status resets" do
    # Setup: p1 is cardless, their turn comes around
    game = setup_cardless_player(game, p1)
    
    {:ok, updated_game} = CardGames.draw_card_from_deck(game, p1.id)
    
    player_session = Repo.get_by!(GameSessionPlayer,
      game_session_id: updated_game.id,
      player_id: p1.id
    )
    
    assert player_session.status == "normal"
    # Assert player has 1 card now
    # Assert turn advanced to next player
  end
end
```

### §7.4 Telemetry Tests
**File**: `test/kadi/telemetry_test.exs`

```elixir
defmodule Kadi.TelemetryTest do
  use Kadi.DataCase
  
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
    
    on_exit(fn ->
      :telemetry.detach("test-king-telemetry")
    end)
    
    :ok
  end
  
  test "emits direction_change event with metadata", %{game: game, player: p1} do
    # Setup and play King
    {:ok, _updated_game} = CardGames.play_cards(game, p1.id, [king.id])
    
    assert_receive {:telemetry_event, [:kadi, :king, :direction_change], _, metadata}
    assert metadata.game_id == game.id
    assert metadata.player_id == p1.id
    assert metadata.previous_direction == "clockwise"
    assert metadata.new_direction == "counter_clockwise"
    assert metadata.card_id == king.id
    assert is_boolean(metadata.neutral)
  end
end
```

### §7.5 LiveView Tests
**File**: `test/kadi_web/live/game_live_test.exs`

```elixir
describe "direction indicator" do
  test "updates when King is played", %{conn: conn, game: game} do
    {:ok, view, _html} = live(conn, ~p"/games/#{game.short_code}")
    
    # Initial direction
    assert has_element?(view, "[role='status']", "Clockwise")
    
    # Play King (via test helper)
    play_king_card(view, player, king)
    
    # Direction updated
    assert has_element?(view, "[role='status']", "Counter-clockwise")
  end
  
  test "toast appears and auto-dismisses", %{conn: conn, game: game} do
    {:ok, view, _html} = live(conn, ~p"/games/#{game.short_code}")
    
    play_king_card(view, player, king)
    
    # Toast visible
    assert has_element?(view, ".toast", "Direction reversed")
    
    # Wait for auto-dismiss
    :timer.sleep(2100)
    render(view)
    
    refute has_element?(view, ".toast")
  end
  
  test "rapid King plays coalesce toast", %{conn: conn, game: game} do
    {:ok, view, _html} = live(conn, ~p"/games/#{game.short_code}")
    
    play_king_card(view, p1, king1)
    :timer.sleep(500)
    play_king_card(view, p2, king2)
    
    # Only one toast element visible
    assert [_single_toast] = view |> element(".toast") |> has_element?()
  end
end
```

---

## §8. i18n Keys

### §8.1 Add Gettext Keys
**File**: `priv/gettext/en/LC_MESSAGES/default.po`

```
msgid "Clockwise"
msgstr "Clockwise"

msgid "Counter-clockwise"
msgstr "Counter-clockwise"

msgid "Direction reversed: now %{direction}"
msgstr "Direction reversed: now %{direction}"

msgid "Deck exhausted. Skipping %{player}"
msgstr "Deck exhausted. Skipping %{player}"

msgid "It's not your turn."
msgstr "It's not your turn."

msgid "You can't play that card."
msgstr "You can't play that card."

msgid "You must draw before playing."
msgstr "You must draw before playing."
```

---

## §9. Anomaly Handling (Deck Exhaustion)

### §9.1 Update recycle_played_stack
**File**: `lib/kadi/card_games.ex`
**Location**: After `recycle_played_stack/1` (around line 350)

**Add guard in draw_card_from_deck** (after recycle attempt fails):
```elixir
case recycle_played_stack(game_session) do
  {:ok, recycled_game_session} ->
    # ... existing retry logic
  
  {:error, :insufficient_cards_to_recycle} ->
    # Anomaly: cannot draw, skip player (FR-018)
    players = get_game_session_players(game_session.id)
    next_player = get_next_player_with_direction(
      players,
      player_id,
      game_session.direction
    )
    
    # Emit anomaly event (FR-020)
    emit_anomaly_skip_event(game_session.id, player_id, "no_cards_after_recycle")
    
    # Update turn without draw
    updated_game = GameSession.changeset(game_session, %{
      current_turn_player_id: next_player.id
    })
    |> Repo.update!()
    
    broadcast_game_update(updated_game)
    broadcast_anomaly_banner(updated_game, player_id)
    
    {:ok, updated_game}
end
```

**Add broadcast helper**:
```elixir
defp broadcast_anomaly_banner(game_session, skipped_player_id) do
  KadiWeb.Endpoint.broadcast(
    "game:" <> to_string(game_session.id),
    "anomaly_skip",
    %{
      player_id: skipped_player_id,
      message: "Deck exhausted. Skipping player."
    }
  )
end
```

---

## §10. Deployment Checklist

1. **Pre-Deploy**:
   - [ ] All tests passing (`mix test`)
   - [ ] Migrations reviewed and tested locally
   - [ ] i18n keys compiled (`mix gettext.extract --merge`)
   - [ ] No hardcoded strings in templates (grep check)

2. **Deploy Sequence**:
   ```bash
   # 1. Run migrations FIRST
   mix ecto.migrate
   
   # 2. Deploy new code
   # ... deployment process
   
   # 3. Verify telemetry events in logs
   # Check for [:kadi, :king, ...] events
   ```

3. **Post-Deploy Monitoring**:
   - [ ] Check error rate for `:invalid_play` (should be low)
   - [ ] Monitor `anomaly_skip` events (should be near-zero)
   - [ ] Verify direction changes logged correctly
   - [ ] Test 2-player and multi-player games

---

## Cross-Reference Index

| Implementation Step | References |
|-------------------|-----------|
| Migration A (direction) | data-model.md §2.1, spec.md FR-006, FR-007 |
| Migration B (status) | data-model.md §2.2, spec.md FR-026 |
| Schema: GameSession | data-model.md §2.1, existing: lib/kadi/games/game_session.ex |
| Schema: GameSessionPlayer | data-model.md §2.2, existing: lib/kadi/games/game_session_player.ex |
| Validator: King logic | spec.md FR-001, FR-004, FR-005, existing: lib/kadi/games/play_validator.ex:33-107 |
| Context: play_cards | spec.md FR-002, FR-008, FR-011, existing: lib/kadi/card_games.ex:415-465 |
| Context: execute_play | spec.md FR-015, FR-020, existing: lib/kadi/card_games.ex:571-615 |
| Context: draw_card | spec.md FR-012, FR-013, existing: lib/kadi/card_games.ex:215-285 |
| Turn progression | spec.md FR-008, FR-009, existing: lib/kadi/card_games.ex:697-706 |
| Telemetry events | spec.md FR-020, events.md §3, research.md §5 |
| LiveView assigns | events.md §2, spec.md FR-021, existing: lib/kadi_web/live/game_live.ex |
| Toast coalescing | spec.md FR-025, SC-013, events.md rate limiting |
| Accessibility | spec.md FR-022, SC-010 |
| i18n | spec.md FR-023, events.md localization keys table |
| Anomaly handling | spec.md FR-018, FR-019, existing: lib/kadi/card_games.ex:recycle_played_stack |

```
