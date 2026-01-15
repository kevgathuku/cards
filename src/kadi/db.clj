(ns kadi.db
  "SQLite database operations."
  (:require [next.jdbc :as jdbc]
            [next.jdbc.result-set :as rs]
            [jsonista.core :as json]))

(def db-spec {:dbtype "sqlite" :dbname "kadi.db"})

(def ^:private ds (atom nil))

(defn datasource []
  (or @ds
      (reset! ds (jdbc/get-datasource db-spec))))

(def ^:private json-mapper (json/object-mapper {:decode-key-fn keyword}))

(defn ->json [data]
  (json/write-value-as-string data json-mapper))

(defn <-json [s]
  (when s
    (json/read-value s json-mapper)))

;; =============================================================================
;; Schema
;; =============================================================================

(def schema
  "CREATE TABLE IF NOT EXISTS games (
     id INTEGER PRIMARY KEY,
     short_code TEXT UNIQUE NOT NULL,
     status TEXT NOT NULL DEFAULT 'lobby',
     state TEXT NOT NULL,
     created_at TEXT NOT NULL DEFAULT (datetime('now')),
     updated_at TEXT NOT NULL DEFAULT (datetime('now'))
   );

   CREATE TABLE IF NOT EXISTS players (
     id INTEGER PRIMARY KEY,
     name TEXT NOT NULL,
     email TEXT UNIQUE,
     password_hash TEXT,
     created_at TEXT NOT NULL DEFAULT (datetime('now'))
   );

   CREATE TABLE IF NOT EXISTS game_players (
     id INTEGER PRIMARY KEY,
     game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
     player_id INTEGER NOT NULL REFERENCES players(id),
     joined_at TEXT NOT NULL DEFAULT (datetime('now')),
     status TEXT NOT NULL DEFAULT 'normal',
     UNIQUE(game_id, player_id)
   );

   CREATE TABLE IF NOT EXISTS game_events (
     id INTEGER PRIMARY KEY,
     game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
     sequence_number INTEGER NOT NULL,
     event_type TEXT NOT NULL,
     event_data TEXT NOT NULL,
     created_at TEXT NOT NULL DEFAULT (datetime('now')),
     UNIQUE(game_id, sequence_number)
   );

   CREATE INDEX IF NOT EXISTS idx_games_short_code ON games(short_code);
   CREATE INDEX IF NOT EXISTS idx_game_events_game_id ON game_events(game_id);
   CREATE INDEX IF NOT EXISTS idx_game_players_game_id ON game_players(game_id);")

(defn init!
  "Initialize the database with schema and pragmas."
  []
  (let [ds (datasource)]
    ;; Enable foreign keys and WAL mode
    (jdbc/execute! ds ["PRAGMA foreign_keys=ON"])
    (jdbc/execute! ds ["PRAGMA journal_mode=WAL"])
    ;; Create tables
    (doseq [stmt (clojure.string/split schema #";")]
      (when (not (clojure.string/blank? stmt))
        (jdbc/execute! ds [(clojure.string/trim stmt)])))))

;; =============================================================================
;; Game Operations
;; =============================================================================

(defn create-game!
  "Create a new game and return it."
  [game-state]
  (let [ds (datasource)]
    (jdbc/execute-one! ds
                       ["INSERT INTO games (short_code, status, state) VALUES (?, ?, ?)"
                        (:short-code game-state)
                        (name (:status game-state))
                        (->json game-state)]
                       {:return-keys true
                        :builder-fn rs/as-unqualified-lower-maps})))

(defn get-game
  "Get a game by ID."
  [game-id]
  (when-let [row (jdbc/execute-one! (datasource)
                                    ["SELECT * FROM games WHERE id = ?" game-id]
                                    {:builder-fn rs/as-unqualified-lower-maps})]
    (update row :state <-json)))

(defn get-game-by-code
  "Get a game by short code."
  [short-code]
  (when-let [row (jdbc/execute-one! (datasource)
                                    ["SELECT * FROM games WHERE short_code = ?" short-code]
                                    {:builder-fn rs/as-unqualified-lower-maps})]
    (update row :state <-json)))

(defn update-game!
  "Update game state."
  [game-id game-state]
  (jdbc/execute-one! (datasource)
                     ["UPDATE games SET state = ?, status = ?, updated_at = datetime('now') WHERE id = ?"
                      (->json game-state)
                      (name (:status game-state))
                      game-id]))

(defn list-games
  "List all games, optionally filtered by status."
  ([] (list-games nil))
  ([status]
   (let [query (if status
                 ["SELECT * FROM games WHERE status = ? ORDER BY created_at DESC" (name status)]
                 ["SELECT * FROM games ORDER BY created_at DESC"])]
     (->> (jdbc/execute! (datasource) query {:builder-fn rs/as-unqualified-lower-maps})
          (map #(update % :state <-json))))))

;; =============================================================================
;; Event Sourcing
;; =============================================================================

(defn append-event!
  "Append an event to a game's event log."
  [game-id event-type event-data]
  (let [ds (datasource)
        next-seq (or (:seq (jdbc/execute-one! ds
                                              ["SELECT MAX(sequence_number) + 1 as seq FROM game_events WHERE game_id = ?" game-id]
                                              {:builder-fn rs/as-unqualified-lower-maps}))
                     1)]
    (jdbc/execute-one! ds
                       ["INSERT INTO game_events (game_id, sequence_number, event_type, event_data) VALUES (?, ?, ?, ?)"
                        game-id next-seq (name event-type) (->json event-data)]
                       {:return-keys true
                        :builder-fn rs/as-unqualified-lower-maps})))

(defn get-events
  "Get all events for a game."
  [game-id]
  (->> (jdbc/execute! (datasource)
                      ["SELECT * FROM game_events WHERE game_id = ? ORDER BY sequence_number" game-id]
                      {:builder-fn rs/as-unqualified-lower-maps})
       (map #(update % :event_data <-json))))

;; =============================================================================
;; Player Operations
;; =============================================================================

(defn create-player!
  "Create a new player."
  [{:keys [name email password-hash]}]
  (jdbc/execute-one! (datasource)
                     ["INSERT INTO players (name, email, password_hash) VALUES (?, ?, ?)"
                      name email password-hash]
                     {:return-keys true
                      :builder-fn rs/as-unqualified-lower-maps}))

(defn get-player
  "Get a player by ID."
  [player-id]
  (jdbc/execute-one! (datasource)
                     ["SELECT * FROM players WHERE id = ?" player-id]
                     {:builder-fn rs/as-unqualified-lower-maps}))

(defn get-player-by-email
  "Get a player by email."
  [email]
  (jdbc/execute-one! (datasource)
                     ["SELECT * FROM players WHERE email = ?" email]
                     {:builder-fn rs/as-unqualified-lower-maps}))
