defmodule Kadi.Games.Poker.Card do
  @moduledoc """
  A struct to represent a card
  """

  @type t :: %__MODULE__{}
  @type suit :: :hearts | :flowers | :diamonds | :spades
  @type value ::
          :two
          | :three
          | :four
          | :five
          | :six
          | :seven
          | :eight
          | :nine
          | :ten
          | :k
          | :q
          | :j
          | :a

  defstruct [:suit, :number]

  @doc """
  Create a new Card struct

  ## Examples

      iex> new(:two, :hearts)
      %Card{suit: :hearts, number: :two}

      iex> new(2, :diamonds)
      %Card{suit: :diamonds, number: :two}
  """
  @spec new(value() | non_neg_integer(), suit()) :: t()
  def new(number, suit) when is_integer(number),
    do: %__MODULE__{suit: suit, number: from_number(number)}

  # TODO: Prevent passing in invalid values
  def new(number, suit) do
    %__MODULE__{
      suit: suit,
      number: number
    }
  end

  @doc """
  Returns the score value for the provided card.
  When the game ends, the player with the
  highest value cards loses

  ## Examples
      iex> score(%Card{suit: :hearts, number: :k})
      13

      iex> score(%Card{suit: :hearts, number: :q})
      12

      iex> score(%Card{suit: :diamonds, number: :j})
      11

      iex> score(%Card{suit: :hearts, number: :a})
      100

      iex> score(%Card{suit: :spades, number: :a})
      500
  """
  @spec score(t()) :: non_neg_integer()
  def score(card)
  def score(%{number: :two}), do: 50
  def score(%{number: :three}), do: 75
  def score(%{number: :four}), do: 4
  def score(%{number: :five}), do: 5
  def score(%{number: :six}), do: 6
  def score(%{number: :seven}), do: 7
  def score(%{number: :eight}), do: 12
  def score(%{number: :nine}), do: 9
  def score(%{number: :ten}), do: 10
  def score(%{number: :j}), do: 11
  def score(%{number: :q}), do: 12
  def score(%{number: :k}), do: 13
  def score(%{suit: :spades, number: :a}), do: 500
  def score(%{number: :a}), do: 100

  @doc """
  Returns the value atom for the specified number.

  ## Examples

      iex> from_number(3)
      :three
  """
  @spec from_number(non_neg_integer()) :: value()
  def from_number(2), do: :two
  def from_number(3), do: :three
  def from_number(4), do: :four
  def from_number(5), do: :five
  def from_number(6), do: :six
  def from_number(7), do: :seven
  def from_number(8), do: :eight
  def from_number(9), do: :nine
  def from_number(10), do: :ten

  @doc """
  Returns a new Card instance from the provided shorthand format

  ## Examples

      iex> parse("10♣")
      %Card{number: :ten, suit: :flowers}

      iex> parse("3♦")
      %Card{number: :three, suit: :diamonds}
  """
  def parse(short_format) do
    {suit, remaining} = String.graphemes(short_format) |> List.pop_at(-1)

    %__MODULE__{suit: parse_suit(suit), number: parse_value(Enum.join(remaining))}
  end

  defp parse_suit("H"), do: :hearts
  defp parse_suit("♥"), do: :hearts
  defp parse_suit("S"), do: :spades
  defp parse_suit("♠"), do: :spades
  defp parse_suit("D"), do: :diamonds
  defp parse_suit("♦"), do: :diamonds
  defp parse_suit("F"), do: :flowers
  defp parse_suit("♣"), do: :flowers

  defp parse_value("A"), do: :a
  defp parse_value("K"), do: :k
  defp parse_value("Q"), do: :q
  defp parse_value("J"), do: :j
  defp parse_value(other), do: other |> String.to_integer() |> from_number()
end
