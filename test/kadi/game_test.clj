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
  (-> (game/new-game "TEST")
      (#(:ok (game/join-player % {:id 1 :name "Alice"})))
      (#(:ok (game/join-player % {:id 2 :name "Bob"})))
      (game/start-game {})))

(defn make-3p-test-game
  "Create a game with three players for testing."
  []
  (-> (game/new-game "TEST3")
      (#(:ok (game/join-player % {:id 1 :name "Alice"})))
      (#(:ok (game/join-player % {:id 2 :name "Bob"})))
      (#(:ok (game/join-player % {:id 3 :name "Charlie"})))
      (game/start-game {})))

(defn give-card
  "Give a specific card to a player (for testing)."
  [state player-id card]
  (game/update-hand state player-id #(conj % card)))

(defn set-top-card
  "Set the top card of the played stack (for testing)."
  [state card]
  (assoc-in state [:zones :played-stack] [card]))

(defn clear-hand
  "Clear a player's hand (for testing cardless scenarios)."
  [state player-id]
  (game/set-hand state player-id []))

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
  (let [game (game/new-game "TEST")]
    (is (= "TEST" (:short-code game)))
    (is (= :lobby (:status game)))
    (is (empty? (:players game)))
    (is (= :clockwise (get-in game [:turn :direction])))))

(deftest player-management
  (testing "adding players"
    (let [game (-> (game/new-game "TEST")
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
      (is (= 4 (count (game/get-hand game (:id (get-in game [:players 0]))))))
      (is (= 1 (count (get-in game [:zones :played-stack]))))
      (is (pos? (count (get-in game [:zones :deck]))))))

  (testing "each player has 4 cards after start"
    (let [game (make-test-game)
          players (:players game)]
      (doseq [player players]
        (let [hand (game/get-hand game (:id player))]
          (is (= 4 (count hand))
              (str "Player " (:name player) " should have 4 cards"))))))

  (testing "cannot start with less than 2 players"
    (let [game (-> (game/new-game "TEST")
                   (game/add-player {:id 1 :name "Alice"})
                   (game/start-game {}))]
      (is (= :lobby (:status game))))))

;; =============================================================================
;; Turn Management Tests
;; =============================================================================

(deftest turn-advancement
  (testing "turn advances clockwise"
    (let [game (make-test-game)
          next-game (game/advance-turn game)]
      (is (= 1 (game/current-player-index next-game)))))

  (testing "turn wraps around"
    (let [game (assoc (make-test-game) :current-player-index 1)
          next-game (game/advance-turn game)]
      (is (= 0 (game/current-player-index next-game))))))

(deftest direction-reversal
  (testing "king reverses direction"
    (let [game (make-test-game)
          reversed (game/reverse-direction game)]
      (is (= :counter-clockwise (get-in reversed [:turn :direction]))))

    (let [game (-> (make-test-game)
                   (assoc :direction :counter-clockwise))
          reversed (game/reverse-direction game)]
      (is (= :clockwise (get-in reversed [:turn :direction]))))))

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
      (is (some #(= :select-suit (:type %)) (:effects result))))))

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
      (is (= :counter-clockwise (get-in result [:turn :direction]))))))

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
      (is (= 0 (game/current-player-index result))))))

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
      (is (some #(= :penalty (:type %)) (:effects result))
          "penalty effect present")
      (is (= :two (:penalty-type (first (filter #(= :penalty (:type %)) (:effects result)))))))))

;; =============================================================================
;; Command Function Tests
;; =============================================================================

(deftest play-cards-cmd-errors
  (testing "not live game"
    (let [game (-> (game/new-game "TEST")
                   (game/add-player {:id 1 :name "Alice"})
                   (game/add-player {:id 2 :name "Bob"}))]
      (is (:error (game/play-cards-cmd game 1 [{:suit :hearts :rank "5"}])))))

  (testing "not your turn"
    (let [game (make-test-game)
          card {:suit :hearts :rank "5"}
          game (give-card game 2 card)]
      (is (:error (game/play-cards-cmd game 2 [card])))))

  (testing "card doesn't match"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"}))
          card {:suit :clubs :rank "9"}
          game (give-card game 1 card)]
      (is (:error (game/play-cards-cmd game 1 [card]))))))

(deftest draw-card-cmd-test
  (testing "successful draw"
    (let [game (make-test-game)
          result (game/draw-card-cmd game (game/current-player-id game))]
      (is (:ok result))
      (is (= 5 (count (game/get-hand (:ok result) (game/current-player-id game)))))))

  (testing "not your turn"
    (let [game (make-test-game)
          other-id (:id (second (:players game)))]
      (is (:error (game/draw-card-cmd game other-id))))))

(deftest select-suit-cmd-test
  (testing "successful suit selection"
    (let [game (-> (make-test-game)
                   (update :effects conj {:type :select-suit}))
          result (game/select-suit-cmd game :hearts)]
      (is (:ok result))
      (is (not (game/has-effect? (:ok result) :select-suit)))
      (is (game/has-effect? (:ok result) :suit-selected))))

  (testing "invalid suit"
    (let [game (-> (make-test-game)
                   (update :effects conj {:type :select-suit}))]
      (is (:error (game/select-suit-cmd game :invalid)))))

  (testing "no effect active"
    (let [game (make-test-game)]
      (is (:error (game/select-suit-cmd game :hearts))))))

(deftest accept-penalty-cmd-test
  (testing "successful accept draw-2"
    (let [game (-> (make-test-game)
                   (update :effects conj {:type :penalty :penalty-type :two}))
          player-id (game/current-player-id game)
          hand-before (count (game/get-hand game player-id))
          result (game/accept-penalty-cmd game player-id)]
      (is (:ok result))
      (is (= (+ hand-before 2) (count (game/get-hand (:ok result) player-id))))
      (is (not (game/has-effect? (:ok result) :penalty)))))

  (testing "successful accept draw-3"
    (let [game (-> (make-test-game)
                   (update :effects conj {:type :penalty :penalty-type :three}))
          player-id (game/current-player-id game)
          hand-before (count (game/get-hand game player-id))
          result (game/accept-penalty-cmd game player-id)]
      (is (:ok result))
      (is (= (+ hand-before 3) (count (game/get-hand (:ok result) player-id))))))

  (testing "no penalty active"
    (let [game (make-test-game)]
      (is (:error (game/accept-penalty-cmd game (game/current-player-id game)))))))

(deftest answer-question-cmd-test
  (testing "successful answer"
    (let [game (-> (make-test-game)
                   (update :effects conj {:type :awaiting-answer}))
          player-id (game/current-player-id game)
          hand-before (count (game/get-hand game player-id))
          result (game/answer-question-cmd game player-id)]
      (is (:ok result))
      (is (= (+ hand-before 1) (count (game/get-hand (:ok result) player-id))))
      (is (not (game/has-effect? (:ok result) :awaiting-answer)))))

  (testing "no awaiting answer"
    (let [game (make-test-game)]
      (is (:error (game/answer-question-cmd game (game/current-player-id game)))))))

;; =============================================================================
;; Game Mechanics Tests
;; =============================================================================

(deftest penalty-3-creation
  (testing "playing 3 creates draw-3 penalty"
    (let [top {:suit :hearts :rank "5"}
          three {:suit :hearts :rank "3"}
          game (-> (make-test-game)
                   (set-top-card top)
                   (give-card 1 three))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [three]})]
      (is (not (:error result)))
      (is (some #(= :penalty (:type %)) (:effects result)))
      (is (= :three (:penalty-type (first (filter #(= :penalty (:type %)) (:effects result)))))))))

(deftest penalty-blocking
  (testing "2 blocks 2 penalty"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "2"})
                   (update :effects conj {:type :penalty :penalty-type :two})
                   (give-card 1 {:suit :clubs :rank "2"}))
          result (game/play-cards-cmd game 1 [{:suit :clubs :rank "2"}])]
      (is (:ok result))
      ;; Should still have a penalty effect (new one stacked)
      (is (some #(= :penalty (:type %)) (:effects (:ok result))))))

  (testing "3 blocks 3 penalty"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "3"})
                   (update :effects conj {:type :penalty :penalty-type :three})
                   (give-card 1 {:suit :clubs :rank "3"}))
          result (game/play-cards-cmd game 1 [{:suit :clubs :rank "3"}])]
      (is (:ok result))))

  (testing "Ace blocks any penalty"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "2"})
                   (update :effects conj {:type :penalty :penalty-type :two})
                   (give-card 1 {:suit :clubs :rank "A"}))
          result (game/play-cards-cmd game 1 [{:suit :clubs :rank "A"}])]
      (is (:ok result))))

  (testing "cross-blocking prevented: 2 cannot block 3 penalty"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "3"})
                   (update :effects conj {:type :penalty :penalty-type :three})
                   (give-card 1 {:suit :hearts :rank "2"}))
          result (game/play-cards-cmd game 1 [{:suit :hearts :rank "2"}])]
      (is (:error result)))))

