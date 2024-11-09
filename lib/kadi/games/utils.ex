defmodule Kadi.Utils do
  alias Kadi.Games.Poker.Card
  require Logger

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

  @spec is_valid_suit_or_number?(Card.t(), nonempty_list(Card.t())) :: boolean()
  def is_valid_suit_or_number?(last_played, hand) do
    [last_played | hand]
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(&List.to_tuple/1)
    |> Enum.all?(fn {last_card, current_card} ->
      is_same_suit_or_number?(last_card, current_card)
    end)
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

  def is_valid_hand?(last_card, hand) do
    cond do
      # Validate single card of the same suit or number
      is_same_suit_or_number?(last_card, hd(hand)) and length(hand) == 1 ->
        true

      # Is valid multi-card combo (same numbers)
      is_same_suit_or_number?(last_card, hd(hand)) and is_same_number?(hand) ->
        true

      is_question?(hd(hand)) ->
        is_valid_question_answer?(last_card, hand)

      is_question?(hd(hand)) && is_question_without_answer?(hand) ->
        # All Qs. No answer. Accept hand and assign a card to the player
        # Convert to return tuple -> {:valid, next_action}, {:invalid, reason???}
        false

      true ->
        false
    end
  end

  def is_question?(card) do
    card.number == :eight || card.number == :q
  end

  def contains_question?(hand) do
    hand |> hd |> is_question?
  end

  def is_question_without_answer?(hand) do
    Enum.all?(hand, fn x -> is_question?(x) end)
  end

  def is_valid_question_answer?(last_played, hand) do
    not is_question_without_answer?(hand) &&
      is_valid_suit_or_number?(last_played, hand)
  end

  # Find the intersection of two lists, providing the larger one first
  def intersection(larger, smaller) do
    Enum.filter(larger, fn larger_item -> Enum.member?(smaller, larger_item) end)
  end
end
