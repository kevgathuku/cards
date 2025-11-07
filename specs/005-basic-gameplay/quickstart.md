# Quickstart Guide: Basic Gameplay Implementation

**Feature**: Basic Gameplay - Regular Cards  
**Date**: 2025-11-06  
**Audience**: Developers implementing this feature

## Overview

This guide provides a step-by-step implementation path for the basic gameplay mechanics. Follow phases sequentially to maintain testability and incremental progress.

**Important Note**: The helper functions `get_game_session_players/1` and `get_next_player/2` shown at the end of Phase 3 are the correct implementations that should be added in Phase 2. They use the actual schema fields (`current_turn_player_id`, `inserted_at`) rather than non-existent fields.

---

## Prerequisites

- [x] Elixir 1.17+ and OTP 28 installed
- [x] PostgreSQL running
- [x] Phoenix application setup complete
- [x] Existing game session creation working
- [x] Player authentication functional

**Verify Setup**:
```bash
cd /Users/kevin/code/elixir/cards
mix deps.get
mix ecto.migrate
mix test  # Ensure existing tests pass
```

---

## Implementation Phases

### Phase 0: Database Schema Review (15 minutes)

**Current State**: The played stack is **already tracked** through the existing `DeckCard` model.

📖 **Reference**: See `docs/database-relationships.md` for:
- Deck card ordering conventions (order_index semantics: lower = top of deck, higher = top of played stack)
- Cascade behavior for deletions
- Existing relationships and validation constraints

#### Step 1: Review Existing Schema

The `DeckCard` table already supports the played stack:

```elixir
# lib/kadi/games/deck_card.ex (EXISTING - NO CHANGES NEEDED)
schema "deck_cards" do
  belongs_to :deck, Deck
  belongs_to :card, Card
  belongs_to :player, Player
  field :location_type, :string  # "deck", "played_stack", or "player_hand"
  field :order_index, :integer   # Position in deck or played_stack (must be > 0)
  
  timestamps(type: :utc_datetime)
end

# Validation rules (ALREADY IMPLEMENTED):
# - location_type='player_hand' → player_id required, order_index must be nil
# - location_type='deck' or 'played_stack' → player_id must be nil, order_index required and > 0
# - Unique constraint on (deck_id, card_id)
# - Unique constraint on (deck_id, location_type, order_index)
```

**How it works**:
- Cards with `location_type='played_stack'` are in the played stack
- `order_index` determines stack position (higher = newer, on top)
- Top card = DeckCard with highest `order_index` where `location_type='played_stack'`

#### Step 2: Add top_card_id to GameSession

GameSession currently has:
- `current_turn_player_id` (added in feature 003)
- `status` ("lobby" or "live")
- NO `top_card_id` yet

**Create Migration**:

```bash
mix ecto.gen.migration add_top_card_to_game_sessions
```

```elixir
# priv/repo/migrations/XXXXXX_add_top_card_to_game_sessions.exs
defmodule Kadi.Repo.Migrations.AddTopCardToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :top_card_id, references(:cards, on_delete: :nilify_all)
    end

    create index(:game_sessions, [:top_card_id])
  end
end
```

**Update Schema**:

```elixir
# lib/kadi/games/game_session.ex
schema "game_sessions" do
  field :short_code, :string
  field :status, :string, default: "lobby"
  belongs_to :created_by, Kadi.Accounts.Player
  belongs_to :current_turn_player, Kadi.Accounts.Player
  belongs_to :top_card, Kadi.Games.Card  # ADD THIS LINE
  has_one :deck, Kadi.Games.Deck
  has_many :game_session_players, Kadi.Games.GameSessionPlayer
  
  timestamps(type: :utc_datetime)
end

# Update changeset to include top_card_id
def changeset(game_session, attrs) do
  game_session
  |> cast(attrs, [:short_code, :created_by_id, :status, :current_turn_player_id, :top_card_id])  # ADD top_card_id
  |> validate_required([:short_code, :created_by_id, :status])
  |> validate_inclusion(:status, @statuses)
  |> assoc_constraint(:created_by)
  |> assoc_constraint(:current_turn_player)
  |> assoc_constraint(:top_card)  # ADD THIS
  |> unique_constraint(:short_code)
end
```

