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
    diff_number_cards = [Card.new(:two, :spades), Card.new(:three, :spades)]

    assert Utils.is_same_number?(two_cards) == true
    assert Utils.is_same_number?(diff_number_cards) == false
  end

  describe "is_valid_hand?" do
    test "single card of the same suit is valid" do
      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:nine, :diamonds)
             ]) == true
    end

    test "single card of a different suit is not valid" do
      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:nine, :spades)
             ]) == false
    end

    test "single card of Q or 8 of the same suit is not valid" do
      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:q, :diamonds)
             ]) == false

      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:eight, :diamonds)
             ]) == false
    end

    test "single card of A of any suit is valid" do
      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:a, :diamonds)
             ]) == true

      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:a, :spades)
             ]) == true

      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:a, :flowers)
             ]) == true

      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:a, :hearts)
             ]) == true
    end

    test "multiple cards of the same number are valid" do
      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [
               Games.Kadi.Card.new(:ten, :spades),
               Games.Kadi.Card.new(:ten, :hearts)
             ]) == true

      assert Utils.is_valid_hand?(Games.Kadi.Card.new(:eight, :spades), [
               Games.Kadi.Card.new(:ten, :spades),
               Games.Kadi.Card.new(:ten, :hearts)
             ]) == true
    end
  end
end
