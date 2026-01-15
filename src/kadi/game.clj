(ns kadi.game
  "Game state and state transitions.

  Core philosophy:
  - Game state is a pure value (immutable map)
  - State transitions are pure functions: (state, action) -> state
  - Side effects (persistence, broadcasting) happen at the edges"
  (:require [kadi.cards :as cards]
            [kadi.validation :as validation]))

;; =============================================================================
;; Game State Shape
;; =============================================================================

(defn new-game
  "Create a new game in lobby state."
  [{:keys [id short-code]}]
  {:id id
   :short-code short-code
   :status :lobby

   ;; Players (ordered by join time for turn order)
   :players []

   ;; Turn management
   :current-player-index 0
   :direction :clockwise

   ;; Card locations
   :deck []
   :played-stack []

   ;; Special states
   :action {:type nil :suit nil}
   :penalty {:active false
             :type nil
             :target-player-id nil
             :blocked-suit nil}
   :awaiting-answer false

   ;; Timestamps
   :created-at (java.time.Instant/now)
   :updated-at (java.time.Instant/now)})

;; =============================================================================
;; Player Management
;; =============================================================================

(defn add-player
  "Add a player to the game. Only valid in lobby state."
  [state {:keys [id name]}]
  (if (= :lobby (:status state))
    (update state :players conj {:id id
                                 :name name
                                 :status :normal
                                 :hand []})
    (assoc state :error {:type :invalid-state
                         :message "Can only join games in lobby"})))

