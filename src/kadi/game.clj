(ns kadi.game
  "Game state and state transitions with validation-first commands.

  Core philosophy:
  - Game state is a pure value (immutable map)
  - Commands are validated before applying; invalid commands return {:error reason}
  - Only valid commands should be persisted as events
  - State transitions are pure: (state, command) -> {:ok state} | {:error reason}
  - Hands are stored in zones: :zones/:hands {player-id [cards...]}
  - Side effects (persistence, broadcasting) happen at the edges"
  (:require [kadi.cards :as cards]
            [kadi.validation :as validation]))

;; =============================================================================
;; Game State Shape (hierarchical)
;; =============================================================================

(defn new-game
  "Create a new game in lobby state with hierarchical schema.

  short-code: game join code; game-id: optional DB id (when known)."
  ([short-code] (new-game short-code nil))
  ([short-code game-id]
   {:game/id game-id
    :short-code short-code
   :game/ruleset :kadi
   :game/version 1

   ;; Players (ordered by join time for turn order) - metadata only
   :players []

   ;; Turn management
   :turn {:current-player-index 0
          :direction :clockwise}

   ;; Card locations
   :zones {:deck []
           :played-stack []
           :hands {}}

   ;; Active effects (penalties, suit selection, awaits, etc.)
   :effects []

   ;; Game metadata
   :status :lobby
     :meta {:created-at (java.time.Instant/now)
       :updated-at (java.time.Instant/now)}}))

;; =============================================================================
;; Player Management
;; =============================================================================

(defn game-status [state]
  ;; Prefer root-level status; fallback to legacy meta path for compatibility
  (or (:status state)
      (get-in state [:meta :status])))

(defn turn-direction [state]
  (cond
    (contains? state :direction) (:direction state)
    :else (or (get-in state [:turn :direction]) :clockwise)))

(defn current-player-index [state]
  (cond
    (contains? state :current-player-index) (:current-player-index state)
    :else (get-in state [:turn :current-player-index] 0)))

(defn players [state]
  (:players state))

(defn add-player-metadata
  "Add player metadata (no hand here)."
  [state {:keys [id name]}]
  (update state :players conj {:id id
                               :name name
                               :status :normal}))

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
  (get-in state [:players (current-player-index state)]))

(defn current-player-id [state]
  (:id (current-player state)))

;; =============================================================================
;; Hands Helpers (hands live in :zones/:hands keyed by player-id)
;; =============================================================================

(defn get-hand [state player-id]
  (get-in state [:zones :hands player-id] []))

(defn set-hand [state player-id new-hand]
  (assoc-in state [:zones :hands player-id] new-hand))

(defn update-hand [state player-id f]
  (update-in state [:zones :hands player-id] (fnil f [])))

;; Embed hands for legacy validation that expects :hand on players
(defn with-embedded-hands [state]
  (update state :players
          (fn [ps]
            (mapv (fn [p]
                    (assoc p :hand (get-hand state (:id p))))
                  ps))))

;; =============================================================================
;; Turn Management
;; =============================================================================

(defn next-player-index
  "Calculate the next player index, respecting direction and skip count."
  [{:keys [players] :as state} skip-count]
  (let [player-count (count players)
      direction (turn-direction state)
      current-player-index (current-player-index state)
        offset (case direction
                 :clockwise skip-count
                 :counter-clockwise (- skip-count))]
    (mod (+ current-player-index offset player-count)
         player-count)))

(defn advance-turn
  "Advance to the next player's turn."
  ([state] (advance-turn state 1))
  ([state skip-count]
   (let [idx (next-player-index state skip-count)]
     (-> state
         (assoc-in [:turn :current-player-index] idx)
         (assoc :current-player-index idx)))))

(defn reverse-direction [state]
  (let [new-dir (case (turn-direction state)
                  :clockwise :counter-clockwise
                  :counter-clockwise :clockwise
                  :clockwise)]
    (-> state
        (assoc-in [:turn :direction] new-dir)
        (assoc :direction new-dir))))

;; =============================================================================
;; Card Operations
;; =============================================================================