**Run Migration**:
```bash
mix ecto.migrate
mix test  # Existing tests should still pass
```

---

### Phase 1: Play Validation Module (2 hours)

📖 **Reference**: See `data-model.md` section "Validation Rules" for:
- Single card matching logic (FR-002)
- Combo validation rules (FR-003, FR-004)
- Player hand validation (FR-015)

📖 **See Also**: `spec.md` clarifications #3 (combo ordering), #4 (case sensitivity)

#### Step 1: Create PlayValidator Module

```bash
mkdir -p lib/kadi/games
touch lib/kadi/games/play_validator.ex
```

#### Step 2: Implement Validation Logic

```elixir
# lib/kadi/games/play_validator.ex
defmodule Kadi.Games.PlayValidator do
  @moduledoc """
  Validates card plays according to game rules for regular cards (4-10).
  """

  alias Kadi.Games.Card

  @doc """
  Validates if the given cards can be played on the top card.

  ## Rules
  - Single card: Must match suit OR rank
  - Multiple cards: All must have same rank, first card must match suit OR rank
  
  ## Examples
      iex> valid_play?([%Card{rank: "4", suit: "H"}], %Card{rank: "5", suit: "H"})
      {:ok, :valid}
      
      iex> valid_play?([%Card{rank: "4", suit: "C"}], %Card{rank: "5", suit: "H"})
      {:error, :no_match}
  """
  def valid_play?(cards, top_card) when is_list(cards) and length(cards) > 0 do
    cond do
      length(cards) == 1 ->
        validate_single_card(hd(cards), top_card)
        
      length(cards) > 1 ->
        validate_combo(cards, top_card)
        
      true ->
        {:error, :no_cards}
    end
  end

  defp validate_single_card(card, top_card) do
    if matches_suit_or_rank?(card, top_card) do
      {:ok, :valid}
    else
      {:error, :no_match}
    end
  end

  defp validate_combo(cards, top_card) do
    cond do
      not same_rank?(cards) ->
        {:error, :different_ranks}

      not first_card_matches?(cards, top_card) ->
        {:error, :no_match}

      true ->
        {:ok, :valid}
    end
  end

  defp matches_suit_or_rank?(card, top_card) do
    card.suit == top_card.suit or card.rank == top_card.rank
  end

  defp same_rank?(cards) do
    cards
    |> Enum.map(& &1.rank)
    |> Enum.uniq()
    |> length() == 1
  end

  defp first_card_matches?([first_card | _rest], top_card) do
    matches_suit_or_rank?(first_card, top_card)
  end

  defp first_card_matches?([], _top_card), do: false

  @doc """
  Validates that player has all specified cards in their hand.
  """
  def player_has_cards?(hand_card_ids, play_card_ids) when is_list(hand_card_ids) and is_list(play_card_ids) do
    hand_set = MapSet.new(hand_card_ids)
    play_set = MapSet.new(play_card_ids)
    
    MapSet.subset?(play_set, hand_set)
  end
end
```

#### Step 3: Create Tests

```bash
touch test/kadi/games/play_validator_test.exs
```