(deftest multi-card-combos
  (testing "same rank combo valid"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (give-card 1 {:suit :hearts :rank "5"})
                   (give-card 1 {:suit :clubs :rank "5"}))
          result (game/play-cards-cmd game 1
                                      [{:suit :hearts :rank "5"} {:suit :clubs :rank "5"}])]
      (is (:ok result))))

  (testing "king combo rejected"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (give-card 1 {:suit :hearts :rank "K"})
                   (give-card 1 {:suit :clubs :rank "K"}))
          result (game/play-cards-cmd game 1
                                      [{:suit :hearts :rank "K"} {:suit :clubs :rank "K"}])]
      (is (:error result)))))

(deftest cardless-state
  (testing "K as last card triggers cardless"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (clear-hand 1)
                   (give-card 1 {:suit :hearts :rank "K"}))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [{:suit :hearts :rank "K"}]})]
      (is (= :cardless (:status (game/get-player result 1))))))

  (testing "J as last card triggers cardless"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (clear-hand 1)
                   (give-card 1 {:suit :hearts :rank "J"}))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [{:suit :hearts :rank "J"}]})]
      (is (= :cardless (:status (game/get-player result 1))))))

  (testing "2 as last card triggers cardless"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (clear-hand 1)
                   (give-card 1 {:suit :hearts :rank "2"}))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [{:suit :hearts :rank "2"}]})]
      (is (= :cardless (:status (game/get-player result 1))))))

  (testing "regular card as last does not trigger cardless"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (clear-hand 1)
                   (give-card 1 {:suit :hearts :rank "9"}))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [{:suit :hearts :rank "9"}]})]
      (is (= :normal (:status (game/get-player result 1))))))

  (testing "A as last card does not trigger cardless"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (clear-hand 1)
                   (give-card 1 {:suit :clubs :rank "A"}))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [{:suit :clubs :rank "A"}]})]
      (is (= :normal (:status (game/get-player result 1)))))))

