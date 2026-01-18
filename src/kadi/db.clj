(ns kadi.db
  "SQLite database operations."
  (:require [next.jdbc :as jdbc]
            [next.jdbc.result-set :as rs]
            [jsonista.core :as json]
            [kadi.game :as game]
            [kadi.schema :as schema]))

(def ^:dynamic *db-spec* {:dbtype "sqlite" :dbname "kadi.db"})

(defn datasource []
  "Get or create a datasource for the current *db-spec*.
   Always reads *db-spec* so dynamic binding works correctly."
  (jdbc/get-datasource *db-spec*))

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
     event_id TEXT NOT NULL UNIQUE,
     event_type TEXT NOT NULL,
     event_data TEXT NOT NULL,
     timestamp TEXT NOT NULL,
     created_at TEXT NOT NULL DEFAULT (datetime('now')),
     UNIQUE(game_id, sequence_number)
   );

  CREATE INDEX IF NOT EXISTS idx_games_short_code ON games(short_code);
  CREATE INDEX IF NOT EXISTS idx_games_status ON games(json_extract(state, '$.status'));
  CREATE INDEX IF NOT EXISTS idx_games_status_meta ON games(json_extract(state, '$.meta.status'));
   CREATE INDEX IF NOT EXISTS idx_game_events_game_id ON game_events(game_id);
   CREATE INDEX IF NOT EXISTS idx_game_events_event_id ON game_events(event_id);
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
;; Event Sourcing
;; =============================================================================

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

(defn rebuild-state-from-events
  "Rebuild game state by replaying all events from the event log.
  This allows verification of state correctness and recovery from corruption.
  Starts with nil since the first event (:game-created) creates the initial state."
  [game-id]
  (let [events (get-events game-id)]
    (reduce (fn [state {:keys [event_type event_data]}]
              (game/apply-action state (merge event_data {:type (keyword event_type)})))
            nil
            events)))

(defn append-event!
  "Append an event to a game's event log with idempotency protection.
   If event_id already exists, returns the existing event (idempotent).
   Otherwise inserts and returns the new event with sequence_number."
  [game-id event-id event-type timestamp event-data]
  (when (nil? game-id)
    (throw (Exception. "game-id cannot be nil in append-event!")))
  (let [ds (datasource)
        ;; Check if event_id already exists (idempotency)
        existing (jdbc/execute-one! ds
                                    ["SELECT sequence_number, event_type, event_data FROM game_events WHERE event_id = ?"
                                     event-id]
                                    {:builder-fn rs/as-unqualified-lower-maps})]
    (if existing
      ;; Event already exists, return it (idempotent)
      (assoc existing :event_data (<-json (:event_data existing)))
      ;; New event, insert it
      (let [next-seq (or (:seq (jdbc/execute-one! ds
                                                  ["SELECT COALESCE(MAX(sequence_number), 0) + 1 as seq FROM game_events WHERE game_id = ?" game-id]
                                                  {:builder-fn rs/as-unqualified-lower-maps}))
                         1)]
        (jdbc/execute-one! ds
                           ["INSERT INTO game_events (game_id, sequence_number, event_id, event_type, event_data, timestamp) VALUES (?, ?, ?, ?, ?, ?)"
                            game-id next-seq event-id (name event-type) (->json event-data) (str timestamp)]
                           {:return-keys true
                            :builder-fn rs/as-unqualified-lower-maps})
        {:sequence_number next-seq :event_type event-type :event_data event-data}))))

;; =============================================================================
;; Game Operations
;; =============================================================================

(defn- get-latest-event-seq
  "Get the latest event sequence number for a game."
  [game-id]
  (or (:seq (jdbc/execute-one! (datasource)
                               ["SELECT MAX(sequence_number) as seq FROM game_events WHERE game_id = ?" game-id]
                               {:builder-fn rs/as-unqualified-lower-maps}))
      0))

(defn update-game-cache!
  "Update the denormalized game state cache with the sequence number of the last applied event.
   The cached state is a materialized view derived from events for performance."
  [game-id game-state state-sequence]
  (jdbc/execute-one! (datasource)
                     ["UPDATE games SET state = ?, state_sequence = ?, updated_at = datetime('now') WHERE id = ?"
                      (->json game-state)
                      state-sequence
                      game-id]))

