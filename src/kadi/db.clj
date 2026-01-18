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
     state TEXT NOT NULL,
     state_sequence INTEGER NOT NULL DEFAULT 0,
     created_at TEXT NOT NULL DEFAULT (datetime('now')),
     updated_at TEXT NOT NULL DEFAULT (datetime('now'))
   );

   CREATE TABLE IF NOT EXISTS players (
     id INTEGER PRIMARY KEY,
     name TEXT NOT NULL,
     email TEXT UNIQUE NOT NULL,
     created_at TEXT NOT NULL DEFAULT (datetime('now'))
   );

   CREATE TABLE IF NOT EXISTS auth_tokens (
     id INTEGER PRIMARY KEY,
     email TEXT NOT NULL,
     token TEXT NOT NULL UNIQUE,
     expires_at TEXT NOT NULL,
     used INTEGER NOT NULL DEFAULT 0,
     created_at TEXT NOT NULL DEFAULT (datetime('now'))
   );

   CREATE TABLE IF NOT EXISTS game_players (
     id INTEGER PRIMARY KEY,
     game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
     player_id INTEGER NOT NULL REFERENCES players(id),
     joined_at TEXT NOT NULL DEFAULT (datetime('now')),
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
   CREATE INDEX IF NOT EXISTS idx_games_status ON games(json_extract(state, '$.status'));
   CREATE INDEX IF NOT EXISTS idx_game_events_game_id ON game_events(game_id);
   CREATE INDEX IF NOT EXISTS idx_game_players_game_id ON game_players(game_id);
   CREATE INDEX IF NOT EXISTS idx_auth_tokens_token ON auth_tokens(token);
   CREATE INDEX IF NOT EXISTS idx_auth_tokens_email ON auth_tokens(email);")

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
    (let [result (jdbc/execute-one! ds
                       ["INSERT INTO games (short_code, state, state_sequence) VALUES (?, ?, 0)"
                        (:short-code game-state)
                        (->json game-state)]
                       {:return-keys true
                        :builder-fn rs/as-unqualified-lower-maps})]
      (println "DEBUG create-game! result:" result)
      ;; SQLite returns last_insert_rowid() with parentheses as the key name
      (let [game-id (or (:id result) (get result (keyword "last_insert_rowid()")))]
        (println "DEBUG create-game! game-id:" game-id)
        (assoc result :id game-id)))))

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
  "Update game state with the sequence number of the last applied event."
  [game-id game-state state-sequence]
  (jdbc/execute-one! (datasource)
                     ["UPDATE games SET state = ?, state_sequence = ?, updated_at = datetime('now') WHERE id = ?"
                      (->json game-state)
                      state-sequence
                      game-id]))

