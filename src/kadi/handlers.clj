(ns kadi.handlers
  "HTTP request handlers."
  (:require [kadi.db :as db]
            [kadi.game :as game]
            [jsonista.core :as json]))

(def ^:private json-mapper (json/object-mapper {:decode-key-fn keyword}))

(defn- json-response [status body]
  {:status status
   :headers {"Content-Type" "application/json"}
   :body (json/write-value-as-string body json-mapper)})

(defn- parse-body [request]
  (when-let [body (:body request)]
    (json/read-value (slurp body) json-mapper)))

(defn- generate-short-code []
  (let [chars "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"]
    (apply str (repeatedly 6 #(rand-nth chars)))))

;; =============================================================================
;; Page Handlers
;; =============================================================================

(defn index [_request]
  {:status 200
   :headers {"Content-Type" "text/html"}
   :body "<html>
            <head><title>Kadi</title></head>
            <body>
              <h1>Kadi Card Game</h1>
              <p>API available at /api</p>
            </body>
          </html>"})

;; =============================================================================
;; Game Handlers
;; =============================================================================

(defn list-games [_request]
  (let [games (db/list-games :lobby)]
    (json-response 200 {:games (map #(select-keys % [:id :short_code :status :created_at]) games)})))

(defn create-game [_request]
  (let [short-code (generate-short-code)
        game-state (game/new-game {:id nil :short-code short-code})
        result (db/create-game! game-state)
        game-id (:id result)]
    (db/append-event! game-id :game-created {})
    (json-response 201 {:id game-id :short-code short-code})))

(defn get-game [request]
  (let [game-id (parse-long (get-in request [:path-params :id]))]
    (if-let [game (db/get-game game-id)]
      (json-response 200 game)
      (json-response 404 {:error "Game not found"}))))

(defn join-game [request]
  (let [game-id (parse-long (get-in request [:path-params :id]))
        body (parse-body request)
        player-id (:player-id body)
        player-name (:player-name body)]
    (if-let [game (db/get-game game-id)]
      (let [new-state (game/apply-action (:state game)
                                         {:type :join-game
                                          :player-id player-id
                                          :player-name player-name})]
        (if (:error new-state)
          (json-response 400 {:error (:error new-state)})
          (do
            (db/update-game! game-id new-state)
            (db/append-event! game-id :player-joined {:player-id player-id :player-name player-name})
            (json-response 200 {:status "joined"}))))
      (json-response 404 {:error "Game not found"}))))

(defn start-game [request]
  (let [game-id (parse-long (get-in request [:path-params :id]))]
    (if-let [game (db/get-game game-id)]
      (let [new-state (game/apply-action (:state game) {:type :start-game})]
        (if (:error new-state)
          (json-response 400 {:error (:error new-state)})
          (do
            (db/update-game! game-id new-state)
            (db/append-event! game-id :game-started {})
            (json-response 200 {:status "started"}))))
      (json-response 404 {:error "Game not found"}))))

(defn game-action [request]
  (let [game-id (parse-long (get-in request [:path-params :id]))
        action (parse-body request)]
    (if-let [game (db/get-game game-id)]
      (let [new-state (game/apply-action (:state game) action)]
        (if (:error new-state)
          (json-response 400 {:error (:error new-state)})
          (do
            (db/update-game! game-id new-state)
            (db/append-event! game-id (keyword (:type action)) action)
            (json-response 200 {:status "ok" :state new-state}))))
      (json-response 404 {:error "Game not found"}))))

;; =============================================================================
;; Player Handlers
;; =============================================================================

(defn create-player [request]
  (let [body (parse-body request)
        result (db/create-player! body)]
    (json-response 201 {:id (:id result)})))

(defn get-player [request]
  (let [player-id (parse-long (get-in request [:path-params :id]))]
    (if-let [player (db/get-player player-id)]
      (json-response 200 (dissoc player :password_hash))
      (json-response 404 {:error "Player not found"}))))