(defn- ensure-fresh-state
  "Check if game state is stale and rebuild from snapshot + subsequent events if needed.
   Uses the cached state as a snapshot and only replays events after state_sequence.
   Returns game with fresh state (normalized)."
  [game]
  (when game
    (let [latest-seq (get-latest-event-seq (:id game))
          cached-seq (:state_sequence game)]
      (if (or (nil? cached-seq) (< cached-seq latest-seq))
        ;; State is stale, rebuild from snapshot + subsequent events
        (let [snapshot-state (if (and (:state game) (pos? cached-seq))
                               (:state game)  ; Use cached state as snapshot
                               nil)           ; No snapshot, start from scratch
              subsequent-events (get-events-after (:id game) (or cached-seq 0))
              fresh-state (reduce (fn [state {:keys [event_type event_data]}]
                                    (game/apply-action state (merge event_data {:type (keyword event_type)})))
                                  snapshot-state
                                  subsequent-events)
              normalized-state (schema/normalize-game fresh-state)]
          (update-game-cache! (:id game) normalized-state latest-seq)
          (assoc game :state normalized-state :state_sequence latest-seq))
        ;; State is fresh
        game))))

(defn get-game-by-code
  "Get a game by short code with fresh state."
  [short-code]
  (when-let [row (jdbc/execute-one! (datasource)
                                    ["SELECT * FROM games WHERE short_code = ?" short-code]
                                    {:builder-fn rs/as-unqualified-lower-maps})]
    (-> row
        (update :state <-json)
        ensure-fresh-state
        schema/normalize-game-row)))

(defn list-games
  "List all games, optionally filtered by status (extracted from state JSON)."
  ([] (list-games nil))
  ([status]
   (let [query (if status
                 ["SELECT * FROM games WHERE COALESCE(json_extract(state, '$.status'), json_extract(state, '$.meta.status')) = ? ORDER BY created_at DESC"
                  (name status)]
                 ["SELECT * FROM games ORDER BY created_at DESC"])]
     (->> (jdbc/execute! (datasource) query {:builder-fn rs/as-unqualified-lower-maps})
          (map #(update % :state <-json))
          (map schema/normalize-game-row)))))

(defn create-game!
  "Create a new game from an action. Persists event and game_player in a transaction,
   then computes state by applying the event. Returns {:id :short-code :state :state_sequence}."
  [action]
  (let [short-code (or (:short-code action) (game/generate-short-code))
        player-id (get-in action [:player :id])
        event-id (or (:event-id action) (str (java.util.UUID/randomUUID)))
        timestamp (or (:timestamp action) (java.time.Instant/now))
        action-with-code (assoc action :short-code short-code)]
    ;; Transaction: persist event and authorization
    (let [{:keys [game-id]}
          (jdbc/with-transaction [tx (datasource)]
            (let [game-result (jdbc/execute-one! tx
                                                 ["INSERT INTO games (short_code, state, state_sequence) VALUES (?, ?, 0)"
                                                  short-code "{}"]
                                                 {:return-keys true
                                                  :builder-fn rs/as-unqualified-lower-maps})
                  new-game-id (or (:id game-result) (get game-result (keyword "last_insert_rowid()")))
                  next-seq 1]
              ;; Append event with event_id and timestamp
              (jdbc/execute-one! tx
                                 ["INSERT INTO game_events (game_id, sequence_number, event_id, event_type, event_data, timestamp) VALUES (?, ?, ?, ?, ?, ?)"
                                  new-game-id next-seq event-id "game-created" (->json action-with-code) (str timestamp)])
              ;; Add player to game for authorization
              (jdbc/execute-one! tx
                                 ["INSERT OR IGNORE INTO game_players (game_id, player_id) VALUES (?, ?)"
                                  new-game-id player-id])
              {:game-id new-game-id}))]
      ;; State will be computed lazily on read via get-game-by-code
      {:id game-id :short-code short-code})))

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
  "Get all games a player is in, with fresh state."
  [player-id]
  (->> (jdbc/execute! (datasource)
                      ["SELECT g.* FROM games g
                        JOIN game_players gp ON g.id = gp.game_id
                        WHERE gp.player_id = ?
                        ORDER BY g.updated_at DESC" player-id]
                      {:builder-fn rs/as-unqualified-lower-maps})
       (map #(update % :state <-json))
       (map ensure-fresh-state)
       (map schema/normalize-game-row)))

(comment
  (rebuild-state-from-events 120))
