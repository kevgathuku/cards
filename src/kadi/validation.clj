(ns kadi.validation
  "Play validation - pure functions to validate card plays.

  Key rules:
  - Aces can always be played
  - During active penalty, only matching penalty cards or Aces allowed
  - Cross-blocking prevented: 2 blocks only 2, 3 blocks only 3
  - With action-suit set (from Ace), must match that suit
  - Regular play: match by suit or rank"
  (:require [kadi.cards :as cards]))

(defn all-same-rank?
  "Check if all cards have the same rank."
  [card-list]
  (apply = (map :rank card-list)))

(defn all-aces?
  "Check if all cards are Aces."
  [card-list]
  (every? cards/ace? card-list))

(defn all-jacks?
  "Check if all cards are Jacks."
  [card-list]
  (every? cards/jack? card-list))

(defn all-twos?
  "Check if all cards are 2s."
  [card-list]
  (every? cards/two? card-list))

(defn all-threes?
  "Check if all cards are 3s."
  [card-list]
  (every? cards/three? card-list))

(defn all-question-cards?
  "Check if all cards are question cards (Q or 8)."
  [card-list]
  (every? cards/question-card? card-list))

(defn valid-combo?
  "Check if cards form a valid combo."
  [card-list]
  (or (= 1 (count card-list))
      (all-aces? card-list)
      (all-jacks? card-list)
      (all-twos? card-list)
      (all-threes? card-list)
      (all-question-cards? card-list)
      (and (all-same-rank? card-list)
           (not (cards/king? (first card-list))))))

(defn valid-penalty-block?
  "Check if cards can block the active penalty."
  [card-list penalty-type]
  (case penalty-type
    :two (or (all-aces? card-list) (all-twos? card-list))
    :three (or (all-aces? card-list) (all-threes? card-list))
    false))

(defn first-card-matches-top?
  "Check if first card matches top card by suit or rank."
  [card-list top-card action-suit]
  (let [first-card (first card-list)]
    (cond
      ;; Aces always match
      (cards/ace? first-card) true

      ;; If action-suit is set, must match that suit
      action-suit (= (:suit first-card) action-suit)

      ;; Otherwise standard matching
      :else (cards/matches? first-card top-card))))

(defn question-sequence-valid?
  "Check if question card sequence is valid (each matches previous)."
  [card-list]
  (if (<= (count card-list) 1)
    true
    (let [questions (take-while cards/question-card? card-list)]
      (every? (fn [[c1 c2]] (cards/matches? c2 c1))
              (partition 2 1 questions)))))

(defn answer-valid?
  "Check if answer cards are valid for the question."
  [card-list]
  (let [questions (take-while cards/question-card? card-list)
        answers (drop (count questions) card-list)
        last-question (last questions)]
    (or (empty? answers)
        (and (not (cards/question-card? (first answers)))
             (cards/matches? (first answers) last-question)))))

(defn player-has-cards?
  "Check if player has all the cards in their hand."
  [player card-list]
  (let [hand-set (set (:hand player))]
    (every? hand-set card-list)))

(defn is-players-turn?
  "Check if it's the specified player's turn."
  [state player-id]
  (let [current-idx (:current-player-index state)
        current-player (get-in state [:players current-idx])]
    (= player-id (:id current-player))))

(defn validate-play
  "Validate a play attempt. Returns {:valid? bool, :reason string}."
  [state player-id card-list]
  (let [player (first (filter #(= player-id (:id %)) (:players state)))
        top-card (last (:played-stack state))
        penalty (get state :penalty)
        action-suit (get-in state [:action :suit])]

    (cond
      ;; Must be player's turn
      (not (is-players-turn? state player-id))
      {:valid? false :reason "Not your turn"}

      ;; Must play at least one card
      (empty? card-list)
      {:valid? false :reason "Must play at least one card"}

      ;; Player must have the cards
      (not (player-has-cards? player card-list))
      {:valid? false :reason "You don't have those cards"}

      ;; Valid combo check
      (not (valid-combo? card-list))
      {:valid? false :reason "Invalid card combination"}

      ;; During active penalty
      (:active penalty)
      (if (valid-penalty-block? card-list (:type penalty))
        {:valid? true}
        {:valid? false :reason "Must block penalty with matching card or Ace"})

      ;; Aces always valid
      (all-aces? card-list)
      {:valid? true}

      ;; King cannot be combined
      (and (cards/king? (first card-list))
           (> (count card-list) 1))
      {:valid? false :reason "Kings cannot be combined"}

      ;; First card must match top card
      (not (first-card-matches-top? card-list top-card action-suit))
      {:valid? false :reason "Card does not match top card"}

      ;; Question card sequence validation
      (and (cards/question-card? (first card-list))
           (not (question-sequence-valid? card-list)))
      {:valid? false :reason "Question cards must match each other"}

      ;; Answer validation for question combos
      (and (cards/question-card? (first card-list))
           (not (answer-valid? card-list)))
      {:valid? false :reason "Answer must match the question"}

      ;; All checks passed
      :else {:valid? true})))
