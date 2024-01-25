defmodule UtilsTest do
  use ExUnit.Case, async: true

  alias Games.Kadi.Card

  test "create_deck" do
    deck = Utils.create_deck()

    suits = ~w|hearts flowers diamonds spades|a
    num_twos = for suit <- suits, do: Card.new(2, suit)

    assert Enum.all?(num_twos, fn card -> Enum.member?(deck, card) end)
    assert Enum.all?(deck, fn card -> Enum.member?(suits, card.suit) end)
  end

  test "is_same_suit_or_number" do
    two_spades = Card.new(:two, :spades)
    two_hearts = Card.new(:two, :spades)
    four_spades = Card.new(:four, :spades)

    assert Utils.is_same_suit_or_number?(two_spades, two_hearts)
    assert Utils.is_same_suit_or_number?(two_spades, four_spades)
  end
end
