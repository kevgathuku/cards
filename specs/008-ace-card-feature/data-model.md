# Data Model for Ace Card Feature

**Date**: 2025-11-10
**Feature**: Ace Card Special Action

This document describes the data model changes required to implement the Ace card feature. The design is based on the findings in `research.md`.

## 1. `game_sessions` Table Modification

To support the Ace card's functionality and other potential special actions, the `game_sessions` table will be modified to include two new fields to manage intermediate states.

### New Columns

- **Column Name**: `action_type`
  - **Data Type**: `string`
  - **Nullable**: `true`
  - **Default Value**: `NULL`
  - **Description**: Stores the type of action the game is waiting for, e.g., `"select_suit"`.

- **Column Name**: `action_suit`
  - **Data Type**: `string`
  - **Nullable**: `true`
  - **Default Value**: `NULL`
  - **Description**: Stores the suit that the next player must follow, as requested by a special card action. For combo plays, only the lead (first) card must match this suit.

## 2. `Kadi.Games.GameSession` Ecto Schema

The `Kadi.Games.GameSession` schema will be updated to reflect the new database columns.

### Schema Definition

**IMPLEMENTED**: The schema has been updated as shown below.

```elixir
# lib/kadi/games/game_session.ex

defmodule Kadi.Games.GameSession do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["lobby", "live"]
  @directions ["clockwise", "counter_clockwise"]
  @action_types ["select_suit"]
  @suits ["hearts", "diamonds", "clubs", "spades"]

  schema "game_sessions" do
    field :short_code, :string
    field :status, :string, default: "lobby"
    field :direction, :string, default: "clockwise"
    field :action_type, :string
    field :action_suit, :string

    belongs_to :created_by, Kadi.Accounts.Player
    belongs_to :current_turn_player, Kadi.Accounts.Player
    belongs_to :top_card, Kadi.Games.Card
    has_one :deck, Kadi.Games.Deck
    has_many :game_session_players, Kadi.Games.GameSessionPlayer
    many_to_many :players, Kadi.Accounts.Player, join_through: "game_session_players"

    timestamps(type: :utc_datetime)
  end

  # ...
end
```

### Changeset Modification

**IMPLEMENTED**: The changeset function has been updated to include the new fields and their validation rules.

```elixir
# lib/kadi/games/game_session.ex

def changeset(game_session, attrs) do
  game_session
  |> cast(attrs, [
    :short_code,
    :created_by_id,
    :status,
    :direction,
    :current_turn_player_id,
    :top_card_id,
    :action_type,
    :action_suit
  ])
  |> validate_required([:short_code, :created_by_id, :status, :direction])
  |> validate_inclusion(:status, @statuses)
  |> validate_inclusion(:direction, @directions)
  |> validate_inclusion(:action_type, @action_types, allow_nil: true)
  |> validate_inclusion(:action_suit, @suits, allow_nil: true)
  |> assoc_constraint(:created_by)
  |> assoc_constraint(:current_turn_player)
  |> assoc_constraint(:top_card)
  |> unique_constraint(:short_code)
end
```

## 3. Database Migration

**IMPLEMENTED**: The migration has been created and applied.

### Migration File

`priv/repo/migrations/20251110192017_add_action_fields_to_game_sessions.exs`

```elixir
defmodule Kadi.Repo.Migrations.AddActionFieldsToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :action_type, :string
      add :action_suit, :string
    end
  end
end
```

**Note**: Both fields are nullable by default in PostgreSQL when not explicitly specified.

## 4. Context Functions (Kadi.CardGames)

**IMPLEMENTED**: The following functions have been added or modified to support Ace card functionality.

### 4.1 `play_cards/3` - Modified

The existing `play_cards/3` function has been updated to detect when an Ace is played and set the game state accordingly:

- When an Ace is played, `action_type` is set to `"select_suit"`
- The current turn player remains unchanged (turn is paused)
- `action_suit` is set to `nil` (waiting for player to select)

### 4.2 `select_suit/3` - New Function

```elixir
def select_suit(game_session, player_id, suit)
```

**Purpose**: Allows the current player to select a suit after playing an Ace.

