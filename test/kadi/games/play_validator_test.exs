defmodule Kadi.Games.PlayValidatorTest do
  use ExUnit.Case, async: true

  alias Kadi.Games.{Card, PlayValidator}

  describe "valid_play?/2 - single card" do
    test "accepts card matching suit" do
      top_card = %Card{suit: "hearts", rank: "5"}
      card = %Card{suit: "hearts", rank: "4"}

      assert PlayValidator.valid_play?([card], top_card)
    end

    test "accepts card matching rank" do
      top_card = %Card{suit: "hearts", rank: "5"}
      card = %Card{suit: "diamonds", rank: "5"}

      assert PlayValidator.valid_play?([card], top_card)
    end

    test "rejects card matching neither suit nor rank" do
      top_card = %Card{suit: "hearts", rank: "5"}
      card = %Card{suit: "clubs", rank: "7"}

      refute PlayValidator.valid_play?([card], top_card)
    end
  end

  describe "valid_play?/2 - combo" do
    test "accepts combo with same rank and first card matches" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "hearts", rank: "4"},
        %Card{suit: "diamonds", rank: "4"}
      ]

      assert PlayValidator.valid_play?(cards, top_card)
    end

    test "rejects combo with different ranks" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "hearts", rank: "4"},
        %Card{suit: "diamonds", rank: "6"}
      ]

      refute PlayValidator.valid_play?(cards, top_card)
    end

    test "rejects combo where first card doesn't match" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "clubs", rank: "4"},
        %Card{suit: "hearts", rank: "4"}
      ]

      refute PlayValidator.valid_play?(cards, top_card)
    end
  end

  describe "valid_play?/2 - edge cases" do
    test "rejects empty card list" do
      top_card = %Card{suit: "hearts", rank: "5"}

      refute PlayValidator.valid_play?([], top_card)
    end

    test "rejects when top_card is nil" do
      card = %Card{suit: "hearts", rank: "4"}

      refute PlayValidator.valid_play?([card], nil)
    end
  end

  describe "valid_play?/2 - regular cards only (Phase 1)" do
    test "accepts regular cards (4,5,6,7,9,10) when they match" do
      regular_ranks = ["4", "5", "6", "7", "9", "10"]

      for rank <- regular_ranks do
        top_card = %Card{suit: "hearts", rank: "5"}
        card = %Card{suit: "hearts", rank: rank}

        assert PlayValidator.valid_play?([card], top_card),
               "Regular card #{rank} should be accepted"
      end
    end

    test "rejects special cards (2,3,8,Queen,Ace) even when they match - except King and Jack" do
      # King is now supported in Phase 2 (006-king-card)
      # Jack is now supported in Phase 3 (007-jack-card)
      special_ranks = ["2", "3", "8", "queen", "ace"]

      for rank <- special_ranks do
        top_card = %Card{suit: "hearts", rank: rank}
        card = %Card{suit: "hearts", rank: rank}

        refute PlayValidator.valid_play?([card], top_card),
               "Special card #{rank} should be rejected in Phase 1"
      end
    end

    test "accepts King when it matches suit or rank (Phase 2 - 006-king-card)" do
      # King matching suit
      top_card = %Card{suit: "hearts", rank: "5"}
      king = %Card{suit: "hearts", rank: "king"}
      assert PlayValidator.valid_play?([king], top_card)

      # King matching rank
      top_card2 = %Card{suit: "hearts", rank: "king"}
      king2 = %Card{suit: "spades", rank: "king"}
      assert PlayValidator.valid_play?([king2], top_card2)
    end

    test "accepts Jack when it matches suit or rank (Phase 3 - 007-jack-card)" do
      # Jack matching suit
      top_card = %Card{suit: "hearts", rank: "5"}
      jack = %Card{suit: "hearts", rank: "jack"}
      assert PlayValidator.valid_play?([jack], top_card)

      # Jack matching rank
      top_card2 = %Card{suit: "diamonds", rank: "jack"}
      jack2 = %Card{suit: "clubs", rank: "jack"}
      assert PlayValidator.valid_play?([jack2], top_card2)
    end

    test "accepts Jack combo when first matches (Phase 3 - 007-jack-card)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "hearts", rank: "jack"},
        %Card{suit: "diamonds", rank: "jack"}
      ]

      assert PlayValidator.valid_play?(cards, top_card)
    end

    test "rejects combo mixing regular and special cards" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "hearts", rank: "4"},
        %Card{suit: "diamonds", rank: "jack"}
      ]

      refute PlayValidator.valid_play?(cards, top_card)
    end
  end

  describe "player_has_cards?/2" do
    test "returns true when player has all cards" do
      player_cards = [
        %Card{id: 1, suit: "hearts", rank: "4"},
        %Card{id: 2, suit: "diamonds", rank: "5"},
        %Card{id: 3, suit: "clubs", rank: "6"}
      ]

      cards_to_play = [
        %Card{id: 1, suit: "hearts", rank: "4"},
        %Card{id: 2, suit: "diamonds", rank: "5"}
      ]

      assert PlayValidator.player_has_cards?(player_cards, cards_to_play)
    end

    test "returns false when player is missing cards" do
      player_cards = [
        %Card{id: 1, suit: "hearts", rank: "4"},
        %Card{id: 2, suit: "diamonds", rank: "5"}
      ]

      cards_to_play = [
        %Card{id: 1, suit: "hearts", rank: "4"},
        %Card{id: 3, suit: "clubs", rank: "6"}
      ]

      refute PlayValidator.player_has_cards?(player_cards, cards_to_play)
    end

    test "returns true for empty cards_to_play" do
      player_cards = [
        %Card{id: 1, suit: "hearts", rank: "4"}
      ]

      assert PlayValidator.player_has_cards?(player_cards, [])
    end
  end

  describe "valid_king_play?/2 - King card validation (User Story 1)" do
    test "accepts single King matching suit" do
      top_card = %Card{suit: "hearts", rank: "5"}
      king = %Card{suit: "hearts", rank: "king"}

      assert PlayValidator.valid_king_play?([king], top_card)
    end

    test "accepts single King matching rank" do
      top_card = %Card{suit: "hearts", rank: "king"}
      king = %Card{suit: "spades", rank: "king"}

      assert PlayValidator.valid_king_play?([king], top_card)
    end

    test "rejects King not matching suit or rank" do
      top_card = %Card{suit: "hearts", rank: "5"}
      king = %Card{suit: "spades", rank: "king"}

      refute PlayValidator.valid_king_play?([king], top_card)
    end

    test "rejects multiple Kings (FR-005)" do
      top_card = %Card{suit: "hearts", rank: "king"}

      kings = [
        %Card{suit: "hearts", rank: "king"},
        %Card{suit: "spades", rank: "king"}
      ]

      refute PlayValidator.valid_king_play?(kings, top_card)
    end

    test "rejects King in combo with other cards" do
      top_card = %Card{suit: "hearts", rank: "king"}

      cards = [
        %Card{suit: "hearts", rank: "king"},
        %Card{suit: "diamonds", rank: "5"}
      ]

      refute PlayValidator.valid_king_play?(cards, top_card)
    end

    test "rejects empty card list" do
      top_card = %Card{suit: "hearts", rank: "5"}

      refute PlayValidator.valid_king_play?([], top_card)
    end

    test "rejects when top_card is nil" do
      king = %Card{suit: "hearts", rank: "king"}

      refute PlayValidator.valid_king_play?([king], nil)
    end
  end

  describe "valid_jack_play?/2 - Jack card validation (Feature 007)" do
    test "accepts single Jack matching by suit" do
      top_card = %Card{suit: "hearts", rank: "5"}
      jack = %Card{suit: "hearts", rank: "jack"}

      assert PlayValidator.valid_jack_play?([jack], top_card)
    end

    test "accepts single Jack matching by rank" do
      top_card = %Card{suit: "diamonds", rank: "jack"}
      jack = %Card{suit: "clubs", rank: "jack"}

      assert PlayValidator.valid_jack_play?([jack], top_card)
    end

    test "accepts Jack combo when first matches" do
      top_card = %Card{suit: "hearts", rank: "5"}

      jacks = [
        %Card{suit: "hearts", rank: "jack"},
        %Card{suit: "clubs", rank: "jack"}
      ]

      assert PlayValidator.valid_jack_play?(jacks, top_card)
    end

    test "rejects Jack when neither suit nor rank matches" do
      top_card = %Card{suit: "diamonds", rank: "5"}
      jack = %Card{suit: "hearts", rank: "jack"}

      refute PlayValidator.valid_jack_play?([jack], top_card)
    end

    test "rejects combo with non-Jack cards" do
      top_card = %Card{suit: "hearts", rank: "jack"}

      cards = [
        %Card{suit: "hearts", rank: "jack"},
        %Card{suit: "hearts", rank: "5"}
      ]

      refute PlayValidator.valid_jack_play?(cards, top_card)
    end

    test "rejects empty card list" do
      top_card = %Card{suit: "hearts", rank: "5"}

      refute PlayValidator.valid_jack_play?([], top_card)
    end

    test "rejects when top_card is nil" do
      jack = %Card{suit: "hearts", rank: "jack"}

      refute PlayValidator.valid_jack_play?([jack], nil)
    end
  end
end
