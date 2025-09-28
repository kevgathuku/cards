defmodule Kadi.Games.DeckCard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "deck_cards" do
    belongs_to :deck, Kadi.Games.Deck
    belongs_to :card, Kadi.Games.Card
    belongs_to :player, Kadi.Accounts.Player
    field :location_type, :string  # "deck", "played_stack", "player_hand"
    field :order_index, :integer  # Order for deck/played_stack, null for player_hand

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck_card, attrs) do
    deck_card
    |> cast(attrs, [:deck_id, :card_id, :location_type, :player_id, :order_index])
    |> validate_required([:deck_id, :card_id, :location_type])
    |> validate_location_and_order()
    |> assoc_constraint(:deck)
    |> assoc_constraint(:card)
    |> assoc_constraint(:player)
    |> unique_constraint([:deck_id, :card_id])
    |> unique_constraint([:deck_id, :location_type, :order_index])
  end

  defp validate_location_and_order(changeset) do
    location_type = get_field(changeset, :location_type)
    player_id = get_field(changeset, :player_id)
    order_index = get_field(changeset, :order_index)

    case location_type do
      "player_hand" ->
        changeset
        |> validate_required(:player_id)
        |> validate_is_nil(:order_index, "must be nil for player_hand")

      loc when loc == "deck" or loc == "played_stack" ->
        changeset
        |> validate_is_nil(:player_id, "must be nil for #{location_type}")
        |> validate_required(:order_index)
        |> validate_number(:order_index, greater_than: 0)

      _ ->
        add_error(changeset, :location_type, "must be 'deck', 'played_stack', or 'player_hand'")
    end
  end

  defp validate_is_nil(changeset, field, message) do
    if get_field(changeset, field) == nil do
      changeset
    else
      add_error(changeset, field, message)
    end
  end
end
