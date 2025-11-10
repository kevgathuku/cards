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

```elixir
# lib/kadi/games/game_session.ex

defmodule Kadi.Games.GameSession do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["lobby", "live"]
  @directions ["clockwise", "counter_clockwise"]
  @action_types ["select_suit", nil]
  @suits ["hearts", "diamonds", "clubs", "spades", nil]

  schema "game_sessions" do
    field :short_code, :string
    field :status, :string, default: "lobby"
    field :direction, :string, default: "clockwise"
    field :action_type, :string # New field
    field :action_suit, :string # New field

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

The changeset function will be updated to include the new fields and their validation rules.

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
    :action_type, # Add new field
    :action_suit  # Add new field
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

A new Ecto migration will be created to add the `action_type` and `action_suit` columns to the `game_sessions` table.

### Migration File

`priv/repo/migrations/YYYYMMDDHHMMSS_add_action_fields_to_game_sessions.exs`

```elixir
defmodule Kadi.Repo.Migrations.AddActionFieldsToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :action_type, :string, null: true
      add :action_suit, :string, null: true
    end
  end
end
```
