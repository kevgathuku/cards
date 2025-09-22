defmodule Kadi.Games.Card do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cards" do
    field :suit, :string
    field :rank, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [:suit, :rank])
    |> validate_required([:suit, :rank])
    |> validate_inclusion(:suit, ["hearts", "diamonds", "clubs", "spades"])
    |> validate_inclusion(:rank, Enum.map(2..10, &to_string/1) ++ ["jack", "queen", "king", "ace"])
    |> unique_constraint([:suit, :rank])
  end
end
