defmodule Kadi.Games.Poker.CardTest do
  use ExUnit.Case, async: true
  alias Kadi.Games.Poker.Card

  doctest Card, import: true

  describe "new" do
    test "initializes a card with suit and value" do
      card = Card.new(:seven, :diamonds)

      assert card.suit == :diamonds
      assert card.number == :seven
    end

    test "initializes a card with integer and suit" do
      card = Card.new(7, :hearts)

      assert card.suit == :hearts
      assert card.number == :seven
    end
  end

  describe "score" do
    test "cards scores" do
      two = Card.new(:two, :diamonds)
      three = Card.new(:three, :flowers)
      four = Card.new(:four, :spades)
      five = Card.new(:five, :hearts)
      six = Card.new(:six, :diamonds)
      seven = Card.new(:seven, :flowers)
      eight = Card.new(:eight, :spades)
      nine = Card.new(:nine, :hearts)
      ten = Card.new(:ten, :diamonds)
      jump = Card.new(:j, :flowers)
      queen = Card.new(:q, :diamonds)
      kickback = Card.new(:k, :diamonds)
      ace = Card.new(:a, :flowers)
      ace_of_spades = Card.new(:a, :spades)

      assert Card.score(two) == 50
      assert Card.score(three) == 75
      assert Card.score(four) == 4
      assert Card.score(five) == 5
      assert Card.score(six) == 6
      assert Card.score(seven) == 7
      assert Card.score(eight) == 12
      assert Card.score(nine) == 9
      assert Card.score(nine) == 9
      assert Card.score(ten) == 10
      assert Card.score(jump) == 11
      assert Card.score(queen) == 12
      assert Card.score(kickback) == 13
      assert Card.score(ace) == 100
      assert Card.score(ace_of_spades) == 500
    end
  end
end
