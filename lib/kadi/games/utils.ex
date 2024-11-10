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

  @doc """
  Parse a list of cards specified in the shorthand format into the Card struct

  ## Examples

     iex> alias Games.Kadi.Card

     iex> parse_cards(["9♦", "8♥"])
     [ %Card{number: :nine, suit: :diamonds}, %Card{number: :eight, suit: :hearts} ]
  """
  def parse_cards(cards) do
    for card <- cards, do: Card.parse(card)
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

      iex> alias Games.Kadi.Card

      iex> is_valid_hand?(Card.parse("10♦"), [Card.parse("9♦")])
      true

      iex> is_valid_hand?(Card.parse("10♦"), [Card.parse("9♥")])
      false

      iex> is_valid_hand?(
      ...> Card.parse("10♦"), ["5♦", "2♦"] |> parse_cards )
      false

      iex> is_valid_hand?(Card.parse("10♦"), ["5♦", "5♠"] |> parse_cards)
      true

  """
  def is_valid_hand?(_, cards) when hd(cards).number == :a, do: true
  def is_valid_hand?(_, cards) when hd(cards).number == :eight and length(cards) == 1, do: false
  def is_valid_hand?(_, cards) when hd(cards).number == :q and length(cards) == 1, do: false

  def is_valid_hand?(last_card, hand) do
    cond do
      contains_question?(hand) ->
        cond do
          is_valid_question_answer?(last_card, hand) ->
            true

          is_question_without_answer?(hand) ->
            # TODO: Accept hand and assign a card to the player
            # Convert to return tuple -> {:valid, next_action}, {:invalid, reason???}
            false

          extract_answer(hand) |> is_valid_combination?() == false ->
            # Invalid answer combination
            false

          not is_valid_suit_or_number?(last_card, hand) ->
            # Some invalid successive cards combination
            false

          true ->
            Logger.warning("Parsing Q/A: Should not get here. Hand: #{inspect(hand)}")
            false
        end

      is_valid_suit_or_number?(last_card, hand) and is_valid_combination?(hand) ->
        true

      # Fallback condition
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

  @doc """
    Determine if the combination of cards is an allowed sequence
    Not meant to check Q/A combinations

    ## Examples
      iex> alias Games.Kadi.Card

      iex> is_valid_combination?([Card.parse("10♦"), Card.parse("10♠")])
      true

      iex> is_valid_combination?(["10♥", "8♥"] |> parse_cards)
      false
  """
  def is_valid_combination?(hand) do
    Enum.map(hand, fn card -> card.number end) |> Enum.dedup() |> Enum.count() == 1
  end

  def extract_answer(hand) do
    Enum.drop_while(hand, fn card -> is_question?(card) end)
  end

  def is_valid_question_answer?(last_played, hand) do
    Enum.all?(
      [
        not is_question_without_answer?(hand),
        is_valid_suit_or_number?(last_played, hand),
        extract_answer(hand) |> is_valid_combination?()
      ],
      & &1
    )
  end

  # Find the intersection of two lists, providing the larger one first
  def intersection(larger, smaller) do
    Enum.filter(larger, fn larger_item -> Enum.member?(smaller, larger_item) end)
  end
end
