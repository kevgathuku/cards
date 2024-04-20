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

  @spec is_same_number?(nonempty_list(Card.t())) :: boolean()
  def is_same_number?(cards) when length(cards) == 1, do: true

  def is_same_number?(cards) do
    first_card = hd(cards)
    Enum.all?(tl(cards), fn card -> card.number == first_card.number end)
  end

  @doc """
  Determine if the provided combination of cards is valid in this game

  ## Examples

      iex> is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [Games.Kadi.Card.new(:nine, :diamonds)])
      true

      iex> is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [Games.Kadi.Card.new(:nine, :hearts)])
      false

      iex> is_valid_hand?(
      ...> Games.Kadi.Card.new(:ten, :diamonds),
      ...> [Games.Kadi.Card.new(:five, :diamonds), Games.Kadi.Card.new(:five, :spades)])
      true

  """
  def is_valid_hand?(_, cards) when hd(cards).number == :a, do: true
  def is_valid_hand?(_, cards) when hd(cards).number == :eight and length(cards) == 1, do: false
  def is_valid_hand?(_, cards) when hd(cards).number == :q and length(cards) == 1, do: false

  def is_valid_hand?(last_card, cards) do
    cond do
      # Validate single card of the same suit or number
      is_same_suit_or_number?(last_card, hd(cards)) and length(cards) == 1 ->
        true

      # Is valid multi-card combo (same numbers)
      is_same_suit_or_number?(last_card, hd(cards)) and Utils.is_same_number?(cards) ->
        true

      true ->
        # TODO: Is valid Q and A combo
        # Do some pattern matching to check if it starts with '8' or 'Q'
        false
    end
  end

  def intersection(larger, smaller) do
    Enum.filter(larger, fn x -> Enum.member?(smaller, x) end)
  end
end
