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
    two_hearts = Card.new(:two, :hearts)
    four_spades = Card.new(:four, :spades)

    assert Utils.is_same_suit_or_number?(two_spades, two_hearts) == true
    assert Utils.is_same_suit_or_number?(two_spades, four_spades) == true
    assert Utils.is_same_suit_or_number?(two_hearts, four_spades) == false
  end

  test "is_same_number" do
    two_cards = [Card.new(:two, :spades), Card.new(:two, :hearts)]

    assert Utils.is_same_number?(two_cards) == true
  end
end
