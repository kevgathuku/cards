defmodule Kadi.Games.Deck do
  use Ecto.Schema
  import Ecto.Changeset

  schema "decks" do
    belongs_to :game_session, Kadi.GameSession

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck, attrs) do
    deck
    |> cast(attrs, [:game_session_id])
    |> validate_required([:game_session_id])
    |> assoc_constraint(:game_session)
    |> unique_constraint(:game_session_id)  # If using the unique index
  end
end
