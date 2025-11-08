defmodule Kadi.Games.GameSessionPlayer do
  use Ecto.Schema
  import Ecto.Changeset

  @player_statuses ["normal", "cardless"]

  schema "game_session_players" do
    belongs_to :game_session, Kadi.Games.GameSession
    belongs_to :player, Kadi.Accounts.Player
    field :status, :string, default: "normal"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_session_player, attrs) do
    game_session_player
    |> cast(attrs, [:game_session_id, :player_id, :status])
    |> validate_required([:game_session_id, :player_id])
    |> validate_inclusion(:status, @player_statuses)
    |> assoc_constraint(:game_session)
    |> assoc_constraint(:player)
    |> unique_constraint([:game_session_id, :player_id])
  end
end
