(ns kadi.schema
  "Malli schemas for domain objects with normalization/coercion."
  (:require [malli.core :as m]
            [malli.transform :as mt]
            [malli.util :as mu]))

;; =============================================================================
;; Custom Transformers
;; =============================================================================

(def string->keyword-transformer
  "Transformer that coerces strings to keywords for enum-like fields."
  (mt/transformer
   {:name :string->keyword
    :decoders {:keyword (fn [schema]
                          (fn [value]
                            (cond
                              (keyword? value) value
                              (string? value) (keyword value)
                              :else value)))}}))

(def json-transformer
  "Transformer for JSON roundtrip normalization (strings -> keywords, etc)."
  (mt/transformer
   mt/strip-extra-keys-transformer
   mt/string-transformer
   string->keyword-transformer))

;; =============================================================================
;; Domain Schemas
;; =============================================================================

(def PlayerStatus
  [:enum :normal :penalty :skip :selecting-suit])

(def GameStatus
  [:enum :lobby :live :finished])

(def Direction
  [:enum :clockwise :counter-clockwise])

(def Ruleset
  [:enum :kadi])

(def Suit
  [:enum :hearts :diamonds :clubs :spades])

(def Rank
  [:enum :ace :two :three :four :five :six :seven :eight :nine :ten :jack :queen :king])

(def Card
  [:map
   [:suit Suit]
   [:rank Rank]])

(def Player
  [:map
   [:id int?]
   [:name string?]
   [:status PlayerStatus]])

(def Turn
  [:map
   [:current-player-index int?]
   [:direction Direction]])

(def Zones
  [:map
   [:deck [:sequential Card]]
   [:played-stack [:sequential Card]]
   [:hands [:map-of int? [:sequential Card]]]])

(def GameMeta
  [:map
   [:created-at inst?]
   [:updated-at inst?]])

(def Effect
  [:map
   [:type keyword?]
   [:data [:maybe map?]]])

(def Game
  "Core game state schema. Represents both in-memory and persisted game state."
  [:map
   [:status GameStatus]
   [:players [:sequential Player]]
   [:turn Turn]
   [:zones Zones]
   [:effects [:sequential Effect]]
   [:short-code string?]
   [:meta GameMeta]
   [:game/ruleset Ruleset]
   [:game/version int?]])

(def GameRow
  "Database row schema with additional metadata."
  [:map
   [:id int?]
   [:short_code string?]
   [:state Game]
   [:state_sequence int?]
   [:created_at string?]
   [:updated_at string?]])

;; =============================================================================
;; Normalization Functions
;; =============================================================================

(defn normalize-game
  "Normalize a game state to ensure consistent types (keywords, etc).
   Useful after JSON deserialization or event sourcing."
  [game]
  (when game
    (m/decode Game game json-transformer)))

(defn normalize-game-row
  "Normalize a database game row, ensuring state is properly typed."
  [row]
  (when row
    (let [normalized-state (normalize-game (:state row))]
      (assoc row :state normalized-state))))

(defn validate-game
  "Validate a game state against the schema. Returns {:valid? bool :errors ...}"
  [game]
  (let [valid? (m/validate Game game)]
    (if valid?
      {:valid? true}
      {:valid? false
       :errors (m/explain Game game)})))

(defn validate-game!
  "Validate a game state, throwing on invalid data."
  [game]
  (when-not (m/validate Game game)
    (throw (ex-info "Invalid game state"
                    {:errors (m/explain Game game)
                     :game game})))
  game)

;; =============================================================================
;; Schema Helpers
;; =============================================================================

(defn game-schema
  "Return the Game schema for inspection."
  []
  Game)

(comment
  ;; Test normalization
  (normalize-game {:status "live"
                   :players [{:id 1 :name "Alice" :status "normal"}]
                   :turn {:current-player-index 0 :direction "clockwise"}
                   :zones {:deck [] :played-stack [] :hands {}}
                   :effects []
                   :short-code "ABC123"
                   :meta {:created-at (java.time.Instant/now)
                          :updated-at (java.time.Instant/now)}
                   :game/ruleset "kadi"
                   :game/version 1})

  ;; Test validation
  (validate-game {:status :live
                  :players [{:id 1 :name "Alice" :status :normal}]
                  :turn {:current-player-index 0 :direction :clockwise}
                  :zones {:deck [] :played-stack [] :hands {}}
                  :effects []
                  :short-code "ABC123"
                  :meta {:created-at (java.time.Instant/now)
                         :updated-at (java.time.Instant/now)}
                  :game/ruleset :kadi
                  :game/version 1}))
