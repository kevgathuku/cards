defmodule Kadi.Games.UtilsTest do
  use ExUnit.Case, async: true

  alias Kadi.Games.Poker.Card
  import Kadi.Utils

  doctest Kadi.Utils, import: true

  test "create_deck" do
    deck = create_deck()

    suits = ~w|hearts flowers diamonds spades|a
    num_twos = for suit <- suits, do: Card.new(2, suit)

    assert Enum.all?(num_twos, fn card -> Enum.member?(deck, card) end)
    assert Enum.all?(deck, fn card -> Enum.member?(suits, card.suit) end)
  end

  test "is_same_suit_or_number" do
    two_spades = Card.new(:two, :spades)
    two_hearts = Card.new(:two, :hearts)
    four_spades = Card.new(:four, :spades)

    assert is_same_suit_or_number?(two_spades, two_hearts) == true
    assert is_same_suit_or_number?(two_spades, four_spades) == true
    assert is_same_suit_or_number?(two_hearts, four_spades) == false
  end

  test "is_same_number" do
    two_cards = [Card.new(:two, :spades), Card.new(:two, :hearts)]
    diff_number_cards = [Card.new(:two, :spades), Card.new(:three, :spades)]

    assert is_same_number?(two_cards)
    refute is_same_number?(diff_number_cards)
  end

  describe "is_valid_hand?" do
    test "single card of the same suit is valid" do
      assert is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:nine, :diamonds)
             ])
    end

    test "single card of a different suit is not valid" do
      refute is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:nine, :spades)
             ])
    end

    test "single card of Q or 8 of the same suit is not valid" do
      refute is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:q, :diamonds)
             ])

      refute is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds)
             ])
    end

    test "single card of A of any suit is valid" do
      assert is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:a, :diamonds)
             ])

      assert is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:a, :spades)
             ])

      assert is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:a, :flowers)
             ])

      assert is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:a, :hearts)
             ])
    end

    test "multiple cards of the same number are valid" do
      assert is_valid_hand?(
               Card.new(:ten, :diamonds),
               parse_cards([
                 "10♠",
                 "10♥"
               ])
             )

      assert is_valid_hand?(Card.new(:eight, :spades), [
               Card.new(:ten, :spades),
               Card.new(:ten, :hearts)
             ])

      # Same suit. Different numbers
      refute is_valid_hand?(
               Card.new(:ten, :diamonds),
               [
                 "5♦",
                 "2♦"
               ]
               |> parse_cards
             )
    end

    test "question and answer hands" do
      assert is_valid_hand?(
               Card.new(:ten, :diamonds),
               [
                 "8♦",
                 "5♦"
               ]
               |> parse_cards
             )

      assert is_valid_hand?(
               Card.new(:ten, :diamonds),
               [
                 "8♦",
                 "Q♦",
                 "5♦",
                 "5♥"
               ]
               |> parse_cards
             )

      assert is_valid_hand?(
               Card.new(:ten, :diamonds),
               [
                 "8♦",
                 "Q♦",
                 "Q♥",
                 "5♥",
                 "5♦"
               ]
               |> parse_cards
             )

      # Invalid question
      refute is_valid_hand?(
               Card.new(:ten, :diamonds),
               [
                 "8♦",
                 "Q♥",
                 "5♥",
                 "5♦"
               ]
               |> parse_cards
             )

      # Invalid answer
      invalid_answer = for card <- ["8♦", "5♦", "2♦"], do: Card.parse(card)

      refute is_valid_hand?(Card.new(:ten, :diamonds), invalid_answer)

      # Question should come first
      refute is_valid_hand?(
               Card.new(:ten, :diamonds),
               [
                 "5♦",
                 "8♦"
               ]
               |> parse_cards
             )

      refute is_valid_hand?(Card.new(:ten, :diamonds), [
               Card.new(:eight, :diamonds)
             ])

      refute is_valid_hand?(
               Card.new(:ten, :diamonds),
               [
                 "8♦",
                 "Q♦"
               ]
               |> parse_cards
             )
    end

    test "is_valid_suit_or_number?" do
      last_played = %Card{suit: :spades, number: :ten}

      hand =
        ["10♥", "10♦"] |> parse_cards

      assert is_valid_suit_or_number?(last_played, hand)
    end
  end
end
