(ns kadi.validation-test
  (:require [clojure.test :refer [deftest testing is]]
            [kadi.validation :as validation]
            [kadi.cards :as cards]))

;; =============================================================================
;; Test Helpers
;; =============================================================================

(defn make-card [suit rank]
  {:suit suit :rank rank})

;; =============================================================================
;; valid-combo? Tests
;; =============================================================================

(deftest valid-combo-test
  (testing "single card is always a valid combo"
    (is (validation/valid-combo? [(make-card :hearts "5")])))

  (testing "same-rank combo is valid (non-king)"
    (is (validation/valid-combo? [(make-card :hearts "5") (make-card :clubs "5")])))

  (testing "Q+8 combo is valid (both are question cards)"
    (is (validation/valid-combo? [(make-card :hearts "Q") (make-card :clubs "8")])))

  (testing "king cannot combine"
    (is (not (validation/valid-combo? [(make-card :hearts "K") (make-card :clubs "K")]))))

  (testing "mixed ranks are invalid"
    (is (not (validation/valid-combo? [(make-card :hearts "5") (make-card :clubs "6")]))))

  (testing "multiple aces are valid"
    (is (validation/valid-combo? [(make-card :hearts "A") (make-card :clubs "A")])))

  (testing "multiple jacks are valid"
    (is (validation/valid-combo? [(make-card :hearts "J") (make-card :clubs "J")])))

  (testing "multiple twos are valid"
    (is (validation/valid-combo? [(make-card :hearts "2") (make-card :clubs "2")])))

  (testing "multiple threes are valid"
    (is (validation/valid-combo? [(make-card :hearts "3") (make-card :clubs "3")]))))

;; =============================================================================
;; valid-penalty-block? Tests
;; =============================================================================

(deftest valid-penalty-block-test
  (testing "2 blocks 2 penalty"
    (is (validation/valid-penalty-block? [(make-card :hearts "2")] :two)))

  (testing "3 blocks 3 penalty"
    (is (validation/valid-penalty-block? [(make-card :hearts "3")] :three)))

  (testing "Ace blocks 2 penalty"
    (is (validation/valid-penalty-block? [(make-card :hearts "A")] :two)))

  (testing "Ace blocks 3 penalty"
    (is (validation/valid-penalty-block? [(make-card :hearts "A")] :three)))

  (testing "cross-blocking prevented: 2 cannot block 3"
    (is (not (validation/valid-penalty-block? [(make-card :hearts "2")] :three))))

  (testing "cross-blocking prevented: 3 cannot block 2"
    (is (not (validation/valid-penalty-block? [(make-card :hearts "3")] :two))))

  (testing "regular card cannot block penalty"
    (is (not (validation/valid-penalty-block? [(make-card :hearts "5")] :two)))))

;; =============================================================================
;; first-card-matches-top? Tests
;; =============================================================================

(deftest first-card-matches-top-test
  (testing "ace always matches"
    (is (validation/first-card-matches-top?
         [(make-card :clubs "A")]
         (make-card :hearts "5")
         nil)))

  (testing "action-suit enforcement"
    (is (validation/first-card-matches-top?
         [(make-card :hearts "5")]
         (make-card :clubs "A")
         :hearts))
    (is (not (validation/first-card-matches-top?
              [(make-card :clubs "5")]
              (make-card :clubs "A")
              :hearts))))

  (testing "suit matching"
    (is (validation/first-card-matches-top?
         [(make-card :hearts "9")]
         (make-card :hearts "5")
         nil)))

  (testing "rank matching"
    (is (validation/first-card-matches-top?
         [(make-card :clubs "5")]
         (make-card :hearts "5")
         nil)))

  (testing "no match"
    (is (not (validation/first-card-matches-top?
              [(make-card :clubs "9")]
              (make-card :hearts "5")
              nil)))))

;; =============================================================================
;; question-sequence-valid? Tests
;; =============================================================================

(deftest question-sequence-valid-test
  (testing "single question card is valid"
    (is (validation/question-sequence-valid? [(make-card :hearts "Q")])))

  (testing "Q chain matching by suit"
    (is (validation/question-sequence-valid?
         [(make-card :hearts "Q") (make-card :hearts "8")])))

  (testing "Q+8 combo matching by suit"
    (is (validation/question-sequence-valid?
         [(make-card :hearts "Q") (make-card :hearts "8")]))))

;; =============================================================================
;; validate-play Integration Tests
;; =============================================================================

(deftest validate-play-test
  (let [base-state {:status :live
                    :players [{:id 1 :name "Alice" :status :normal
                               :hand [(make-card :hearts "5") (make-card :clubs "A")]}
                              {:id 2 :name "Bob" :status :normal
                               :hand [(make-card :diamonds "7")]}]
                    :turn {:current-player-index 0 :direction :clockwise}
                    :zones {:deck [(make-card :spades "10")]
                            :played-stack [(make-card :hearts "9")]
                            :hands {1 [(make-card :hearts "5") (make-card :clubs "A")]
                                    2 [(make-card :diamonds "7")]}}
                    :effects []}]

    (testing "valid play by suit match"
      (let [result (validation/validate-play base-state 1 [(make-card :hearts "5")])]
        (is (:valid? result))))

    (testing "valid play with ace (always matches)"
      (let [result (validation/validate-play base-state 1 [(make-card :clubs "A")])]
        (is (:valid? result))))

    (testing "not your turn"
      (let [result (validation/validate-play base-state 2 [(make-card :diamonds "7")])]
        (is (not (:valid? result)))
        (is (= "Not your turn" (:reason result)))))

    (testing "card doesn't match top"
      (let [state (assoc-in base-state [:players 0 :hand]
                            [(make-card :clubs "6")])
            result (validation/validate-play state 1 [(make-card :clubs "6")])]
        (is (not (:valid? result)))))

    (testing "player doesn't have the card"
      (let [result (validation/validate-play base-state 1 [(make-card :spades "K")])]
        (is (not (:valid? result)))
        (is (= "You don't have those cards" (:reason result)))))

    (testing "penalty scenario - must block or accept"
      (let [state (-> base-state
                      (assoc :effects [{:type :penalty :penalty-type :two}])
                      (assoc-in [:players 0 :hand] [(make-card :hearts "5")]))]
        (let [result (validation/validate-play state 1 [(make-card :hearts "5")])]
          (is (not (:valid? result)))
          (is (= "Must block penalty with matching card or Ace" (:reason result))))))))
