(ns kadi.cards
  "Card representation and deck utilities.")

(def suits #{:hearts :diamonds :clubs :spades})

(def ranks ["2" "3" "4" "5" "6" "7" "8" "9" "10" "J" "Q" "K" "A"])

(defn make-card
  "Create a card with the given suit and rank."
  [suit rank]
  {:suit suit :rank rank})

(defn make-deck
  "Create a shuffled 52-card deck."
  []
  (shuffle
   (for [suit suits
         rank ranks]
     (make-card suit rank))))

;; Card type predicates

(defn ace? [{:keys [rank]}]
  (= rank "A"))

(defn king? [{:keys [rank]}]
  (= rank "K"))

(defn jack? [{:keys [rank]}]
  (= rank "J"))

(defn question-card? [{:keys [rank]}]
  (#{"Q" "8"} rank))

(defn penalty-card? [{:keys [rank]}]
  (#{"2" "3"} rank))

(defn two? [{:keys [rank]}]
  (= rank "2"))

(defn three? [{:keys [rank]}]
  (= rank "3"))

(defn regular-card? [card]
  (not (or (ace? card)
           (king? card)
           (jack? card)
           (question-card? card)
           (penalty-card? card))))

;; Card matching

(defn matches-suit? [card1 card2]
  (= (:suit card1) (:suit card2)))

(defn matches-rank? [card1 card2]
  (= (:rank card1) (:rank card2)))

(defn matches? [card top-card]
  (or (matches-suit? card top-card)
      (matches-rank? card top-card)))

;; Starting card validation

(def invalid-starting-ranks #{"J" "2" "3"})

(defn valid-starting-card? [card]
  (not (invalid-starting-ranks (:rank card))))

(defn select-starting-card
  "Select a valid starting card from the deck."
  [deck]
  (or (first (filter valid-starting-card? deck))
      (first deck)))
