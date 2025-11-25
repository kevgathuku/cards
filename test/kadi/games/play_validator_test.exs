defmodule Kadi.Games.PlayValidatorTest do
  use ExUnit.Case, async: true

  alias Kadi.Games.{Card, PlayValidator}

  describe "valid_play?/3 - single card" do
    test "accepts card matching suit" do
      top_card = %Card{suit: "hearts", rank: "5"}
      card = %Card{suit: "hearts", rank: "4"}

      assert PlayValidator.valid_play?([card], top_card, [])
    end

    test "accepts card matching rank" do
      top_card = %Card{suit: "hearts", rank: "5"}
      card = %Card{suit: "diamonds", rank: "5"}

      assert PlayValidator.valid_play?([card], top_card, [])
    end

    test "rejects card matching neither suit nor rank" do
      top_card = %Card{suit: "hearts", rank: "5"}
      card = %Card{suit: "clubs", rank: "7"}

      refute PlayValidator.valid_play?([card], top_card, [])
    end
  end

  describe "valid_play?/3 - combo" do
    test "accepts combo with same rank and first card matches" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "hearts", rank: "4"},
        %Card{suit: "diamonds", rank: "4"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "rejects combo with different ranks" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "hearts", rank: "4"},
        %Card{suit: "diamonds", rank: "6"}
      ]

      refute PlayValidator.valid_play?(cards, top_card, [])
    end

    test "rejects combo where first card doesn't match" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "clubs", rank: "4"},
        %Card{suit: "hearts", rank: "4"}
      ]

      refute PlayValidator.valid_play?(cards, top_card, [])
    end
  end

  describe "valid_play?/3 - edge cases" do
    test "rejects empty card list" do
      top_card = %Card{suit: "hearts", rank: "5"}

      refute PlayValidator.valid_play?([], top_card, [])
    end

    test "rejects when top_card is nil" do
      card = %Card{suit: "hearts", rank: "4"}

      refute PlayValidator.valid_play?([card], nil, [])
    end
  end

  describe "valid_play?/3 - regular cards only (Phase 1)" do
    test "accepts regular cards (4,5,6,7,9,10) when they match" do
      regular_ranks = ["4", "5", "6", "7", "9", "10"]

      for rank <- regular_ranks do
        top_card = %Card{suit: "hearts", rank: "5"}
        card = %Card{suit: "hearts", rank: rank}

        assert PlayValidator.valid_play?([card], top_card, []),
               "Regular card #{rank} should be accepted"
      end
    end

    test "accepts question cards (8, Queen) when they match suit or rank" do
      # Question cards (8 and Queen) are now supported as of question-cards feature
      # They should be accepted when they match the top card by suit or rank

      # 8 matching suit
      top_card = %Card{suit: "hearts", rank: "5"}
      eight = %Card{suit: "hearts", rank: "8"}

      assert PlayValidator.valid_play?([eight], top_card, []),
             "8 matching suit should be accepted"

      # 8 matching rank
      top_card = %Card{suit: "diamonds", rank: "8"}
      eight = %Card{suit: "hearts", rank: "8"}

      assert PlayValidator.valid_play?([eight], top_card, []),
             "8 matching rank should be accepted"

      # Queen matching suit
      top_card = %Card{suit: "hearts", rank: "5"}
      queen = %Card{suit: "hearts", rank: "queen"}

      assert PlayValidator.valid_play?([queen], top_card, []),
             "Queen matching suit should be accepted"

      # Queen matching rank
      top_card = %Card{suit: "diamonds", rank: "queen"}
      queen = %Card{suit: "hearts", rank: "queen"}

      assert PlayValidator.valid_play?([queen], top_card, []),
             "Queen matching rank should be accepted"
    end

    test "accepts King when it matches suit or rank (Phase 2 - 006-king-card)" do
      # King matching suit
      top_card = %Card{suit: "hearts", rank: "5"}
      king = %Card{suit: "hearts", rank: "king"}
      assert PlayValidator.valid_play?([king], top_card, [])

      # King matching rank
      top_card2 = %Card{suit: "hearts", rank: "king"}
      king2 = %Card{suit: "spades", rank: "king"}
      assert PlayValidator.valid_play?([king2], top_card2, [])
    end

    test "accepts Jack when it matches suit or rank (Phase 3 - 007-jack-card)" do
      # Jack matching suit
      top_card = %Card{suit: "hearts", rank: "5"}
      jack = %Card{suit: "hearts", rank: "jack"}
      assert PlayValidator.valid_play?([jack], top_card, [])

      # Jack matching rank
      top_card2 = %Card{suit: "diamonds", rank: "jack"}
      jack2 = %Card{suit: "clubs", rank: "jack"}
      assert PlayValidator.valid_play?([jack2], top_card2, [])
    end

    test "accepts Jack combo when first matches (Phase 3 - 007-jack-card)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "hearts", rank: "jack"},
        %Card{suit: "diamonds", rank: "jack"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "rejects combo mixing regular and special cards" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{suit: "hearts", rank: "4"},
        %Card{suit: "diamonds", rank: "jack"}
      ]

      refute PlayValidator.valid_play?(cards, top_card, [])
    end
  end

  describe "valid_play?/3 - ace interactions" do
    test "accepts ace even when it doesn't match suit or rank" do
      top_card = %Card{suit: "hearts", rank: "5"}
      ace = %Card{suit: "clubs", rank: "ace"}

      assert PlayValidator.valid_play?([ace], top_card, [])
    end

    test "accepts multiple aces in a single play" do
      top_card = %Card{suit: "diamonds", rank: "7"}

      cards = [
        %Card{suit: "clubs", rank: "ace"},
        %Card{suit: "spades", rank: "ace"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "enforces requested suit for non-ace plays" do
      top_card = %Card{suit: "hearts", rank: "5"}
      action_suit = "clubs"

      matching_card = %Card{suit: "clubs", rank: "9"}
      non_matching_card = %Card{suit: "hearts", rank: "9"}

      assert PlayValidator.valid_play?([matching_card], top_card, action_suit: action_suit)
      refute PlayValidator.valid_play?([non_matching_card], top_card, action_suit: action_suit)
    end

    test "allows combo when lead card matches requested suit" do
      top_card = %Card{suit: "hearts", rank: "5"}
      action_suit = "spades"

      cards = [
        %Card{suit: "spades", rank: "9"},
        %Card{suit: "hearts", rank: "9"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, action_suit: action_suit)
    end

    test "rejects combo when lead card mismatches requested suit" do
      top_card = %Card{suit: "hearts", rank: "5"}
      action_suit = "spades"

      cards = [
        %Card{suit: "hearts", rank: "9"},
        %Card{suit: "spades", rank: "9"}
      ]

      refute PlayValidator.valid_play?(cards, top_card, action_suit: action_suit)
    end

    test "allows ace play even when requested suit is enforced" do
      top_card = %Card{suit: "spades", rank: "10"}
      action_suit = "hearts"
      ace = %Card{suit: "clubs", rank: "ace"}

      assert PlayValidator.valid_play?([ace], top_card, action_suit: action_suit)
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

  describe "Jack combo validation (Phase 6 - User Story 4)" do
    @tag :phase6
    @tag :us4
    test "accepts combo with all Jacks when first matches (T041)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      jacks = [
        %Card{suit: "hearts", rank: "jack"},
        %Card{suit: "clubs", rank: "jack"},
        %Card{suit: "diamonds", rank: "jack"}
      ]

      assert PlayValidator.valid_jack_play?(jacks, top_card)
    end

    @tag :phase6
    @tag :us4
    test "rejects combo with Jack + regular card (T042)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      mixed_cards = [
        %Card{suit: "hearts", rank: "jack"},
        %Card{suit: "hearts", rank: "6"}
      ]

      refute PlayValidator.valid_jack_play?(mixed_cards, top_card)
    end

    @tag :phase6
    @tag :us4
    test "rejects combo where no Jack matches (T043)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      jacks = [
        %Card{suit: "clubs", rank: "jack"},
        %Card{suit: "diamonds", rank: "jack"}
      ]

      refute PlayValidator.valid_jack_play?(jacks, top_card)
    end
  end

  describe "valid_play?/3 - 3 card validation (no penalty)" do
    test "accepts single 3 matching suit" do
      top_card = %Card{suit: "hearts", rank: "5"}
      three = %Card{suit: "hearts", rank: "3"}

      assert PlayValidator.valid_play?([three], top_card, [])
    end

    test "accepts single 3 matching rank" do
      top_card = %Card{suit: "diamonds", rank: "3"}
      three = %Card{suit: "clubs", rank: "3"}

      assert PlayValidator.valid_play?([three], top_card, [])
    end

    test "rejects single 3 not matching suit or rank" do
      top_card = %Card{suit: "hearts", rank: "5"}
      three = %Card{suit: "clubs", rank: "3"}

      refute PlayValidator.valid_play?([three], top_card, [])
    end

    test "accepts combo of 3s when first matches" do
      top_card = %Card{suit: "hearts", rank: "5"}

      threes = [
        %Card{suit: "hearts", rank: "3"},
        %Card{suit: "clubs", rank: "3"}
      ]

      assert PlayValidator.valid_play?(threes, top_card, [])
    end

    test "rejects combo of 3s when first doesn't match" do
      top_card = %Card{suit: "hearts", rank: "5"}

      threes = [
        %Card{suit: "clubs", rank: "3"},
        %Card{suit: "diamonds", rank: "3"}
      ]

      refute PlayValidator.valid_play?(threes, top_card, [])
    end
  end

  describe "valid_play?/3 - 3 card blocking when penalty active" do
    test "accepts 3 card when penalty_type is 'three'" do
      top_card = %Card{suit: "hearts", rank: "3"}
      three = %Card{suit: "clubs", rank: "3"}

      assert PlayValidator.valid_play?([three], top_card,
               penalty_active?: true,
               penalty_type: "three"
             )
    end

    test "rejects 3 card when penalty_type is 'two' (cross-blocking prevention)" do
      top_card = %Card{suit: "hearts", rank: "2"}
      three = %Card{suit: "hearts", rank: "3"}

      refute PlayValidator.valid_play?([three], top_card,
               penalty_active?: true,
               penalty_type: "two"
             )
    end

    test "accepts Ace when penalty_type is 'three'" do
      top_card = %Card{suit: "hearts", rank: "3"}
      ace = %Card{suit: "clubs", rank: "ace"}

      assert PlayValidator.valid_play?([ace], top_card,
               penalty_active?: true,
               penalty_type: "three"
             )
    end

    test "rejects regular card when penalty_type is 'three'" do
      top_card = %Card{suit: "hearts", rank: "3"}
      regular = %Card{suit: "hearts", rank: "5"}

      refute PlayValidator.valid_play?([regular], top_card,
               penalty_active?: true,
               penalty_type: "three"
             )
    end

    test "rejects 2 card when penalty_type is 'three' (cross-blocking prevention)" do
      top_card = %Card{suit: "hearts", rank: "3"}
      two = %Card{suit: "hearts", rank: "2"}

      refute PlayValidator.valid_play?([two], top_card,
               penalty_active?: true,
               penalty_type: "three"
             )
    end

    test "accepts combo of 3s when penalty_type is 'three'" do
      top_card = %Card{suit: "hearts", rank: "3"}

      threes = [
        %Card{suit: "clubs", rank: "3"},
        %Card{suit: "diamonds", rank: "3"}
      ]

      assert PlayValidator.valid_play?(threes, top_card,
               penalty_active?: true,
               penalty_type: "three"
             )
    end

    test "rejects combo of 2s when penalty_type is 'three'" do
      top_card = %Card{suit: "hearts", rank: "3"}

      twos = [
        %Card{suit: "hearts", rank: "2"},
        %Card{suit: "clubs", rank: "2"}
      ]

      refute PlayValidator.valid_play?(twos, top_card,
               penalty_active?: true,
               penalty_type: "three"
             )
    end
  end

  describe "valid_play?/3 - 3 card with action_suit" do
    test "accepts 3 matching action_suit" do
      top_card = %Card{suit: "hearts", rank: "3"}
      action_suit = "clubs"
      three = %Card{suit: "clubs", rank: "3"}

      assert PlayValidator.valid_play?([three], top_card, action_suit: action_suit)
    end

    test "rejects 3 not matching action_suit (penalty cards must match action_suit)" do
      top_card = %Card{suit: "hearts", rank: "3"}
      action_suit = "clubs"
      three = %Card{suit: "diamonds", rank: "3"}

      # When action_suit is set from regular Ace play, ALL cards must match it
      refute PlayValidator.valid_play?([three], top_card, action_suit: action_suit)
    end

    test "accepts 3 matching action_suit even with different rank" do
      top_card = %Card{suit: "hearts", rank: "5"}
      action_suit = "clubs"
      three = %Card{suit: "clubs", rank: "3"}

      # 3 of clubs matches the action_suit requirement
      assert PlayValidator.valid_play?([three], top_card, action_suit: action_suit)
    end
  end

  describe "valid_question_sequence?/1 - question card sequence validation" do
    test "accepts single question card (always valid)" do
      card = %Card{rank: "8", suit: "hearts"}

      assert PlayValidator.valid_question_sequence?([card])
    end

    test "accepts two 8s matching by rank" do
      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "8", suit: "diamonds"}
      ]

      assert PlayValidator.valid_question_sequence?(cards)
    end

    test "accepts 8 and Q matching by suit" do
      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "queen", suit: "hearts"}
      ]

      assert PlayValidator.valid_question_sequence?(cards)
    end

    test "accepts mixed Q and 8 cards (8H QH QD 8D)" do
      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "queen", suit: "hearts"},
        %Card{rank: "queen", suit: "diamonds"},
        %Card{rank: "8", suit: "diamonds"}
      ]

      assert PlayValidator.valid_question_sequence?(cards)
    end

    test "rejects 8 and Q not matching by suit or rank" do
      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "queen", suit: "diamonds"}
      ]

      refute PlayValidator.valid_question_sequence?(cards)
    end

    test "rejects sequence where middle card doesn't match" do
      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "queen", suit: "diamonds"},
        %Card{rank: "queen", suit: "clubs"}
      ]

      refute PlayValidator.valid_question_sequence?(cards)
    end

    test "rejects empty card list" do
      refute PlayValidator.valid_question_sequence?([])
    end

    test "rejects non-question card (regular card)" do
      cards = [
        %Card{rank: "5", suit: "hearts"}
      ]

      refute PlayValidator.valid_question_sequence?(cards)
    end

    test "rejects sequence with non-question card mixed in" do
      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "5", suit: "hearts"}
      ]

      refute PlayValidator.valid_question_sequence?(cards)
    end

    test "rejects sequence with ace card" do
      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "ace", suit: "hearts"}
      ]

      refute PlayValidator.valid_question_sequence?(cards)
    end
  end

  describe "valid_answer_for_question?/2 - answer card validation" do
    test "accepts single answer matching suit" do
      answer_cards = [%Card{rank: "2", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "accepts single answer matching by suit (not rank, since that would require Q or 8)" do
      # Note: Answer cards cannot be question cards (Q or 8)
      # Since last_question is Q or 8, matching by rank would require answer to also be Q or 8
      # So we test matching by suit instead
      answer_cards = [%Card{rank: "2", suit: "diamonds"}]
      last_question = %Card{rank: "queen", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "accepts answer combo matching suit (4D 4H after 8D)" do
      answer_cards = [
        %Card{rank: "4", suit: "diamonds"},
        %Card{rank: "4", suit: "hearts"}
      ]

      last_question = %Card{rank: "8", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "rejects single answer not matching suit or rank" do
      answer_cards = [%Card{rank: "2", suit: "hearts"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      refute PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "rejects answer combo with different ranks" do
      answer_cards = [
        %Card{rank: "4", suit: "diamonds"},
        %Card{rank: "5", suit: "diamonds"}
      ]

      last_question = %Card{rank: "8", suit: "diamonds"}

      refute PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "rejects answer combo where first doesn't match" do
      answer_cards = [
        %Card{rank: "4", suit: "hearts"},
        %Card{rank: "4", suit: "clubs"}
      ]

      last_question = %Card{rank: "8", suit: "diamonds"}

      refute PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "rejects empty answer list" do
      refute PlayValidator.valid_answer_for_question?([], %Card{rank: "8", suit: "diamonds"})
    end

    test "rejects when last_question_card is nil" do
      answer_cards = [%Card{rank: "2", suit: "diamonds"}]

      refute PlayValidator.valid_answer_for_question?(answer_cards, nil)
    end

    test "rejects answer cards containing question cards (Q)" do
      answer_cards = [%Card{rank: "queen", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      refute PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "rejects answer cards containing question cards (8)" do
      answer_cards = [%Card{rank: "8", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "hearts"}

      refute PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "accepts special cards as answers (Ace)" do
      answer_cards = [%Card{rank: "ace", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "accepts special cards as answers (Jack)" do
      answer_cards = [%Card{rank: "jack", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "accepts special cards as answers (King)" do
      answer_cards = [%Card{rank: "king", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "accepts penalty cards as answers (2)" do
      answer_cards = [%Card{rank: "2", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "accepts penalty cards as answers (3)" do
      answer_cards = [%Card{rank: "3", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end

    test "accepts regular cards as answers" do
      answer_cards = [%Card{rank: "5", suit: "diamonds"}]
      last_question = %Card{rank: "8", suit: "diamonds"}

      assert PlayValidator.valid_answer_for_question?(answer_cards, last_question)
    end
  end

  describe "valid_play?/3 - question card integration" do
    test "accepts single question card matching top card by suit" do
      top_card = %Card{suit: "hearts", rank: "5"}
      eight = %Card{suit: "hearts", rank: "8"}

      assert PlayValidator.valid_play?([eight], top_card, [])
    end

    test "accepts single question card matching top card by rank" do
      top_card = %Card{suit: "diamonds", rank: "8"}
      eight = %Card{suit: "hearts", rank: "8"}

      assert PlayValidator.valid_play?([eight], top_card, [])
    end

    test "rejects single question card not matching top card" do
      top_card = %Card{suit: "diamonds", rank: "5"}
      eight = %Card{suit: "hearts", rank: "8"}

      refute PlayValidator.valid_play?([eight], top_card, [])
    end

    test "accepts question combo with answer (8H 8D 2D)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "8", suit: "diamonds"},
        %Card{rank: "2", suit: "diamonds"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "accepts question combo without answer (8H 8D)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "8", suit: "diamonds"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "accepts mixed Q and 8 combo with answer (8H QH 2H)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "queen", suit: "hearts"},
        %Card{rank: "2", suit: "hearts"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "accepts question combo with answer combo (8H 8D 4D 4H)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "8", suit: "diamonds"},
        %Card{rank: "4", suit: "diamonds"},
        %Card{rank: "4", suit: "hearts"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "rejects question combo where first card doesn't match top card" do
      top_card = %Card{suit: "diamonds", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "8", suit: "clubs"}
      ]

      refute PlayValidator.valid_play?(cards, top_card, [])
    end

    test "rejects question combo where questions don't match each other" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "queen", suit: "diamonds"}
      ]

      refute PlayValidator.valid_play?(cards, top_card, [])
    end

    test "rejects question combo where answer doesn't match last question" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "8", suit: "diamonds"},
        %Card{rank: "2", suit: "hearts"}
      ]

      refute PlayValidator.valid_play?(cards, top_card, [])
    end

    test "accepts question combo ending with Q/8 (all questions)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "8", suit: "diamonds"},
        %Card{rank: "queen", suit: "diamonds"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "accepts question with special card answer (Ace)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "ace", suit: "hearts"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "accepts question with special card answer (Jack)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "jack", suit: "hearts"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end

    test "accepts question with special card answer (King)" do
      top_card = %Card{suit: "hearts", rank: "5"}

      cards = [
        %Card{rank: "8", suit: "hearts"},
        %Card{rank: "king", suit: "hearts"}
      ]

      assert PlayValidator.valid_play?(cards, top_card, [])
    end
  end
end
