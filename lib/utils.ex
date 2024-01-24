defmodule Utils do
  alias Games.Kadi.Card

  def create_deck() do
    # TODO: Refactor to use our custom Card struct
    numbers = [
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      ?K,
      ?Q,
      ?J,
      ?A
    ]

    suits = ~w(Hearts Flowers Diamonds Spades)

    # Are there some cards that you don't want? Do it here
    for num <- numbers, suit <- suits, do: {num, suit}
  end

  @spec is_same_suit_or_number?(Card.t(), Card.t()) :: boolean()
  def is_same_suit_or_number?(first, second) do
    first.number == second.number || first.suit == second.suit
  end
end