```elixir
# test/kadi/games/play_validator_test.exs
defmodule Kadi.Games.PlayValidatorTest do
  use ExUnit.Case, async: true
  
  alias Kadi.Games.{PlayValidator, Card}

  describe "valid_play?/2 single card" do
    test "accepts card matching suit" do
      card = %Card{rank: "4", suit: "H"}
      top_card = %Card{rank: "5", suit: "H"}
      
      assert {:ok, :valid} = PlayValidator.valid_play?([card], top_card)
    end

    test "accepts card matching rank" do
      card = %Card{rank: "4", suit: "D"}
      top_card = %Card{rank: "4", suit: "H"}
      
      assert {:ok, :valid} = PlayValidator.valid_play?([card], top_card)
    end

    test "rejects card matching neither" do
      card = %Card{rank: "4", suit: "C"}
      top_card = %Card{rank: "5", suit: "H"}
      
      assert {:error, :no_match} = PlayValidator.valid_play?([card], top_card)
    end
  end

  describe "valid_play?/2 combo" do
    test "accepts combo with same rank and one match" do
      cards = [
        %Card{rank: "4", suit: "H"},
        %Card{rank: "4", suit: "D"}
      ]
      top_card = %Card{rank: "5", suit: "H"}
      
      assert {:ok, :valid} = PlayValidator.valid_play?(cards, top_card)
    end

    test "rejects combo with different ranks" do
      cards = [
        %Card{rank: "4", suit: "H"},
        %Card{rank: "5", suit: "H"}
      ]
      top_card = %Card{rank: "6", suit: "H"}
      
      assert {:error, :different_ranks} = PlayValidator.valid_play?(cards, top_card)
    end

    test "rejects combo where no card matches" do
      cards = [
        %Card{rank: "4", suit: "C"},
        %Card{rank: "4", suit: "S"}
      ]
      top_card = %Card{rank: "5", suit: "H"}
      
      assert {:error, :no_match} = PlayValidator.valid_play?(cards, top_card)
    end
  end

  describe "player_has_cards?/2" do
    test "returns true when player has all cards" do
      hand = ["card-1", "card-2", "card-3"]
      play = ["card-1", "card-2"]
      
      assert PlayValidator.player_has_cards?(hand, play)
    end

    test "returns false when player missing cards" do
      hand = ["card-1", "card-2"]
      play = ["card-1", "card-3"]
      
      refute PlayValidator.player_has_cards?(hand, play)
    end
  end
end
```

**Validation**:
```bash
mix test test/kadi/games/play_validator_test.exs
```

---

### Phase 2: Turn Helper Functions (30 minutes)

⚠️ **NOTE**: No separate TurnManager module needed. Turn logic is simple enough
to implement inline in CardGames context functions.

📖 **Reference**: See `research.md` section 2 for turn management decisions

**Implementation**: Turn logic is implemented as private helper functions in the CardGames context.

#### Step 1: Add Turn Helpers to CardGames Context

```elixir
# lib/kadi/card_games.ex (add to existing module)

# Helper: Get players ordered by join time (determines turn order)
defp get_game_session_players(game_session_id) do
  from(gsp in GameSessionPlayer,
    where: gsp.game_session_id == ^game_session_id,
    order_by: [asc: gsp.inserted_at],  # Join order = turn order
    preload: :player
  )
  |> Repo.all()
end

# Helper: Get next player in turn sequence
defp get_next_player(players, current_player_id) do
  current_index = Enum.find_index(players, &(&1.player_id == current_player_id))
  next_index = rem(current_index + 1, length(players))
  Enum.at(players, next_index).player
end

# Helper: Validate it's player's turn
defp validate_current_turn(game_session, player_id) do
  if game_session.current_turn_player_id == player_id do
    {:ok, :valid}
  else
    {:error, :not_your_turn}
  end
end
```

#### Step 2: Create Tests

```elixir
# test/kadi/card_games_test.exs (add to existing test module)

describe "turn validation" do
  test "play_cards/3 rejects play when not player's turn" do
    game = create_game_with_players([player1, player2])
    # Ensure player2 is current turn
    {:ok, game} = CardGames.update_game_session(game, %{current_turn_player_id: player2.id})
    
    # player1 tries to play
    result = CardGames.play_cards(game.id, player1.id, ["4H"])
    
    assert {:error, :not_your_turn} = result
  end
  
  test "play_cards/3 accepts play when it's player's turn" do
    game = create_game_with_players_and_start([player1, player2])
    # Give player1 a valid card and set their turn
    {:ok, game} = CardGames.update_game_session(game, %{
      current_turn_player_id: player1.id,
      top_card_id: five_hearts.id
    })
    
    result = CardGames.play_cards(game.id, player1.id, [four_hearts.id])
    
    assert {:ok, updated_game} = result
    # Turn should advance to player2
    assert updated_game.current_turn_player_id == player2.id
  end
end
```

**Validation**:
```bash
mix test test/kadi/card_games_test.exs
```

---

### Phase 3: Context Functions (3 hours)

📖 **Reference**: See `contracts/play_actions.md` for:
- Event payloads (play_cards, draw_card)
- Error codes and messages
- State change specifications

📖 **See Also**: 
- `data-model.md` section "State Transitions" for atomic update patterns
- `research.md` section 4 for Ecto.Multi rationale

#### Extend CardGames Context

