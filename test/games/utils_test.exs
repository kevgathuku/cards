defmodule UtilsTest do
  alias Games.Kadi.Card
  use ExUnit.Case, async: true

  test "create_deck" do
    deck = Utils.create_deck()

    suits = ~w(Hearts Flowers Diamonds Spades)
    num_twos = for suit <- suits, do: {2, suit}

    assert Enum.all?(num_twos, fn card -> Enum.member?(deck, card) end)
    assert Enum.all?(deck, fn {_, suit} -> Enum.member?(suits, suit) end)
  end

  test "is_same_suit_or_number" do
    two_spades = Card.new(:two, :spades)
    two_hearts = Card.new(:two, :spades)
    four_spades = Card.new(:four, :spades)

    assert Utils.is_same_suit_or_number?(two_spades, two_hearts)
    assert Utils.is_same_suit_or_number?(two_spades, four_spades)
  end
end
