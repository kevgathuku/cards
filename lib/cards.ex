defmodule Cards do
  @moduledoc """
  Documentation for `Cards`.
  """

  def generate_permutations(list1, list2) do
    Enum.flat_map(list1, fn item1 ->
      for item2 <- list2, do: {item1, item2}
    end)
  end

  def create_deck do
    numbers = [:ace, :two, :three, :four, :five, :six, :seven, :eight, :nine, :ten, :king, :queen, :j]
    suits = [:flowers, :diamonds, :hearts, :spades]
    # Enum.zip(numbers, suits)
    Enum.flat_map(numbers, fn number ->
      for suit <- suits, do: {number, suit}
    end)
  end

  def shuffle(deck) do
    Enum.shuffle(deck)
  end
end
