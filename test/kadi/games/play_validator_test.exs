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
end
