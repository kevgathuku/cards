defmodule Utils do
  def create_deck() do
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
end
