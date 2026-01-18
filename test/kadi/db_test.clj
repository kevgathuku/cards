(ns kadi.db-test
  (:require [clojure.test :refer [deftest is testing use-fixtures]]
            [kadi.db :as db]
            [kadi.game :as game]
            [next.jdbc :as jdbc]))

;; Use a test database file that gets cleaned up
(def test-db-file "test-kadi.db")

;; Helper to normalize status to string for consistent comparison
(defn- normalize-status [status]
  (cond
    (keyword? status) (name status)
    (string? status) status
    :else nil))

(defn with-test-db [f]
  ;; Delete test db if it exists
  (let [file (java.io.File. test-db-file)]
    (when (.exists file)
      (.delete file)))
  
  ;; Override to use test database and reset datasource
  (with-redefs [db/db-spec {:dbtype "sqlite" :dbname test-db-file}]
    ;; Reset the datasource atom to force new connection
    (reset! @#'db/ds nil)
    (db/init!)
    (try
      (f)
      (finally
        ;; Clean up
        (reset! @#'db/ds nil)
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
  (testing "When state is stale (state_sequence < latest event)"
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
            "State sequence should be 2 (game-created + join-game)"))))
  
  (testing "When state is fresh (state_sequence matches latest event)"
    (let [action {:player {:id 1 :name "Alice"}}
          result (db/create-game! action)
          short-code (:short-code result)]
      
      ;; Get game without adding new events
      (let [game1 (db/get-game-by-code short-code)
            initial-seq (:state_sequence game1)]
        (is (= 1 initial-seq) "Should have sequence 1")
        
        ;; Get again - should not rebuild since state is fresh
        (let [game2 (db/get-game-by-code short-code)]
          (is (= initial-seq (:state_sequence game2))
              "State sequence should not change when fresh")
          (is (= "lobby" (normalize-status (get-in game2 [:state :status])))
              "Status should be lobby")
          (is (= (count (get-in game1 [:state :players]))
                 (count (get-in game2 [:state :players])))
              "Player count should be identical when fresh"))))))
  
  (testing "When state_sequence is 0 (initial state, no events applied)"
    (let [action {:player {:id 1 :name "Alice"}}
          result (db/create-game! action)
          game-id (:id result)
          short-code (:short-code result)]
      
      ;; Manually set state_sequence to 0 (simulating stale state)
      (jdbc/execute-one! (db/datasource)
                         ["UPDATE games SET state_sequence = 0 WHERE id = ?" game-id])
      
      ;; Get game - should rebuild from events since sequence is behind
      (let [game (db/get-game-by-code short-code)]
        (is (some? (:state_sequence game)) "Should have rebuilt state_sequence")
        (is (= 1 (:state_sequence game)) "Should match event count")
        (is (= "lobby" (normalize-status (get-in game [:state :status])))
            "Should have lobby status"))))
  
  (testing "When game is nil"
    (let [result (#'db/ensure-fresh-state nil)]
      (is (nil? result) "Should return nil when input is nil")))
  
  (testing "After multiple events, state should reflect all changes"
    (let [action {:player {:id 1 :name "Alice"}}
          result (db/create-game! action)
          game-id (:id result)
          short-code (:short-code result)]
      
      ;; Add multiple events
      (db/append-event! game-id :join-game {:player {:id 2 :name "Bob"}})
      (db/append-event! game-id :join-game {:player {:id 3 :name "Charlie"}})
      (db/append-event! game-id :start-game {})
      
      ;; Get game - should have all events applied
      (let [game (db/get-game-by-code short-code)]
        (is (= 4 (:state_sequence game))
            "Should have sequence 4 (create + 3 events)")
        (is (= 3 (count (get-in game [:state :players])))
            "Should have 3 players")
        (is (= "live" (normalize-status (get-in game [:state :status])))
            "Game should be live after start-game"))))

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
    (let [action {:player {:id 1 :name "Alice"} :short-code "CUSTOM1"}
          result (db/create-game! action)]
      (is (= "CUSTOM1" (:short-code result)) "Should use custom short-code")))
  
  (testing "Creating multiple games with different custom short-codes"
    ;; Use unique codes with timestamp to avoid collisions
    (let [timestamp (System/currentTimeMillis)
          code1 (str "GA" timestamp)
          code2 (str "GB" timestamp)
          action1 {:player {:id 1 :name "Alice"} :short-code code1}
          result1 (db/create-game! action1)
          action2 {:player {:id 2 :name "Bob"} :short-code code2}
          result2 (db/create-game! action2)]
      (is (= code1 (:short-code result1)) "First game should have first code")
      (is (= code2 (:short-code result2)) "Second game should have second code")
      (is (not= (:id result1) (:id result2)) "Games should have different IDs"))))
