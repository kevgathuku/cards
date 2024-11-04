defmodule Kadi.GameSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_sessions" do
    field :short_code, :string
    field :created_by, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_session, attrs) do
    game_session
    |> cast(attrs, [:short_code, :created_by,])
    |> validate_required([:short_code, :created_by])
  end
end
