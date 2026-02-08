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
  "Check if answer cards are valid for the question.
  - No answer cards is valid (question-only play)
  - All answer cards must NOT be question cards
  - First answer must match last question by suit or rank
  - Multiple answers must all share the same rank"
  [card-list]
  (let [questions (take-while cards/question-card? card-list)
        answers (drop (count questions) card-list)
        last-question (last questions)]
    (or (empty? answers)
        (and (every? (complement cards/question-card?) answers)
             (cards/matches? (first answers) last-question)
             (or (< (count answers) 2) (all-same-rank? answers))))))

(defn player-has-cards?
  "Check if player has all the cards in their hand."
  [player card-list]
  (let [hand-set (set (:hand player))]
    (every? hand-set card-list)))

(defn is-players-turn?
  "Check if it's the specified player's turn."
  [state player-id]
  (let [current-idx (get-in state [:turn :current-player-index])
        current-player (get-in state [:players current-idx])]
    (= player-id (:id current-player))))

(defn active-penalty
  "Return active penalty effect map or nil."
  [state]
  (first (filter #(= :penalty (:type %)) (:effects state))))

(defn action-suit
  "Return selected suit if present (after select-suit)."
  [state]
  (some->> (:effects state)
           (filter #(= :suit-selected (:type %)))
           first
           :suit))

(defn validate-play
  "Validate a play attempt. Returns {:valid? bool, :reason string}."
  [state player-id card-list]
  (let [hand (get-in state [:zones :hands player-id] [])
        player {:id player-id :hand hand}  ; Create temporary player with embedded hand
        top-card (last (get-in state [:zones :played-stack]))
        penalty (active-penalty state)
        action-suit (action-suit state)]

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

      ;; Must answer question before playing
      (some #(= :awaiting-answer (:type %)) (:effects state))
      {:valid? false :reason "Must draw to answer the question first"}

      ;; During active penalty
      penalty
      (if (valid-penalty-block? card-list (:penalty-type penalty))
        {:valid? true}
        {:valid? false :reason "Must block penalty with matching card or Ace"})

      ;; Aces always valid
      (all-aces? card-list)
      {:valid? true}

      ;; Question card play (Q or 8 as first card) — uses question-specific validation
      ;; instead of valid-combo?, allowing Q+answer plays like [Q-hearts 5-hearts]
      (cards/question-card? (first card-list))
      (cond
        (not (first-card-matches-top? card-list top-card action-suit))
        {:valid? false :reason "Card does not match top card"}

        (not (question-sequence-valid? card-list))
        {:valid? false :reason "Question cards must match each other"}

        (not (answer-valid? card-list))
        {:valid? false :reason "Answer must match the question"}

        :else {:valid? true})

      ;; Valid combo check (non-question cards)
      (not (valid-combo? card-list))
      {:valid? false :reason "Invalid card combination"}

      ;; King cannot be combined
      (and (cards/king? (first card-list))
           (> (count card-list) 1))
      {:valid? false :reason "Kings cannot be combined"}

      ;; First card must match top card
      (not (first-card-matches-top? card-list top-card action-suit))
      {:valid? false :reason "Card does not match top card"}

      ;; All checks passed
      :else {:valid? true})))
