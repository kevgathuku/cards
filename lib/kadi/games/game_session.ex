defmodule Kadi.Games.GameSession do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["lobby", "live"]

  schema "game_sessions" do
    field :short_code, :string
    field :status, :string, default: "lobby"
    belongs_to :created_by, Kadi.Accounts.Player
    has_one :deck, Kadi.Games.Deck

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_session, attrs) do
    game_session
    |> cast(attrs, [:short_code, :created_by_id, :status])
    |> validate_required([:short_code, :created_by_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:created_by)
    |> unique_constraint(:short_code)
  end
end