(defn list-games
  "List all games, optionally filtered by status (extracted from state JSON)."
  ([] (list-games nil))
  ([status]
   (let [query (if status
                 ["SELECT * FROM games WHERE json_extract(state, '$.status') = ? ORDER BY created_at DESC"
                  (name status)]
                 ["SELECT * FROM games ORDER BY created_at DESC"])]
     (->> (jdbc/execute! (datasource) query {:builder-fn rs/as-unqualified-lower-maps})
          (map #(update % :state <-json))))))

;; =============================================================================
;; Event Sourcing
;; =============================================================================

(defn append-event!
  "Append an event to a game's event log. Returns the event with sequence_number."
  [game-id event-type event-data]
  (println "DEBUG append-event! - game-id:" game-id "event-type:" event-type)
  (when (nil? game-id)
    (println "ERROR: game-id is nil in append-event!")
    (throw (Exception. "game-id cannot be nil in append-event!")))
  (let [ds (datasource)
        next-seq (or (:seq (jdbc/execute-one! ds
                                              ["SELECT COALESCE(MAX(sequence_number), 0) + 1 as seq FROM game_events WHERE game_id = ?" game-id]
                                              {:builder-fn rs/as-unqualified-lower-maps}))
                     1)]
    (println "DEBUG append-event! - next-seq:" next-seq)
    (jdbc/execute-one! ds
                       ["INSERT INTO game_events (game_id, sequence_number, event_type, event_data) VALUES (?, ?, ?, ?)"
                        game-id next-seq (name event-type) (->json event-data)]
                       {:return-keys true
                        :builder-fn rs/as-unqualified-lower-maps})
    {:sequence_number next-seq :event_type event-type :event_data event-data}))

(defn get-events
  "Get all events for a game."
  [game-id]
  (->> (jdbc/execute! (datasource)
                      ["SELECT * FROM game_events WHERE game_id = ? ORDER BY sequence_number" game-id]
                      {:builder-fn rs/as-unqualified-lower-maps})
       (map #(update % :event_data <-json))))

(defn get-events-after
  "Get events after a given sequence number."
  [game-id after-sequence]
  (->> (jdbc/execute! (datasource)
                      ["SELECT * FROM game_events WHERE game_id = ? AND sequence_number > ? ORDER BY sequence_number"
                       game-id after-sequence]
                      {:builder-fn rs/as-unqualified-lower-maps})
       (map #(update % :event_data <-json))))

(defn apply-and-persist!
  "Append event and update state atomically. Returns the new sequence number."
  [game-id new-state event-type event-data]
  (let [event (append-event! game-id event-type event-data)]
    (update-game! game-id new-state (:sequence_number event))
    (:sequence_number event)))

;; =============================================================================
;; Player Operations
;; =============================================================================

(defn get-player
  "Get a player by ID."
  [player-id]
  (jdbc/execute-one! (datasource)
                     ["SELECT * FROM players WHERE id = ?" player-id]
                     {:builder-fn rs/as-unqualified-lower-maps}))
(defn create-player!
  "Create a new player and return the full record."
  [{:keys [name email]}]
  (let [result (jdbc/execute-one! (datasource)
                                  ["INSERT INTO players (name, email) VALUES (?, ?)"
                                   name email]
                                  {:return-keys true
                                   :builder-fn rs/as-unqualified-lower-maps})
        player-id (or (:id result) (get result (keyword "last_insert_rowid()")))]
    (get-player player-id)))

(defn get-player-by-email
  "Get a player by email."
  [email]
  (jdbc/execute-one! (datasource)
                     ["SELECT * FROM players WHERE email = ?" email]
                     {:builder-fn rs/as-unqualified-lower-maps}))

;; =============================================================================
;; Auth Token Operations
;; =============================================================================

(defn create-auth-token!
  "Create a new auth token for email sign-in."
  [{:keys [email token expires-at]}]
  (jdbc/execute-one! (datasource)
                     ["INSERT INTO auth_tokens (email, token, expires_at) VALUES (?, ?, ?)"
                      email token expires-at]
                     {:return-keys true
                      :builder-fn rs/as-unqualified-lower-maps}))

(defn get-auth-token
  "Get an auth token by token string."
  [token]
  (jdbc/execute-one! (datasource)
                     ["SELECT * FROM auth_tokens WHERE token = ?" token]
                     {:builder-fn rs/as-unqualified-lower-maps}))

(defn mark-token-used!
  "Mark an auth token as used."
  [token]
  (jdbc/execute-one! (datasource)
                     ["UPDATE auth_tokens SET used = 1 WHERE token = ?" token]))

(defn delete-expired-tokens!
  "Clean up expired tokens."
  []
  (jdbc/execute-one! (datasource)
                     ["DELETE FROM auth_tokens WHERE expires_at < datetime('now')"]))

;; =============================================================================
;; Game Players (for authorization - who can access which game)
;; =============================================================================

(defn add-player-to-game!
  "Add a player to a game (for authorization tracking)."
  [game-id player-id]
  (jdbc/execute-one! (datasource)
                     ["INSERT OR IGNORE INTO game_players (game_id, player_id) VALUES (?, ?)"
                      game-id player-id]
                     {:return-keys true
                      :builder-fn rs/as-unqualified-lower-maps}))

(defn get-game-player-ids
  "Get all player IDs for a game."
  [game-id]
  (->> (jdbc/execute! (datasource)
                      ["SELECT player_id FROM game_players WHERE game_id = ?" game-id]
                      {:builder-fn rs/as-unqualified-lower-maps})
       (map :player_id)))

(defn player-in-game?
  "Check if a player is in a game."
  [game-id player-id]
  (some? (jdbc/execute-one! (datasource)
                            ["SELECT 1 FROM game_players WHERE game_id = ? AND player_id = ?" game-id player-id]
                            {:builder-fn rs/as-unqualified-lower-maps})))

(defn get-player-games
  "Get all game IDs a player is in."
  [player-id]
  (->> (jdbc/execute! (datasource)
                      ["SELECT game_id FROM game_players WHERE player_id = ?" player-id]
                      {:builder-fn rs/as-unqualified-lower-maps})
       (map :game_id)))