```elixir
# lib/kadi/card_games.ex (add to existing module)
alias Kadi.Games.PlayValidator

@doc """
Plays the specified cards for the player.

## Examples
    iex> play_cards(game_session, player_id, ["card-id-1", "card-id-2"])
    {:ok, %GameSession{}}
    
    iex> play_cards(game_session, wrong_player_id, ["card-id-1"])
    {:error, :not_your_turn}
"""
def play_cards(game_session_id, player_id, card_ids) when is_list(card_ids) do
  with {:ok, game_session} <- get_game_session_preloaded(game_session_id),
       {:ok, :can_play} <- validate_can_play(game_session, player_id),
       {:ok, cards} <- get_cards(card_ids),
       {:ok, player} <- get_player_in_session(game_session, player_id),
       {:ok, :has_cards} <- validate_player_has_cards(player, card_ids),
       {:ok, top_card} <- get_top_card(game_session),
       {:ok, :valid} <- PlayValidator.valid_play?(cards, top_card) do
    execute_play(game_session, player, cards)
  else
    {:error, reason} -> {:error, reason}
  end
end

@doc """
Draws a card from the deck for the player when they have no valid play.

IMPORTANT: Uses existing CardGames.draw_card_from_deck/2 from feature 003.
This function handles:
- Turn validation
- Drawing from deck
- Automatic deck recycling when empty (via feature 004)
- Turn advancement
- Broadcasting updates
"""
def draw_card(game_session_id, player_id) do
  case get_game_session_preloaded(game_session_id) do
    {:ok, game_session} ->
      # Reuse existing function from feature 003-pick-card-from-deck
      draw_card_from_deck(game_session, player_id)
    {:error, reason} ->
      {:error, reason}
  end
end

# Private helper functions

defp get_game_session_preloaded(id) do
  case Repo.get(GameSession, id) do
    nil -> {:error, :not_found}
    game_session ->
      preloaded = Repo.preload(game_session, [
        :top_card,
        game_session_players: :player,
        deck: [deck_cards: :card]
      ])
      {:ok, preloaded}
  end
end

defp validate_can_play(game_session, player_id) do
  if game_session.current_turn_player_id == player_id do
    {:ok, :can_play}
  else
    {:error, :not_your_turn}
  end
end

defp get_player_in_session(game_session, player_id) do
  case Enum.find(game_session.game_session_players, &(&1.player_id == player_id)) do
    nil -> {:error, :player_not_in_game}
    player -> {:ok, player}
  end
end

defp validate_player_has_cards(player, card_ids) do
  if PlayValidator.player_has_cards?(player.hand, card_ids) do
    {:ok, :has_cards}
  else
    {:error, :cards_not_in_hand}
  end
end

# Note: top_card_id is set when game starts via start_game/1
# and updated on every play via execute_play/3
defp get_top_card(%{top_card_id: nil}), do: {:error, :no_top_card}
defp get_top_card(%{top_card: card}), do: {:ok, card}

defp execute_play(game_session, player, cards) do
  # Get next max order_index for played_stack
  max_order_index = get_max_played_stack_order(game_session)
  players = get_game_session_players(game_session.id)
  next_player = get_next_player(players, player.id)
  
  # Build multi to update DeckCard locations
  multi = 
    cards
    |> Enum.with_index()
    |> Enum.reduce(Multi.new(), fn {card, index}, acc ->
      # Find the DeckCard for this card in player's hand
      deck_card = find_player_deck_card(game_session, player.id, card.id)
      
      # Update to played_stack with sequential order_index
      changeset = DeckCard.changeset(deck_card, %{
        location_type: "played_stack",
        order_index: max_order_index + index + 1,
        player_id: nil
      })
      
      Multi.update(acc, {:move_card, card.id}, changeset)
    end)
    |> Multi.update(:update_game, fn _changes ->
      # Last card in array becomes top card
      top_card = List.last(cards)
      
      GameSession.changeset(game_session, %{
        top_card_id: top_card.id,
        current_turn_player_id: next_player.id
      })
    end)
  
  case Repo.transaction(multi) do
    {:ok, %{update_game: updated_game}} ->
      broadcast_game_update(updated_game)
      {:ok, updated_game}
    {:error, _failed_operation, reason, _changes} ->
      {:error, reason}
  end
end

defp get_max_played_stack_order(game_session) do
  # Query max order_index from DeckCard where location_type='played_stack'
  from(dc in DeckCard,
    where: dc.deck_id == ^game_session.deck.id and dc.location_type == "played_stack",
    select: max(dc.order_index)
  )
  |> Repo.one()
  |> case do
    nil -> 0  # No cards in played stack yet
    max -> max
  end
end

defp find_player_deck_card(game_session, player_id, card_id) do
  Repo.get_by!(DeckCard,
    deck_id: game_session.deck.id,
    card_id: card_id,
    location_type: "player_hand",
    player_id: player_id
  )
end

defp get_game_session_players(game_session_id) do
  # Players ordered by inserted_at (join order) determines turn order
  from(gsp in GameSessionPlayer,
    where: gsp.game_session_id == ^game_session_id,
    order_by: [asc: gsp.inserted_at],
    preload: :player
  )
  |> Repo.all()
end

defp get_next_player(players, current_player_id) do
  current_index = Enum.find_index(players, &(&1.player_id == current_player_id))
  next_index = rem(current_index + 1, length(players))
  Enum.at(players, next_index).player
end

# NO execute_draw implementation needed - using existing draw_card_from_deck/2
# from feature 003-pick-card-from-deck
#
# The existing function handles:
# - Deck empty check
# - Automatic recycle via feature 004 (recycle_played_stack/1)
# - Turn advancement
# - Broadcasting updates
# - Error handling (:not_your_turn, :deck_empty, etc.)

defp broadcast_game_update(game_session) do
  Phoenix.PubSub.broadcast(
    Kadi.PubSub,
    "game:#{game_session.id}",
    {:game_updated, game_session}
  )
end
```