(defn deal-cards
  "Deal n cards to a player from the deck."
  [state player-id n]
  (let [cards-to-deal (take n (get-in state [:zones :deck]))]
    (-> state
        (update-in [:zones :deck] #(drop n %))
        (update-hand player-id #(into % cards-to-deal)))))

(defn remove-cards-from-hand
  "Remove specific cards from a player's hand."
  [state player-id cards-to-remove]
  (let [cards-set (set cards-to-remove)]
    (update-hand state player-id
                 (fn [hand]
                   (vec (remove cards-set hand))))))

(defn add-to-played-stack
  "Add cards to the played stack."
  [state cards]
  (update-in state [:zones :played-stack] into cards))

(defn top-card [state]
  (last (get-in state [:zones :played-stack])))

(defn draw-card
  "Draw one card from deck to player's hand."
  [state player-id]
  (if (empty? (get-in state [:zones :deck]))
    state
    (let [card (first (get-in state [:zones :deck]))]
      (-> state
          (update-in [:zones :deck] rest)
          (update-hand player-id #(conj % card))
          (update-player player-id #(assoc % :status :normal))))))

(defn recycle-played-stack
  "Move all but top card from played stack back to deck (shuffled)."
  [state]
  (let [played (get-in state [:zones :played-stack])
        top (last played)
        to-recycle (butlast played)]
    (if (empty? to-recycle)
      state
      (-> state
          (assoc-in [:zones :deck] (shuffle to-recycle))
          (assoc-in [:zones :played-stack] [top])))))

;; =============================================================================
;; Game Start
;; =============================================================================

(defn start-game
  "Transition game from lobby to live, deal cards, set starting card."
  [state {:keys [cards-per-player] :or {cards-per-player 4}}]
  (if (< (count (:players state)) 2)
    state
    (let [deck (cards/make-deck)
          starting-card (cards/select-starting-card deck)
          deck-without-start (remove #{starting-card} deck)]
      (-> state
          (assoc :status :live)
          (assoc-in [:zones :deck] deck-without-start)
          (assoc-in [:zones :played-stack] [starting-card])
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
        reverse-direction

      ;; Ace triggers suit selection
      (some #{"A"} ranks)
        (update :effects conj {:type :select-suit})

      ;; 2 creates draw-2 penalty
      (some #{"2"} ranks)
        (update :effects conj {:type :penalty :penalty-type :two})

      ;; 3 creates draw-3 penalty
      (some #{"3"} ranks)
        (update :effects conj {:type :penalty :penalty-type :three})

      ;; Jack skips players
      (pos? jack-count)
      (assoc ::skip-count (inc jack-count))

        ;; Question without answer
        (and (every? cards/question-card? cards)
             (not (empty? cards)))
        (update :effects conj {:type :awaiting-answer}))))

(defn maybe-advance-turn
  "Advance turn unless waiting for suit selection or question answer."
  [state cards]
    (let [skip-count (or (::skip-count state) 1)]
    (cond
      ;; Waiting for suit selection
      (some #(= :select-suit (:type %)) (:effects state))
      (dissoc state ::skip-count)

      ;; Waiting for question answer
      (some #(= :awaiting-answer (:type %)) (:effects state))
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
        hand (get-hand state player-id)
      triggers-cardless? (some #(contains? #{"K" "J" "2" "3"} (:rank %)) cards)]
    (if (and (empty? hand) triggers-cardless?)
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
  (let [penalty-effect (first (filter #(= :penalty (:type %)) (:effects state)))
  penalty-type (:penalty-type penalty-effect)
  draw-count (case penalty-type :two 2 :three 3 0)]
    (-> state
        (draw-card player-id)
        (as-> s (if (> draw-count 1)
                  (reduce (fn [st _] (draw-card st player-id))
                          s (range (dec draw-count)))
                  s))
  (update :effects #(remove (fn [e] (= :penalty (:type e))) %))
        (advance-turn))))

;; =============================================================================
;; Command Validation Helpers
;; =============================================================================
(defn has-effect? [state effect-type]
  (some #(= effect-type (:type %)) (:effects state)))

(defn get-effect [state effect-type]
  (first (filter #(= effect-type (:type %)) (:effects state))))

(defn- validate-join [state {:keys [id name]}]
  (cond
    (not= :lobby (game-status state)) {:error "Game is not in lobby"}
    (get-player state id) {:error "Player already in game"}
    (not name) {:error "Player name required"}
    :else {:ok true}))

(defn join-player [state player]
  (let [player* (select-keys player [:id :name])
        v (validate-join state player*)]
    (if (:error v)
      v
      {:ok (-> state
               (add-player-metadata player*)
               (update-in [:meta :updated-at] (constantly (java.time.Instant/now))))})))

;; Compatibility helper: returns plain state on success, {:error "..."} on failure.
(defn add-player [state player]
  (let [res (join-player state player)]
    (if (:ok res) (:ok res) res)))

(defn validate-start [state]
  (cond
    (not= :lobby (game-status state)) {:error "Game is not in lobby"}
    (< (count (players state)) 2) {:error "Need at least 2 players to start"}
    :else {:ok true}))

(defn start-game-cmd [state & {:keys [cards-per-player] :or {cards-per-player 4}}]
  (let [v (validate-start state)]
    (if (:error v)
      v
      {:ok (-> state
               (start-game {:cards-per-player cards-per-player})
               (update-in [:meta :updated-at] (constantly (java.time.Instant/now))))})))

(defn validate-draw [state player-id]
  (cond
    (not= :live (game-status state)) {:error "Game is not live"}
    (not (get-player state player-id)) {:error "Player not in game"}
    (not= player-id (current-player-id state)) {:error "Not your turn"}
    (empty? (get-in state [:zones :deck])) {:error "No cards in deck"}
    :else {:ok true}))

(defn draw-card-cmd [state player-id]
  (let [v (validate-draw state player-id)]
    (if (:error v)
      v
      {:ok (-> state
               (draw-card player-id)
               (advance-turn)
               (update-in [:meta :updated-at] (constantly (java.time.Instant/now))))})))

(defn validate-play-cards [state player-id cards]
  (cond
    (not= :live (game-status state)) {:error "Game is not live"}
    (not (get-player state player-id)) {:error "Player not in game"}
    (not= player-id (current-player-id state)) {:error "Not your turn"}
    (empty? cards) {:error "Must play at least one card"}
    :else (validation/validate-play (with-embedded-hands state) player-id cards)))

(defn play-cards-cmd [state player-id cards]
  (let [v (validate-play-cards state player-id cards)]
    (if (:error v)
      v
      (if (:valid? v)
        {:ok (-> state
                 (remove-cards-from-hand player-id cards)
                 (add-to-played-stack cards)
                 (apply-card-effects cards)
                 (check-cardless player-id cards)
                 (maybe-advance-turn cards)
                 (update-in [:meta :updated-at] (constantly (java.time.Instant/now))))}
        {:error (:reason v)}))))

(defn validate-select-suit [state suit]
  (cond
    (not (has-effect? state :select-suit)) {:error "No suit selection in progress"}
    (not (contains? #{:clubs :diamonds :hearts :spades} suit)) {:error "Invalid suit"}
    :else {:ok true}))

(defn select-suit-cmd [state suit]
  (let [v (validate-select-suit state suit)]
    (if (:error v)
      v
      {:ok (-> state
               (update :effects #(remove (fn [e] (= :select-suit (:type e))) %))
               (update :effects conj {:type :suit-selected :suit suit})
               (advance-turn)
               (update-in [:meta :updated-at] (constantly (java.time.Instant/now))))})))

(defn validate-answer [state player-id]
  (cond
    (not= :live (game-status state)) {:error "Game is not live"}
    (not (get-player state player-id)) {:error "Player not in game"}
    (not= player-id (current-player-id state)) {:error "Not your turn"}
    (not (has-effect? state :awaiting-answer)) {:error "Not awaiting answer"}
    (empty? (get-in state [:zones :deck])) {:error "No cards in deck"}
    :else {:ok true}))

(defn answer-question-cmd [state player-id]
  (let [v (validate-answer state player-id)]
    (if (:error v)
      v
      {:ok (-> state
               (draw-card player-id)
               (update :effects #(remove (fn [e] (= :awaiting-answer (:type e))) %))
               (advance-turn)
               (update-in [:meta :updated-at] (constantly (java.time.Instant/now))))})))

(defn validate-accept-penalty [state player-id]
  (cond
    (not= :live (game-status state)) {:error "Game is not live"}
    (not (get-player state player-id)) {:error "Player not in game"}
    (not (has-effect? state :penalty)) {:error "No penalty in progress"}
    :else {:ok true}))

(defn accept-penalty-cmd [state player-id]
  (let [v (validate-accept-penalty state player-id)]
    (if (:error v)
      v
      {:ok (-> state
               (accept-penalty player-id)
               (update-in [:meta :updated-at] (constantly (java.time.Instant/now))))})))

;; =============================================================================
;; Event Replay (apply-action assumes events are valid)
;; =============================================================================

(defmulti apply-action
  "Apply an action (event) to the game state. Assumes validity."
  (fn [_state action] (:type action)))

(defmethod apply-action :join-game [state {:keys [player-id player-name]}]
  (-> state
      (add-player-metadata {:id player-id :name player-name})
      (update-in [:meta :updated-at] (constantly (java.time.Instant/now)))))

(defmethod apply-action :start-game [state action]
  (-> (start-game state action)
      (update-in [:meta :updated-at] (constantly (java.time.Instant/now)))) )

(defmethod apply-action :play-cards [state {:keys [player-id cards]}]
  (-> state
      (remove-cards-from-hand player-id cards)
      (add-to-played-stack cards)
      (apply-card-effects cards)
      (check-cardless player-id cards)
      (maybe-advance-turn cards)
      (update-in [:meta :updated-at] (constantly (java.time.Instant/now)))))

(defmethod apply-action :draw-card [state {:keys [player-id]}]
  (-> state
      (draw-card player-id)
      (advance-turn)
      (update-in [:meta :updated-at] (constantly (java.time.Instant/now)))))

(defmethod apply-action :answer-question [state {:keys [player-id]}]
  (-> state
      (draw-card player-id)
      (update :effects #(remove (fn [e] (= :awaiting-answer (:type e))) %))
      (advance-turn)
      (update-in [:meta :updated-at] (constantly (java.time.Instant/now)))))

(defmethod apply-action :select-suit [state {:keys [suit]}]
  (-> state
      (update :effects #(remove (fn [e] (= :select-suit (:type e))) %))
      (update :effects conj {:type :suit-selected :suit suit})
      (advance-turn)
      (update-in [:meta :updated-at] (constantly (java.time.Instant/now)))))

(defmethod apply-action :accept-penalty [state {:keys [player-id]}]
  (-> state
      (accept-penalty player-id)
      (update-in [:meta :updated-at] (constantly (java.time.Instant/now)))))

(defmethod apply-action :default [state _]
  state)
