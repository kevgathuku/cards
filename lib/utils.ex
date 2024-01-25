defmodule Utils do
  alias Games.Kadi.Card

  def create_deck() do
    numbers = [
      :two,
      :three,
      :four,
      :five,
      :six,
      :seven,
      :eight,
      :nine,
      :ten,
      :k,
      :q,
      :j,
      :a
    ]

    suits = ~w|hearts flowers diamonds spades|a
    for num <- numbers, suit <- suits, do: Card.new(num, suit)
  end

  @spec is_same_suit_or_number?(Card.t(), Card.t()) :: boolean()
  def is_same_suit_or_number?(first, second) do
    first.number == second.number || first.suit == second.suit
  end
end