---

### Phase 4: LiveView Integration (4 hours)

📖 **Reference**: See `contracts/play_actions.md` for:
- Complete event handler specifications
- Request/response flow diagrams (lines 290-350)
- Error handling patterns and error codes (lines 85-130)

Implement these handlers:
- `handle_event("select_card", ...)` - See contracts line 15-45
- `handle_event("play_cards", ...)` - See contracts line 47-120
- `handle_event("draw_card", ...)` - See contracts line 122-175
- `handle_info({:game_updated, ...})` - See contracts line 230-265

**Key Files**:
- `lib/kadi_web/live/game_live/show.ex`
- `lib/kadi_web/live/game_live/show.html.heex`
- `lib/kadi_web/components/card_hand.ex`

---

### Phase 5: Testing (2 hours)

#### Integration Tests
#### LiveView Tests
#### End-to-End Flow Tests

---

## Development Workflow

### Daily Checklist
1. Pull latest from main
2. Run `mix test` to verify no regressions
3. Implement one phase at a time
4. Write tests first (TDD)
5. Commit after each passing phase

### Testing Commands
```bash
# Run all tests
mix test

# Run specific test file
mix test test/kadi/games/play_validator_test.exs

# Run with coverage
mix test --cover

# Run LiveView tests
mix test test/kadi_web/live/
```

---

## Troubleshooting

### Issue: Migration Fails
**Solution**: Check for existing columns, rollback if needed
```bash
mix ecto.rollback
# Fix migration
mix ecto.migrate
```

### Issue: Tests Timeout
**Solution**: Check database connections, increase timeout in config/test.exs

### Issue: PubSub Not Working
**Solution**: Verify PubSub configured in application.ex

---

## Estimated Timeline

- **Phase 0**: 15 minutes (database review)
- **Phase 1**: 2 hours (validation module)
- **Phase 2**: 30 minutes (turn helpers - inline)
- **Phase 3**: 3 hours (context functions)
- **Phase 4**: 4 hours (LiveView)
- **Phase 5**: 2 hours (testing)

**Total**: ~12 hours

---

## Next Steps After Implementation

1. Run full test suite
2. Manual testing with 2+ players
3. Performance testing (verify <100ms requirement)
4. Code review
5. Deploy to staging
6. User acceptance testing
7. Merge to main

---

## Resources

- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view)
- [Ecto.Multi Docs](https://hexdocs.pm/ecto/Ecto.Multi.html)
- [Constitution](/.specify/memory/constitution.md)
- [Spec](./spec.md)
- [Data Model](./data-model.md)
- [Contracts](./contracts/play_actions.md)
