defmodule Kadi.GameSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_sessions" do
    field :short_code, :string
    belongs_to :created_by, Kadi.Accounts.Player

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_session, attrs) do
    game_session
    |> cast(attrs, [:short_code, :created_by_id])
    |> validate_required([:short_code, :created_by_id])
    |> assoc_constraint(:created_by)
    |> unique_constraint(:short_code)
  end
end
