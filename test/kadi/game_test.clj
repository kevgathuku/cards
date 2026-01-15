(ns kadi.game-test
  (:require [clojure.test :refer [deftest testing is]]
            [kadi.game :as game]
            [kadi.cards :as cards]))

;; =============================================================================
;; Test Helpers
;; =============================================================================

(defn make-test-game
  "Create a game with two players for testing."
  []
  (-> (game/new-game {:id 1 :short-code "TEST01" :created-by 1})
      (game/add-player {:id 1 :name "Alice"})
      (game/add-player {:id 2 :name "Bob"})
      (game/start-game {})))

(defn give-card
  "Give a specific card to a player (for testing)."
  [state player-id card]
  (game/update-player state player-id #(update % :hand conj card)))

(defn set-top-card
  "Set the top card of the played stack (for testing)."
  [state card]
  (update state :played-stack #(conj (vec (butlast %)) card)))

;; =============================================================================
;; Card Tests
;; =============================================================================

(deftest card-predicates
  (testing "ace detection"
    (is (cards/ace? {:suit :hearts :rank "A"}))
    (is (not (cards/ace? {:suit :hearts :rank "K"}))))

  (testing "question card detection"
    (is (cards/question-card? {:suit :hearts :rank "Q"}))
    (is (cards/question-card? {:suit :clubs :rank "8"}))
    (is (not (cards/question-card? {:suit :hearts :rank "K"}))))

  (testing "penalty card detection"
    (is (cards/penalty-card? {:suit :hearts :rank "2"}))
    (is (cards/penalty-card? {:suit :clubs :rank "3"}))
    (is (not (cards/penalty-card? {:suit :hearts :rank "4"})))))

(deftest card-matching
  (testing "suit matching"
    (is (cards/matches-suit? {:suit :hearts :rank "5"}
                             {:suit :hearts :rank "K"}))
    (is (not (cards/matches-suit? {:suit :hearts :rank "5"}
                                  {:suit :clubs :rank "5"}))))

  (testing "rank matching"
    (is (cards/matches-rank? {:suit :hearts :rank "5"}
                             {:suit :clubs :rank "5"}))
    (is (not (cards/matches-rank? {:suit :hearts :rank "5"}
                                  {:suit :hearts :rank "6"})))))

;; =============================================================================
;; Game State Tests
;; =============================================================================

(deftest new-game-creation
  (let [game (game/new-game {:id 1 :short-code "ABC123" :created-by 1})]
    (is (= :lobby (:status game)))
    (is (= "ABC123" (:short-code game)))
    (is (empty? (:players game)))
    (is (= :clockwise (:direction game)))))

(deftest player-management
  (testing "adding players"
    (let [game (-> (game/new-game {:id 1 :short-code "TEST" :created-by 1})
                   (game/add-player {:id 1 :name "Alice"})
                   (game/add-player {:id 2 :name "Bob"}))]
      (is (= 2 (count (:players game))))
      (is (= "Alice" (get-in game [:players 0 :name])))))

  (testing "cannot add players after game starts"
    (let [game (make-test-game)
          result (game/add-player game {:id 3 :name "Charlie"})]
      (is (:error result)))))

(deftest game-start
  (testing "game starts with correct state"
    (let [game (make-test-game)]
      (is (= :live (:status game)))
      (is (= 4 (count (get-in game [:players 0 :hand]))))
      (is (= 1 (count (:played-stack game))))
      (is (pos? (count (:deck game))))))

  (testing "cannot start with less than 2 players"
    (let [game (-> (game/new-game {:id 1 :short-code "TEST" :created-by 1})
                   (game/add-player {:id 1 :name "Alice"})
                   (game/start-game {}))]
      (is (:error game)))))

;; =============================================================================
;; Turn Management Tests
;; =============================================================================

(deftest turn-advancement
  (testing "turn advances clockwise"
    (let [game (make-test-game)
          next-game (game/advance-turn game)]
      (is (= 1 (:current-player-index next-game)))))

  (testing "turn wraps around"
    (let [game (-> (make-test-game)
                   (assoc :current-player-index 1))
          next-game (game/advance-turn game)]
      (is (= 0 (:current-player-index next-game))))))

(deftest direction-reversal
  (testing "king reverses direction"
    (let [game (make-test-game)
          reversed (game/reverse-direction game)]
      (is (= :counter-clockwise (:direction reversed))))

    (let [game (-> (make-test-game)
                   (assoc :direction :counter-clockwise))
          reversed (game/reverse-direction game)]
      (is (= :clockwise (:direction reversed))))))

;; =============================================================================
;; Card Play Tests
;; =============================================================================

(deftest play-matching-card
  (testing "can play card matching by suit"
    (let [top {:suit :hearts :rank "5"}
          card {:suit :hearts :rank "9"}
          game (-> (make-test-game)
                   (set-top-card top)
                   (give-card 1 card))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [card]})]
      (is (not (:error result)))
      (is (= card (game/top-card result)))))

  (testing "can play card matching by rank"
    (let [top {:suit :hearts :rank "5"}
          card {:suit :clubs :rank "5"}
          game (-> (make-test-game)
                   (set-top-card top)
                   (give-card 1 card))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [card]})]
      (is (not (:error result))))))

(deftest ace-always-playable
  (testing "ace can be played on any card"
    (let [top {:suit :hearts :rank "5"}
          ace {:suit :clubs :rank "A"}
          game (-> (make-test-game)
                   (set-top-card top)
                   (give-card 1 ace))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [ace]})]
      (is (not (:error result)))
      (is (= :select-suit (get-in result [:action :type]))))))

(deftest king-reverses-direction
  (testing "playing king reverses game direction"
    (let [top {:suit :hearts :rank "5"}
          king {:suit :hearts :rank "K"}
          game (-> (make-test-game)
                   (set-top-card top)
                   (give-card 1 king))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [king]})]
      (is (not (:error result)))
      (is (= :counter-clockwise (:direction result))))))

(deftest jack-skips-player
  (testing "playing jack skips next player"
    (let [top {:suit :hearts :rank "5"}
          jack {:suit :hearts :rank "J"}
          game (-> (make-test-game)
                   (set-top-card top)
                   (give-card 1 jack))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [jack]})]
      (is (not (:error result)))
      ;; In 2-player game, skip brings back to player 1
      (is (= 0 (:current-player-index result))))))

;; =============================================================================
;; Penalty Tests
;; =============================================================================

(deftest penalty-creation
  (testing "playing 2 creates draw-2 penalty"
    (let [top {:suit :hearts :rank "5"}
          two {:suit :hearts :rank "2"}
          game (-> (make-test-game)
                   (set-top-card top)
                   (give-card 1 two))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [two]})]
      (is (not (:error result)))
      (is (get-in result [:penalty :active]))
      (is (= :two (get-in result [:penalty :type]))))))
