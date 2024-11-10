defmodule Kadi.Games.UtilsTest do
  use ExUnit.Case, async: true

  alias Kadi.Games.Poker.Card
  alias Kadi.Utils
  doctest Kadi.Utils

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

    assert Utils.is_same_number?(two_cards)
    refute Utils.is_same_number?(diff_number_cards)
  end

  describe "is_valid_hand?" do
    test "single card of the same suit is valid" do
      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:nine, :diamonds)
             ])
    end

    test "single card of a different suit is not valid" do
      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:nine, :spades)
             ])
    end

    test "single card of Q or 8 of the same suit is not valid" do
      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:q, :diamonds)
             ])

      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds)
             ])
    end

    test "single card of A of any suit is valid" do
      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:a, :diamonds)
             ])

      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:a, :spades)
             ])

      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:a, :flowers)
             ])

      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:a, :hearts)
             ])
    end

    test "multiple cards of the same number are valid" do
      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:ten, :spades),
               Card.new(:ten, :hearts)
             ])

      assert Utils.is_valid_hand?(Card.new(:eight, :spades), [
               Card.new(:ten, :spades),
               Card.new(:ten, :hearts)
             ])

      # Same suit. Different numbers
      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:five, :diamonds),
               Card.new(:two, :diamonds)
             ])
    end

    test "question and answer hands" do
      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds),
               Card.new(:five, :diamonds)
             ])

      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds),
               Card.new(:q, :diamonds),
               Card.new(:five, :diamonds),
               Card.new(:five, :hearts)
             ])

      assert Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds),
               Card.new(:q, :diamonds),
               Card.new(:q, :hearts),
               Card.new(:five, :hearts),
               Card.new(:five, :diamonds)
             ])

      # Invalid question
      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds),
               Card.new(:q, :hearts),
               Card.new(:five, :hearts),
               Card.new(:five, :diamonds)
             ])

      # Invalid answer
      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds),
               Card.new(:five, :diamonds),
               Card.new(:two, :diamonds)
             ])

      # Question should come first
      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:five, :diamonds),
               Card.new(:eight, :diamonds)
             ])

      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds)
             ])

      refute Utils.is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds),
               Card.new(:q, :diamonds)
             ])
    end

    test "is_valid_suit_or_number?" do
      last_played = %Card{suit: :spades, number: :ten}

      hand = [
        %Card{suit: :hearts, number: :ten},
        %Card{suit: :diamonds, number: :ten}
      ]

      assert Utils.is_valid_suit_or_number?(last_played, hand)
    end
  end
end
