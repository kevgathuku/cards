defmodule Kadi.Games.Deck do
  use Ecto.Schema
  import Ecto.Changeset

  schema "decks" do
    belongs_to :game_session, Kadi.GameSession
    has_many :deck_cards, Kadi.Games.DeckCard
    has_many :cards, through: [:deck_cards, :card]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck, attrs) do
    deck
    |> cast(attrs, [:game_session_id])
    |> validate_required([:game_session_id])
    |> assoc_constraint(:game_session)
    |> unique_constraint(:game_session_id)
  end
end