**Validations**:
- Verifies the player is the current turn player
- Checks that `action_type` is `"select_suit"`
- Validates the suit is one of: `"hearts"`, `"diamonds"`, `"clubs"`, `"spades"`

**Effects**:
- Sets `action_suit` to the selected suit
- Clears `action_type` (back to `nil`)
- Advances the turn to the next player
- Broadcasts game update via PubSub
- Emits telemetry event `[:kadi, :game, :ace_suit_selected]`

### 4.3 Validation Changes

The `play_cards/3` validation logic now passes `action_suit` to `PlayValidator.valid_play?/3`:

```elixir
validate_can_play(cards_to_play, top_card, game_session.action_suit)
```

## 5. Play Validation (Kadi.Games.PlayValidator)

**IMPLEMENTED**: The `PlayValidator` module has been updated to support the Ace card's suit requirement.

### 5.1 `valid_play?/3` - Modified Signature

**Previous**: `valid_play?(cards, top_card)`  
**New**: `valid_play?(cards, top_card, opts)`

**New Parameter**: `opts` - Keyword list with optional `:action_suit` key

**Behavior**:
- When `action_suit` is `nil`: Normal validation (match suit or rank of top card)
- When `action_suit` is set: Lead card must match the `action_suit`
- Ace cards ignore `action_suit` requirement (can be played anytime)

### 5.2 Ace-Specific Validation Functions

**IMPLEMENTED**: New functions added:

```elixir
def valid_ace_play?(cards, top_card, action_suit)
```

- Validates that all cards are Aces
- Ignores `action_suit` requirement (Aces can be played anytime)
- Returns `true` if all cards are Aces

**Note**: For combo plays (e.g., "9 of Spades" + "9 of Hearts"), only the lead (first) card must match the `action_suit`.

## 6. LiveView Integration

**IMPLEMENTED**: The LiveView UI has been updated to support Ace card suit selection.

### 6.1 Template Changes (`game_live.html.heex`)

Added suit selection UI that appears when `action_type == "select_suit"`:

```heex
<%= if @game_session.action_type == "select_suit" and 
       @current_turn_player.id == @current_player.id do %>
  <div class="suit-selection">
    <p>Select a suit:</p>
    <button phx-click="select_suit" phx-value-suit="hearts">♥ Hearts</button>
    <button phx-click="select_suit" phx-value-suit="diamonds">♦ Diamonds</button>
    <button phx-click="select_suit" phx-value-suit="clubs">♣ Clubs</button>
    <button phx-click="select_suit" phx-value-suit="spades">♠ Spades</button>
  </div>
<% end %>
```

### 6.2 Event Handler (`game_live.ex`)

Added new event handler:

```elixir
def handle_event("select_suit", %{"suit" => suit}, socket) do
  case CardGames.select_suit(game_session, current_player.id, suit) do
    {:ok, _updated_game} -> {:noreply, socket}
    {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
  end
end
```

**Note**: The handler uses the broadcast-only pattern - it doesn't update socket state directly. Instead, it waits for the PubSub broadcast from `select_suit/3`, which triggers `handle_info({:game_updated, game_session}, socket)`.

## 7. Testing

**IMPLEMENTED**: Comprehensive test suite in `test/kadi/card_games/special_cards_ace_test.exs`

**Test Coverage**:
- `[T033]`: Playing an Ace pauses the turn and sets `action_type` to `"select_suit"`
- `[T034]`: `select_suit/3` advances turn and sets `action_suit`
- `[T035]`: Next player must play a card matching the requested suit
- `[T036]`: Ace can be played even when a suit has been requested
- `[T037]`: Multiple Aces in a single play trigger suit selection once
- `[T038]`: Combo plays respect `action_suit` for lead card only

**Test Organization**: Tests were moved from the monolithic `test/kadi/card_games_test.exs` to a dedicated file `test/kadi/card_games/special_cards_ace_test.exs` to follow DRY principles and improve test organization.

**PlayValidator Tests**: Updated in `test/kadi/games/play_validator_test.exs` to use the new `valid_play?/3` signature with the `opts` parameter.
