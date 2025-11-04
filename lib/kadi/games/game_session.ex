defmodule Kadi.Games.GameSession do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["lobby", "live"]

  schema "game_sessions" do
    field :short_code, :string
    field :status, :string, default: "lobby"
    belongs_to :created_by, Kadi.Accounts.Player
    belongs_to :current_turn_player, Kadi.Accounts.Player
    has_one :deck, Kadi.Games.Deck
    has_many :game_session_players, Kadi.Games.GameSessionPlayer
    many_to_many :players, Kadi.Accounts.Player, join_through: "game_session_players"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_session, attrs) do
    game_session
    |> cast(attrs, [:short_code, :created_by_id, :status, :current_turn_player_id])
    |> validate_required([:short_code, :created_by_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:created_by)
    |> assoc_constraint(:current_turn_player)
    |> unique_constraint(:short_code)
  end
end