(deftest deck-recycling
  (testing "recycling moves played stack (minus top) back to deck"
    (let [game (-> (make-test-game)
                   (assoc-in [:zones :deck] [])
                   (assoc-in [:zones :played-stack]
                             [{:suit :hearts :rank "5"}
                              {:suit :clubs :rank "6"}
                              {:suit :diamonds :rank "7"}]))
          recycled (game/recycle-played-stack game)]
      ;; Top card stays on played stack
      (is (= [{:suit :diamonds :rank "7"}] (get-in recycled [:zones :played-stack])))
      ;; Other cards go to deck
      (is (= 2 (count (get-in recycled [:zones :deck]))))))

  (testing "single card in played stack is no-op"
    (let [game (-> (make-test-game)
                   (assoc-in [:zones :played-stack] [{:suit :hearts :rank "5"}]))
          recycled (game/recycle-played-stack game)]
      (is (= game recycled)))))

(deftest three-player-jack-skip
  (testing "jack skips one player in 3-player game"
    (let [top {:suit :hearts :rank "5"}
          jack {:suit :hearts :rank "J"}
          game (-> (make-3p-test-game)
                   (set-top-card top)
                   (give-card 1 jack))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [jack]})]
      ;; Player 1 (idx 0) plays, skip player 2 (idx 1), go to player 3 (idx 2)
      (is (= 2 (game/current-player-index result))))))