(defn get-player [state player-id]
  (first (filter #(= player-id (:id %)) (:players state))))

(defn get-player-index [state player-id]
  (first (keep-indexed (fn [i p] (when (= player-id (:id p)) i))
                       (:players state))))

(defn update-player [state player-id f]
  (update state :players
          (fn [players]
            (mapv (fn [p] (if (= player-id (:id p)) (f p) p))
                  players))))

(defn current-player [state]
  (get-in state [:players (:current-player-index state)]))

(defn current-player-id [state]
  (:id (current-player state)))

;; =============================================================================
;; Turn Management
;; =============================================================================

(defn next-player-index
  "Calculate the next player index, respecting direction and skip count."
  [{:keys [players direction current-player-index]} skip-count]
  (let [player-count (count players)
        offset (case direction
                 :clockwise skip-count
                 :counter-clockwise (- skip-count))]
    (mod (+ current-player-index offset player-count)
         player-count)))

(defn advance-turn
  "Advance to the next player's turn."
  ([state] (advance-turn state 1))
  ([state skip-count]
   (assoc state :current-player-index (next-player-index state skip-count))))

(defn reverse-direction [state]
  (update state :direction
          #(case % :clockwise :counter-clockwise :counter-clockwise :clockwise)))

;; =============================================================================
;; Card Operations
;; =============================================================================

(defn deal-cards
  "Deal n cards to a player from the deck."
  [state player-id n]
  (let [cards-to-deal (take n (:deck state))]
    (-> state
        (update :deck #(drop n %))
        (update-player player-id #(update % :hand into cards-to-deal)))))

(defn remove-cards-from-hand
  "Remove specific cards from a player's hand."
  [state player-id cards-to-remove]
  (let [cards-set (set cards-to-remove)]
    (update-player state player-id
                   #(update % :hand (fn [hand]
                                      (remove cards-set hand))))))

(defn add-to-played-stack
  "Add cards to the played stack."
  [state cards]
  (update state :played-stack into cards))

(defn top-card [state]
  (last (:played-stack state)))

(defn draw-card
  "Draw one card from deck to player's hand."
  [state player-id]
  (if (empty? (:deck state))
    (assoc state :error {:type :empty-deck :message "No cards in deck"})
    (let [card (first (:deck state))]
      (-> state
          (update :deck rest)
          (update-player player-id #(update % :hand conj card))
          (update-player player-id #(assoc % :status :normal))))))

(defn recycle-played-stack
  "Move all but top card from played stack back to deck (shuffled)."
  [state]
  (let [played (:played-stack state)
        top (last played)
        to-recycle (butlast played)]
    (if (empty? to-recycle)
      (assoc state :error {:type :cannot-recycle
                           :message "Not enough cards to recycle"})
      (-> state
          (assoc :deck (shuffle to-recycle))
          (assoc :played-stack [top])))))

;; =============================================================================
;; Game Start
;; =============================================================================

(defn start-game
  "Transition game from lobby to live, deal cards, set starting card."
  [state {:keys [cards-per-player] :or {cards-per-player 4}}]
  (if (< (count (:players state)) 2)
    (assoc state :error {:type :not-enough-players
                         :message "Need at least 2 players to start"})
    (let [deck (cards/make-deck)
          starting-card (cards/select-starting-card deck)
          deck-without-start (remove #{starting-card} deck)]
      (-> state
          (assoc :status :live)
          (assoc :deck deck-without-start)
          (assoc :played-stack [starting-card])
          ;; Deal cards to each player
          (as-> s (reduce (fn [st player]
                            (deal-cards st (:id player) cards-per-player))
                          s
                          (:players s)))))))

;; =============================================================================
;; Card Effects
;; =============================================================================

(defn apply-card-effects
  "Apply special card effects after playing cards."
  [state cards]
  (let [ranks (map :rank cards)
        jack-count (count (filter #{"J"} ranks))]
    (cond-> state
      ;; King reverses direction
      (some #{"K"} ranks)
      (reverse-direction)

      ;; Ace triggers suit selection
      (some #{"A"} ranks)
      (assoc-in [:action :type] :select-suit)

      ;; 2 creates draw-2 penalty
      (some #{"2"} ranks)
      (-> (assoc-in [:penalty :active] true)
          (assoc-in [:penalty :type] :two))

      ;; 3 creates draw-3 penalty
      (some #{"3"} ranks)
      (-> (assoc-in [:penalty :active] true)
          (assoc-in [:penalty :type] :three))

      ;; Jack skips players
      (pos? jack-count)
      (assoc ::skip-count (inc jack-count))

      ;; Question without answer
      (and (every? cards/question-card? cards)
           (not (empty? cards)))
      (assoc :awaiting-answer true))))

(defn maybe-advance-turn
  "Advance turn unless waiting for suit selection or question answer."
  [state cards]
  (let [skip-count (or (::skip-count state) 1)]
    (cond
      ;; Waiting for suit selection after Ace
      (= :select-suit (get-in state [:action :type]))
      (dissoc state ::skip-count)

      ;; Waiting for question answer
      (:awaiting-answer state)
      (dissoc state ::skip-count)

      ;; Normal turn advance
      :else
      (-> state
          (advance-turn skip-count)
          (dissoc ::skip-count)))))

(defn check-cardless
  "Check if player entered cardless state."
  [state player-id cards]
  (let [player (get-player state player-id)
        triggers-cardless? (some #(#{"K" "J" "2" "3"} (:rank %)) cards)]
    (if (and (empty? (:hand player)) triggers-cardless?)
      (update-player state player-id #(assoc % :status :cardless))
      state)))

;; =============================================================================
;; Penalty Handling
;; =============================================================================

(defn set-penalty-target [state]
  (let [next-idx (next-player-index state 1)
        next-player-id (get-in state [:players next-idx :id])]
    (assoc-in state [:penalty :target-player-id] next-player-id)))

(defn clear-penalty [state]
  (assoc state :penalty {:active false
                         :type nil
                         :target-player-id nil
                         :blocked-suit nil}))

(defn accept-penalty
  "Player accepts penalty and draws cards."
  [state player-id]
  (let [penalty-type (get-in state [:penalty :type])
        draw-count (case penalty-type :two 2 :three 3 0)]
    (-> state
        (draw-card player-id)
        (as-> s (if (> draw-count 1)
                  (reduce (fn [st _] (draw-card st player-id))
                          s (range (dec draw-count)))
                  s))
        (clear-penalty)
        (advance-turn))))

;; =============================================================================
;; Action Handlers (Pure State Transitions)
;; =============================================================================

(defmulti apply-action
  "Apply an action to the game state. Returns new state."
  (fn [_state action] (:type action)))

(defmethod apply-action :join-game [state {:keys [player-id player-name]}]
  (add-player state {:id player-id :name player-name}))

(defmethod apply-action :start-game [state action]
  (start-game state action))

(defmethod apply-action :play-cards [state {:keys [player-id cards]}]
  (let [validation (validation/validate-play state player-id cards)]
    (if (:valid? validation)
      (-> state
          (remove-cards-from-hand player-id cards)
          (add-to-played-stack cards)
          (apply-card-effects cards)
          (check-cardless player-id cards)
          (set-penalty-target)
          (maybe-advance-turn cards))
      (assoc state :error validation))))

(defmethod apply-action :draw-card [state {:keys [player-id]}]
  (-> state
      (draw-card player-id)
      (advance-turn)))

(defmethod apply-action :answer-question [state {:keys [player-id]}]
  (-> state
      (draw-card player-id)
      (assoc :awaiting-answer false)
      (advance-turn)))

(defmethod apply-action :select-suit [state {:keys [suit]}]
  (-> state
      (assoc-in [:action :suit] suit)
      (assoc-in [:action :type] nil)
      (advance-turn)))

(defmethod apply-action :accept-penalty [state {:keys [player-id]}]
  (accept-penalty state player-id))

(defmethod apply-action :default [state action]
  (assoc state :error {:type :unknown-action
                       :message (str "Unknown action type: " (:type action))}))
