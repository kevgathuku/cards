defmodule Kadi.Games.DeckCard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "deck_cards" do
    belongs_to :deck, Kadi.Games.Deck
    belongs_to :card, Kadi.Games.Card
    belongs_to :player, Kadi.Accounts.Player

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck_card, attrs) do
    deck_card
    |> cast(attrs, [:deck_id, :card_id, :player_id])
    |> validate_required([:deck_id, :card_id])
    |> assoc_constraint(:deck)
    |> assoc_constraint(:card)
    |> assoc_constraint(:player)
    |> unique_constraint([:deck_id, :card_id])
  end
end