(deftest three-player-direction-reversal
  (testing "king reverses direction in 3-player game"
    (let [top {:suit :hearts :rank "5"}
          king {:suit :hearts :rank "K"}
          game (-> (make-3p-test-game)
                   (set-top-card top)
                   (give-card 1 king))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [king]})]
      (is (= :counter-clockwise (get-in result [:turn :direction])))
      ;; After reversal from idx 0, next is idx 2 (wraps counter-clockwise)
      (is (= 2 (game/current-player-index result))))))

;; =============================================================================
;; Event Replay Tests
;; =============================================================================

(deftest event-replay-play-cards
  (testing "apply-action :play-cards replays correctly"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (give-card 1 {:suit :hearts :rank "9"}))
          result (game/apply-action game {:type :play-cards
                                          :player-id 1
                                          :cards [{:suit :hearts :rank "9"}]})]
      (is (= {:suit :hearts :rank "9"} (game/top-card result))))))

(deftest event-replay-draw-card
  (testing "apply-action :draw-card replays correctly"
    (let [game (make-test-game)
          player-id (game/current-player-id game)
          hand-before (count (game/get-hand game player-id))
          result (game/apply-action game {:type :draw-card
                                          :player-id player-id})]
      (is (= (inc hand-before) (count (game/get-hand result player-id)))))))

(deftest event-replay-select-suit
  (testing "apply-action :select-suit replays correctly"
    (let [game (-> (make-test-game)
                   (update :effects conj {:type :select-suit}))
          result (game/apply-action game {:type :select-suit :suit :hearts})]
      (is (not (game/has-effect? result :select-suit)))
      (is (game/has-effect? result :suit-selected)))))

(deftest event-replay-accept-penalty
  (testing "apply-action :accept-penalty replays correctly"
    (let [game (-> (make-test-game)
                   (update :effects conj {:type :penalty :penalty-type :two}))
          player-id (game/current-player-id game)
          hand-before (count (game/get-hand game player-id))
          result (game/apply-action game {:type :accept-penalty
                                          :player-id player-id})]
      (is (= (+ hand-before 2) (count (game/get-hand result player-id))))
      (is (not (game/has-effect? result :penalty))))))

(deftest event-replay-answer-question
  (testing "apply-action :answer-question replays correctly"
    (let [game (-> (make-test-game)
                   (update :effects conj {:type :awaiting-answer}))
          player-id (game/current-player-id game)
          hand-before (count (game/get-hand game player-id))
          result (game/apply-action game {:type :answer-question
                                          :player-id player-id})]
      (is (= (inc hand-before) (count (game/get-hand result player-id))))
      (is (not (game/has-effect? result :awaiting-answer))))))

;; =============================================================================
;; Backward Compatibility Alias Tests
;; =============================================================================

(deftest backward-compat-cards-played
  (testing ":cards-played delegates to :play-cards"
    (let [game (-> (make-test-game)
                   (set-top-card {:suit :hearts :rank "5"})
                   (give-card 1 {:suit :hearts :rank "9"}))
          result (game/apply-action game {:type :cards-played
                                          :player-id 1
                                          :cards [{:suit :hearts :rank "9"}]})]
      (is (= {:suit :hearts :rank "9"} (game/top-card result))))))

(deftest backward-compat-card-drawn
  (testing ":card-drawn delegates to :draw-card"
    (let [game (make-test-game)
          player-id (game/current-player-id game)
          hand-before (count (game/get-hand game player-id))
          result (game/apply-action game {:type :card-drawn
                                          :player-id player-id})]
      (is (= (inc hand-before) (count (game/get-hand result player-id)))))))
