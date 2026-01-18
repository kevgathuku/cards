(ns kadi.db-test
  (:require [clojure.test :refer [deftest is testing use-fixtures]]
            [kadi.db :as db]
            [kadi.game :as game]
            [next.jdbc :as jdbc]))

;; Use a test database file that gets cleaned up
(def test-db-file "test-kadi.db")

(defn with-test-db [f]
  ;; Delete test db if it exists
  (let [file (java.io.File. test-db-file)]
    (when (.exists file)
      (.delete file)))
  
  ;; Override to use test database
  (with-redefs [db/db-spec {:dbtype "sqlite" :dbname test-db-file}]
    (db/init!)
    (try
      (f)
      (finally
        ;; Clean up
        (let [file (java.io.File. test-db-file)]
          (when (.exists file)
            (.delete file)))))))

(use-fixtures :each with-test-db)

(deftest rebuild-state-from-events-test
  (testing "Rebuilding state from game-created event"
    (let [action {:player {:id 1 :name "Alice"}}
          result (db/create-game! action)
          game-id (:id result)]
      
      (testing "should create initial game state"
        (let [state (db/rebuild-state-from-events game-id)]
          (is (some? state) "State should not be nil")
          (is (= :lobby (:status state)) "Game should be in lobby status")
          (is (= 1 (count (:players state))) "Should have 1 player")
          (is (= "Alice" (-> state :players first :name)) "Player name should be Alice")
          (is (some? (:short-code state)) "Should have a short-code")))
      
      (testing "should match the state returned by create-game! (excluding timestamps)"
        (let [rebuilt-state (db/rebuild-state-from-events game-id)
              created-state (:state result)]
          (is (= (dissoc rebuilt-state :meta) (dissoc created-state :meta))
              "Rebuilt state should match initially created state (excluding meta)"))))))

  (testing "Rebuilding state with multiple events"
    (let [action {:player {:id 1 :name "Alice"}}
          result (db/create-game! action)
          game-id (:id result)]
      
      ;; Join another player
      (db/append-event! game-id :join-game {:player {:id 2 :name "Bob"}})
      
      (let [state (db/rebuild-state-from-events game-id)]
        (is (= 2 (count (:players state))) "Should have 2 players")
        (is (= "Bob" (-> state :players second :name)) "Second player should be Bob"))
      
      ;; Start the game
      (db/append-event! game-id :start-game {})
      
      (let [state (db/rebuild-state-from-events game-id)]
        (is (= :live (:status state)) "Game should be live after start-game event")
        (is (seq (get-in state [:zones :deck])) "Deck should have cards")
        (is (seq (get-in state [:zones :played-stack])) "Played stack should have starting card")
        (is (= 4 (count (game/get-hand state 1))) "Player 1 should have 4 cards")
        (is (= 4 (count (game/get-hand state 2))) "Player 2 should have 4 cards"))))


(deftest ensure-fresh-state-test
  (testing "Ensuring fresh state when stale"
    (let [action {:player {:id 1 :name "Alice"}}
          result (db/create-game! action)
          game-id (:id result)
          short-code (:short-code result)]
      
      ;; Add an event after game creation
      (db/append-event! game-id :join-game {:player {:id 2 :name "Bob"}})
      
      ;; Get game - should detect stale state and rebuild
      (let [game (db/get-game-by-code short-code)]
        (is (= 2 (count (get-in game [:state :players])))
            "Should have 2 players after ensuring fresh state")
        (is (= 2 (:state_sequence game))
            "State sequence should be 2 (game-created + join-game)")))))

(deftest create-game-test
  (testing "Creating a game with default short-code"
    (let [action {:player {:id 1 :name "Alice"}}
          result (db/create-game! action)]
      (is (some? (:id result)) "Should have game ID")
      (is (some? (:short-code result)) "Should have generated short-code")
      (is (= 6 (count (:short-code result))) "Short-code should be 6 characters")
      (is (some? (:state result)) "Should have state")
      (is (= 1 (:state_sequence result)) "Should have sequence 1")))
  
  (testing "Creating a game with custom short-code"
    (let [action {:player {:id 1 :name "Alice"} :short-code "CUSTOM"}
          result (db/create-game! action)]
      (is (= "CUSTOM" (:short-code result)) "Should use custom short-code"))))
