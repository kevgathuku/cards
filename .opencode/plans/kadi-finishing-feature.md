# Kadi Game Finishing Feature - Implementation Plan

**Date**: 2026-02-08  
**Status**: Ready for Implementation  
**Estimated Effort**: ~760 lines (code + tests + docs)

---

## Executive Summary

Implement the "Kadi" declaration and game finishing mechanism where players can optionally declare their intent to finish when playing cards. Successfully emptying their hand while in Kadi state results in winning the game. Failing to finish properly (playing K/J/2/3 as last card, or not declaring Kadi) results in becoming cardless.

---

## Core Requirements (Confirmed)

1. ✅ **Declaring Kadi is OPTIONAL** - Strategic choice, not automatic
2. ✅ **Declaring Kadi is REQUIRED to win** - Without it, player becomes cardless
3. ✅ **Invalid finish → Cardless** - K/J/2/3 as last card = cardless (even in Kadi)
4. ✅ **Valid finish without Kadi → Cardless** - Must declare to win
5. ✅ **Drawing in Kadi** - Player can choose to maintain or drop status (voluntary draws only)
6. ✅ **Penalty draws reset Kadi** - Accepting penalty automatically exits Kadi (no choice)
7. ✅ **UI Tooltip** - Explain the mechanic with tooltip
8. ✅ **Event Tracking** - Track `declare-kadi?` and hand size in events
9. ✅ **Visual Notification** - Kadi status visible to ALL players via banner
10. ✅ **Single Winner** - First player to finish wins, game ends
11. ✅ **Accessibility** - ARIA labels, keyboard-friendly, screen reader support
12. ✅ **Desktop-first** - Mobile responsiveness not priority

---

## Critical Validation: Penalty Handling

**Finding**: The existing `draw-card` function (line 196 in `game.clj`) already resets player status to `:normal`:

```clojure
(defn draw-card
  "Draw one card from deck to player's hand."
  [state player-id]
  ;; ...
  (update-player player-id #(assoc % :status :normal)))
```

**Impact on Kadi Feature**:

1. **Voluntary draws** (regular draw button):
   - Should have `maintain-kadi?` option
   - Player chooses whether to stay in Kadi after drawing

2. **Involuntary draws** (accept-penalty, answer-question):
   - Should ALWAYS reset Kadi (no choice)
   - Rationale: If player is in Kadi (trying to finish) but must accept penalty, they miscalculated
   - Drawing 2-3 cards means they can't finish anymore
   - Automatic reset is correct behavior

**Implementation Decision**:
- Update `draw-card` to accept optional `maintain-kadi?` parameter
- Only apply `maintain-kadi?` logic for voluntary draws
- `accept-penalty` and `answer-question` do NOT pass `maintain-kadi?` → always reset

---

## Behavior Matrix (Final)

| Scenario | Kadi? | Last Cards | Hand After | Result |
|----------|-------|------------|------------|--------|
| Valid finish | ✅ | 5♥ | Empty | **🏆 WIN** |
| Valid combo | ✅ | 7♥ 7♦ 7♣ | Empty | **🏆 WIN** |
| Invalid finish | ✅ | K♥ | Empty | **Cardless** ⚠️ |
| Invalid finish | ✅ | J♥ | Empty | **Cardless** ⚠️ |
| Invalid finish | ✅ | 2♥ | Empty | **Cardless** ⚠️ |
| Invalid finish | ✅ | 3♥ | Empty | **Cardless** ⚠️ |
| Forgot Kadi | ❌ | 5♥ | Empty | **Cardless** ⚠️ |
| Forgot Kadi | ❌ | K♥ | Empty | **Cardless** ⚠️ |
| Partial play | ✅ | 7♥ | 2 cards left | **In Kadi** 🎯 |
| Voluntary draw + maintain | N/A | N/A | +1 card | **Stay Kadi** 🎯 |
| Voluntary draw + drop | N/A | N/A | +1 card | **Normal** |
| Accept penalty (in Kadi) | N/A | N/A | +2/3 cards | **Normal** (auto-reset) |
| Answer question (in Kadi) | N/A | N/A | +1 card | **Normal** (auto-reset) |
| Multi Kadi | ✅ | Valid | Empty (1st) | **Winner** 🏆 |

---

## Phase 1: Schema Updates

**File**: `src/kadi/schema.clj`

### Changes

```clojure
;; Line ~35 - Add :kadi to PlayerStatus enum
(def PlayerStatus
  [:enum :normal :penalty :skip :selecting-suit :cardless :kadi])

;; Line ~120 - Add optional winner field to Game schema
;; (Inside Game schema map)
[:winner {:optional true} int?]  ; Player ID of winner when game finishes
```

**Reasoning**: 
- `:kadi` status marks players who have declared intent to finish
- `:winner` stores which player won when game status becomes `:finished`

---

## Phase 2: Core Game Logic

**File**: `src/kadi/game.clj`

### 2.1 Update `draw-card` Function (Line ~187)

**Add optional parameter to support maintaining Kadi**:

```clojure
(defn draw-card
  "Draw one card from deck to player's hand.
   
   Optional maintain-kadi?: If true and player is in :kadi state, 
   keep them in Kadi instead of resetting to :normal.
   
   Note: Defaults to false (existing behavior = always reset to :normal)."
  [state player-id & {:keys [maintain-kadi?]}]
  (if (empty? (get-in state [:zones :deck]))
    state
    (let [card (first (get-in state [:zones :deck]))
          player (get-player state player-id)
          was-kadi? (= :kadi (:status player))
          was-cardless? (= :cardless (:status player))
          should-stay-kadi? (and was-kadi? maintain-kadi?)]
      (-> state
          (update-in [:zones :deck] rest)
          (update-hand player-id #(conj % card))
          ;; NEW: Only reset to :normal if not maintaining Kadi
          (update-player player-id #(assoc % :status 
                                      (cond
                                        should-stay-kadi? :kadi
                                        :else :normal)))))))
```

**Impact**:
- Backward compatible (defaults to existing behavior)
- Enables voluntary draws to maintain Kadi
- Involuntary draws (penalty, question) still reset automatically

### 2.2 Update `play-cards-cmd` Signature (Line ~393)

```clojure
(defn play-cards-cmd 
  "Execute play-cards command with optional Kadi declaration.
   
   Parameters:
   - state: Current game state
   - player-id: ID of player making the move
   - cards: Vector of cards to play
   - declare-kadi?: (optional) Boolean - if true, player declares intent to finish"
  [state player-id cards & {:keys [declare-kadi?]}]
  ;; ... existing implementation
  )
```

### 2.3 Update `apply-action :play-cards` (Line ~513)

```clojure
(defmethod apply-action :play-cards 
  [state {:keys [player-id cards declare-kadi? timestamp]}]
  (let [normalized-cards (schema/normalize-cards cards)
        prev-top-card (last (get-in state [:zones :played-stack]))
        
        ;; NEW: Set player to :kadi status BEFORE playing if declaring
        state-with-kadi (if declare-kadi?
                          (update-player state player-id #(assoc % :status :kadi))
                          state)
        
        ;; Calculate hand state
        player (get-player state-with-kadi player-id)
        hand-before (get-hand state-with-kadi player-id)
        hand-after-size (- (count hand-before) (count normalized-cards))
        in-kadi-state? (= :kadi (:status player))
        will-empty-hand? (zero? hand-after-size)
        
        ;; Apply all game effects
        state-after-play (-> state-with-kadi
                            (update :effects #(remove (fn [e] (= :suit-selected (:type e))) %))
                            (remove-cards-from-hand player-id normalized-cards)
                            (add-to-played-stack normalized-cards)
                            (apply-card-effects normalized-cards prev-top-card)
                            (check-cardless player-id normalized-cards)  ; May set :cardless!
                            (maybe-advance-turn normalized-cards))
        
        ;; NEW: Check if player successfully finished
        ;; Success = in Kadi + hand empty + NOT cardless (check-cardless didn't trigger)
        player-after (get-player state-after-play player-id)
        successfully-finished? (and in-kadi-state? 
                                   will-empty-hand? 
                                   (not= :cardless (:status player-after)))]
    
    (cond-> state-after-play
      ;; If successful finish → set game to finished, record winner
      successfully-finished?
      (-> (assoc :status :finished)
          (assoc :winner player-id))
      
      ;; Update timestamp
      timestamp 
      (update-in [:meta :updated-at] (constantly timestamp)))))
```

**Key Logic**:
1. If `declare-kadi?` = true → set player status to `:kadi` before playing
2. Play cards through normal flow
3. `check-cardless` runs - may set player to `:cardless` if K/J/2/3 played
4. After all effects, if player is STILL in `:kadi` (not cardless) AND hand is empty → **WIN**
5. Otherwise, player either has cards left (Kadi continues) or became cardless

### 2.4 Update `check-cardless` (Line ~308)

```clojure
(defn check-cardless
  "Check if player entered cardless state.
   
   Triggers when:
   1. Hand is empty after playing cards, AND
   2. Played a cardless-triggering card (K/J/2/3), OR
   3. Hand is empty WITHOUT being in :kadi state (forgot to declare)
   
   CRITICAL: This triggers even if player is in :kadi state!
   Playing K/J/2/3 as last card while in Kadi = invalid finish = cardless.
   
   Also triggers if hand is empty WITHOUT being in Kadi (forgot to declare)."
  [state player-id cards]
  (let [player (get-player state player-id)
        hand (get-hand state player-id)
        triggers-cardless-card? (some #(contains? #{"K" "J" "2" "3"} (:rank %)) cards)
        in-kadi? (= :kadi (:status player))
        empty-hand-without-kadi? (and (empty? hand) (not in-kadi?))]
    
    (cond
      ;; Case 1: Played K/J/2/3 and hand is now empty → ALWAYS cardless
      ;; (Even in Kadi - invalid finishing card)
      (and (empty? hand) triggers-cardless-card?)
      (update-player state player-id #(assoc % :status :cardless))
      
      ;; Case 2: Hand is empty but NOT in Kadi → ALWAYS cardless
      ;; (Forgot to declare Kadi)
      empty-hand-without-kadi?
      (update-player state player-id #(assoc % :status :cardless))
      
      ;; Otherwise: no change
      :else
      state)))
```

**Reasoning**:
- K/J/2/3 as last card → **always** triggers cardless (even in Kadi)
- Empty hand without Kadi → **always** triggers cardless
- Only way to win: Kadi + valid finishing card (not K/J/2/3)

### 2.5 Update `draw-card-cmd` (Line ~400)

**Add support for maintain-kadi parameter**:

```clojure
(defn draw-card-cmd 
  [state player-id & {:keys [maintain-kadi?]}]
  (let [v (validate-draw state player-id)]
    (if (:error v)
      v
      {:ok (-> state
               ;; Pass maintain-kadi? to draw-card
               (draw-card player-id :maintain-kadi? maintain-kadi?)
               (advance-turn)
               (update-in [:meta :updated-at] (constantly (java.time.Instant/now))))})))
```

### 2.6 Update `apply-action :draw-card` (Line ~526)

```clojure
(defmethod apply-action :draw-card 
  [state {:keys [player-id maintain-kadi? timestamp]}]
  (cond-> (-> state
              (draw-card player-id :maintain-kadi? maintain-kadi?)
              (advance-turn))
    timestamp 
    (update-in [:meta :updated-at] (constantly timestamp))))
```

### 2.7 Keep `accept-penalty` Unchanged (Line ~333)

**No changes needed** - it calls `draw-card` without `maintain-kadi?`, so it will always reset to `:normal` (correct behavior for involuntary draws).

### 2.8 Keep `answer-question` Unchanged (Line ~461)

**No changes needed** - same reasoning as `accept-penalty`.

---

## Phase 3: HTTP Handler Updates

**File**: `src/kadi/handlers.clj`

### 3.1 Update `play-cards` Handler (Line ~218)

```clojure
(defn play-cards [request]
  (if-let [player (auth/current-player request)]
    (let [short-code (get-in request [:path-params :code])
          [game error-msg] (check-game-status short-code :live)]
      (if error-msg
        (redirect "/games" {:type :error :message error-msg})
        (if-not (player-in-game? player game)
          (redirect "/games" {:type :error :message "You are not in this game"})
          (let [params (parse-form request)
                ordered-cards-str (get params "ordered-cards")
                card-ids (if (and ordered-cards-str (not= ordered-cards-str ""))
                          (clojure.string/split ordered-cards-str #",")
                          [])
                parsed-cards (keep cards/id->card card-ids)
                
                ;; NEW: Parse declare-kadi checkbox
                declare-kadi? (= "on" (get params "declare-kadi"))
                
                ;; NEW: Capture hand size for event tracking
                hand-size (count (game/get-hand (:state game) (:id player)))
                
                result (game/play-cards-cmd (:state game) (:id player) parsed-cards 
                                           :declare-kadi? declare-kadi?)]
            (if (:error result)
              (redirect (str "/games/" short-code) {:type :error :message (:error result)})
              (do
                 (let [event-id (str (java.util.UUID/randomUUID))
                       timestamp (java.time.Instant/now)]
                   (db/append-event! (:id game) event-id :play-cards timestamp
                                     {:player-id (:id player)
                                      :cards parsed-cards
                                      :declare-kadi? declare-kadi?  ; Track declaration
                                      :hand-size-before hand-size   ; Track hand size
                                      :timestamp timestamp}))
                (redirect (str "/games/" short-code))))))))
    (redirect "/auth/signin")))
```

### 3.2 Update `draw-card` Handler (Line ~246)

```clojure
(defn draw-card [request]
  (if-let [player (auth/current-player request)]
    (let [short-code (get-in request [:path-params :code])
          [game error-msg] (check-game-status short-code :live)]
      (if error-msg
        (redirect "/games" {:type :error :message error-msg})
        (if-not (player-in-game? player game)
          (redirect "/games" {:type :error :message "You are not in this game"})
          (let [params (parse-form request)
                ;; NEW: Parse maintain-kadi checkbox
                maintain-kadi? (= "on" (get params "maintain-kadi"))
                
                result (game/draw-card-cmd (:state game) (:id player)
                                          :maintain-kadi? maintain-kadi?)]
            (if (:error result)
              (redirect (str "/games/" short-code) {:type :error :message (:error result)})
              (do
                (let [event-id (str (java.util.UUID/randomUUID))
                      timestamp (java.time.Instant/now)]
                  (db/append-event! (:id game) event-id :draw-card timestamp
                                    {:player-id (:id player)
                                     :maintain-kadi? maintain-kadi?  ; Track in events
                                     :timestamp timestamp}))
                (redirect (str "/games/" short-code))))))))
    (redirect "/auth/signin")))
```

### 3.3 Keep `accept-penalty` and `answer-question` Handlers Unchanged

**No changes needed** - these handlers don't need `maintain-kadi?` parameter since the underlying functions automatically reset to `:normal`.

---

## Phase 4: UI/View Updates

**File**: `src/kadi/views.clj`

### 4.1 Add "Declare Kadi" Checkbox with Tooltip & Accessibility (Line ~430)

**Add inside play form, before buttons**:

```clojure
;; NEW: Kadi declaration checkbox (only show during normal play)
(when (and is-my-turn? 
           (not has-select-suit?)
           (not has-awaiting-answer?)
           (not has-penalty?))
  [:div {:class "kadi-declaration" 
         :style "margin: 1rem 0; padding: 0.75rem; background: #fef3c7; border-left: 4px solid #f59e0b; border-radius: 6px;"
         :role "region"
         :aria-label "Kadi declaration"}
   [:label {:for "declare-kadi"
            :style "display: flex; align-items: center; gap: 0.75rem; cursor: pointer;"}
    [:input {:type "checkbox" 
             :name "declare-kadi" 
             :id "declare-kadi"
             :aria-describedby "kadi-explanation"
             :style "width: 1.3rem; height: 1.3rem; cursor: pointer;"}]
    [:div {:style "flex: 1;"}
     [:div {:style "font-weight: 600; color: #92400e; display: flex; align-items: center; gap: 0.5rem;"}
      [:span "🎯 Declare Kadi (Play to Finish)"]
      ;; Tooltip icon
      [:span {:style "font-size: 0.9rem; color: #d97706; cursor: help;"
              :title "Declaring Kadi signals your intent to finish the game. If you successfully play your last card(s), you WIN! However, if you play K/J/2/3 as your last card, or forget to declare Kadi, you'll become cardless instead."
              :aria-label "Information about Kadi declaration"}
       "ℹ️"]]
     ;; Explanation text
     [:p {:id "kadi-explanation"
          :style "margin: 0.25rem 0 0 0; font-size: 0.85rem; color: #78350f;"}
      "Required to win! Declare when playing your last card(s). Risk: K/J/2/3 as last card makes you cardless."]]]])
```

**Accessibility features**:
- ✅ `role="region"` and `aria-label` for the container
- ✅ `for` attribute links label to checkbox
- ✅ `aria-describedby` connects checkbox to explanation
- ✅ `title` attribute for tooltip
- ✅ Proper semantic HTML structure
- ✅ Clear, descriptive text

### 4.2 Add "Maintain Kadi" Checkbox for Voluntary Draws Only

**Show ONLY on regular draw button when player is in :kadi**:

```clojure
;; Inside draw button area (line ~454)
[:button.btn.btn-secondary {:type "submit" 
                            :formaction (str "/games/" (:short_code game) "/draw")}
 "Draw Card"]

;; NEW: Show maintain-kadi option below draw button
(when (= :kadi (:status my-player))
  [:div {:style "margin-top: 0.75rem; padding: 0.5rem; background: #fef3c7; border-radius: 4px;"
         :role "region"
         :aria-label "Kadi status options"}
   [:label {:for "maintain-kadi"
            :style "font-size: 0.9rem; display: flex; align-items: center; gap: 0.5rem; cursor: pointer;"}
    [:input {:type "checkbox" 
             :name "maintain-kadi" 
             :id "maintain-kadi"
             :checked true  ; Default to maintaining
             :aria-describedby "maintain-kadi-hint"
             :style "width: 1.1rem; height: 1.1rem;"}]
    [:span {:style "color: #92400e;"}
     "🎯 Stay in Kadi after drawing"]
    [:span {:id "maintain-kadi-hint"
            :style "font-size: 0.8rem; color: #78350f; margin-left: 0.5rem;"} 
     "(uncheck to exit Kadi state)"]]])
```

**IMPORTANT**: Do NOT show this checkbox for:
- Accept penalty (forced draw, auto-resets)
- Answer question (forced draw, auto-resets)

### 4.3 Add Kadi Status Banner (Visible to ALL Players) (Line ~320)

```clojure
(defn kadi-status-banner 
  "Display banner for players who declared Kadi - visible to ALL players."
  [state]
  (let [kadi-players (filter #(= :kadi (:status %)) (:players state))]
    (when (seq kadi-players)
      [:div {:class "mb-4"
             :role "status"
             :aria-live "polite"}
       (for [player kadi-players]
         (let [hand-count (count (get-in state [:zones :hands (:id player)]))]
           [:div {:key (:id player)
                  :class "bg-gradient-to-r from-yellow-50 to-amber-50 border-l-4 border-yellow-500 p-4 mb-2 rounded-r-lg shadow-sm"}
            [:div {:class "flex items-center"}
             [:span {:class "text-3xl mr-3" :aria-hidden "true"} "🎯"]
             [:div {:class "flex-1"}
              [:p {:class "font-bold text-yellow-900 text-lg"}
               (str (:name player) " declared Kadi!")]
              [:p {:class "text-sm text-yellow-700 mt-1"}
               "Playing to finish the game..."]]
             ;; Card count indicator
             [:div {:class "bg-yellow-200 text-yellow-900 font-bold px-3 py-2 rounded-full text-lg"
                    :aria-label (str (:name player) " has " hand-count " cards remaining")}
              (str hand-count " card" (when (not= 1 hand-count) "s") " left")]]]))])))
```

**Call in main game view before other banners**.

### 4.4 Add Game Finished Banner (Line ~200)

```clojure
(defn game-finished-banner 
  "Display winner announcement when game is finished."
  [game]
  (when (= :finished (get-in game [:state :status]))
    (let [winner-id (get-in game [:state :winner])
          winner (game/get-player (:state game) winner-id)
          finished-at (get-in game [:state :meta :updated-at])]
      [:div {:class "bg-gradient-to-r from-green-50 to-emerald-50 border-4 border-green-500 rounded-xl p-8 mb-6 text-center shadow-2xl"
             :role "alert"
             :aria-live "assertive"}
       [:div {:class "text-8xl mb-4"
              :aria-hidden "true"} "🎉"]
       [:h1 {:class "text-5xl font-bold text-green-800 mb-3"}
        "Game Over!"]
       [:div {:class "bg-white border-2 border-green-400 rounded-lg p-4 inline-block mb-4"}
        [:p {:class "text-3xl font-bold text-green-700"}
         (str "🏆 " (:name winner) " wins!")]]
       [:p {:class "text-gray-600 text-sm mt-4"}
        (str "Game finished at " finished-at)]
       
       ;; Back to games link
       [:div {:class "mt-6"}
        [:a {:href "/games"
             :class "inline-block px-6 py-3 bg-green-600 text-white font-semibold rounded-lg hover:bg-green-700 transition focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2"
             :aria-label "Return to games list"}
         "← Back to Games List"]]])))
```

**Call at top of game view**.

### 4.5 Disable Actions When Game Finished

```clojure
;; Wrap all action forms in condition
(when (not= :finished (get-in game [:state :status]))
  [:form {:method "post" :action ...}
   ;; ... form contents
   ])
```

### 4.6 Update Player Status Badge

```clojure
(defn player-status-badge 
  "Display visual badge for player status."
  [player]
  (case (:status player)
    :kadi 
    [:span {:class "inline-block px-3 py-1 bg-yellow-400 text-yellow-900 font-bold rounded-full text-sm"
            :role "status"
            :aria-label "Player declared Kadi"}
     "🎯 KADI"]
    
    :cardless 
    [:span {:class "inline-block px-2 py-1 bg-blue-200 text-blue-800 rounded-full text-xs"
            :role "status"
            :aria-label "Player is cardless"}
     "Cardless"]
    
    :selecting-suit 
    [:span {:class "inline-block px-2 py-1 bg-purple-200 text-purple-800 rounded-full text-xs"
            :role "status"
            :aria-label "Player is selecting suit"}
     "Selecting Suit"]
    
    nil))
```

---

## Phase 5: Testing Strategy

**File**: `test/kadi/game_test.clj`

### Test Suite (10 comprehensive tests)

1. ✅ **Valid single card finish**
2. ✅ **Valid combo finish**
3. ✅ **Invalid finish with King**
4. ✅ **Invalid finish with Jack**
5. ✅ **Invalid finish with 2**
6. ✅ **Invalid finish with 3**
7. ✅ **No Kadi declaration → Cardless**
8. ✅ **Voluntary draw + maintain → Stay Kadi**
9. ✅ **Voluntary draw + no maintain → Normal**
10. ✅ **Accept penalty in Kadi → Auto-reset to Normal**

### Example Tests

```clojure
(deftest kadi-finish-single-card-test
  (testing "Declare Kadi and finish with single valid card"
    (let [game (-> (make-test-game)
                   (assoc-in [:zones :played-stack] [{:suit :hearts :rank "5"}])
                   (assoc-in [:zones :hands 1] [{:suit :hearts :rank "6"}]))
          
          result (game/apply-action game {:type :play-cards
                                         :player-id 1
                                         :cards [{:suit :hearts :rank "6"}]
                                         :declare-kadi? true})]
      
      (is (= :finished (:status result)) "Game should be finished")
      (is (= 1 (:winner result)) "Player 1 should be winner")
      (is (empty? (game/get-hand result 1)) "Winner's hand should be empty"))))

(deftest kadi-invalid-finish-becomes-cardless-test
  (testing "Declare Kadi but play K/J/2/3 as last card → becomes CARDLESS"
    (let [game (-> (make-test-game)
                   (assoc-in [:zones :played-stack] [{:suit :hearts :rank "5"}])
                   (assoc-in [:zones :hands 1] [{:suit :hearts :rank "K"}]))
          
          result (game/apply-action game {:type :play-cards
                                         :player-id 1
                                         :cards [{:suit :hearts :rank "K"}]
                                         :declare-kadi? true})]
      
      (is (= :live (:status result)) "Game should still be live")
      (is (nil? (:winner result)) "No winner")
      (is (= :cardless (:status (game/get-player result 1))) 
          "Player should be CARDLESS (invalid finish)"))))

(deftest kadi-penalty-auto-resets-test
  (testing "Accept penalty while in Kadi → automatically exits Kadi"
    (let [game (-> (make-test-game)
                   (update-player 1 #(assoc % :status :kadi))
                   (update :effects conj {:type :penalty :penalty-type :two}))
          
          result (game/accept-penalty game 1)]
      
      (is (= :normal (:status (game/get-player result 1)))
          "Should automatically exit Kadi after accepting penalty"))))

(deftest kadi-voluntary-draw-maintain-test
  (testing "Draw voluntarily while in Kadi + maintain → stay Kadi"
    (let [game (-> (make-test-game)
                   (update-player 1 #(assoc % :status :kadi)))
          
          result (game/draw-card game 1 :maintain-kadi? true)]
      
      (is (= :kadi (:status (game/get-player result 1)))
          "Should maintain Kadi status"))))
```

---

## Phase 6: Event Tracking

### Event Data Structure

**`:play-cards` event**:
```clojure
{:player-id 1
 :cards [{:suit :hearts :rank "6"}]
 :declare-kadi? true              ; Track declaration
 :hand-size-before 3              ; Track hand size before play
 :timestamp "2026-02-08T..."}
```

**`:draw-card` event (voluntary only)**:
```clojure
{:player-id 1
 :maintain-kadi? true             ; Track if maintaining Kadi
 :timestamp "2026-02-08T..."}
```

**`:accept-penalty` and `:answer-question` events**:
```clojure
{:player-id 1
 :timestamp "2026-02-08T..."}
 ; No maintain-kadi? - always auto-resets
```

**Reasoning**:
- `declare-kadi?` - Essential for understanding player strategy
- `hand-size-before` - Helps identify finishing attempts vs normal plays
- `maintain-kadi?` - Tracks how players manage Kadi state (voluntary draws only)
- Other info can be inferred from game state

---

## Phase 7: Documentation

### 7.1 Create Feature Doc

**File**: `docs/kadi-finishing-feature.md` (NEW)

**Sections**:
- Overview
- Game Rules
  - Declaring Kadi
  - Winning conditions
  - Cardless vs Winning
  - Penalty handling
  - Strategic considerations
- UI Elements
  - Declare Kadi checkbox
  - Maintain Kadi checkbox (voluntary draws only)
  - Status banners
  - Winner announcement
- Technical Implementation
  - Game logic flow
  - State transitions
  - Event tracking
- Edge Cases
- Testing
- Code References
- Accessibility Features

### 7.2 Update Bootstrap Brief

**File**: `docs/CLOJURE_BOOTSTRAP_BRIEF.md`

**Add section**:
```markdown
### 2.8 Game Finishing (Kadi Declaration)

**Winning Condition**: Player must declare "Kadi" and successfully play their last card(s)

- **Declaration**: Optional checkbox when playing cards
- **Success**: Kadi declared + hand empties with valid cards → Game finished, player wins
- **Invalid Finish**: Kadi declared + K/J/2/3 as last card → Cardless (not win)
- **Forgot to Declare**: Hand empties without Kadi → Cardless (not win)
- **Voluntary Draw**: Player in Kadi can choose to maintain or drop status when drawing voluntarily
- **Involuntary Draw**: Accepting penalty or answering question automatically exits Kadi
- **Multiple Winners**: First player to finish wins, game ends

**Critical**: Cardless is NOT winning! Must declare Kadi to win.
```

---

## Files to Modify

| File | Purpose | Est. Lines |
|------|---------|------------|
| `src/kadi/schema.clj` | Add :kadi status, :winner field | +2 |
| `src/kadi/game.clj` | Core game logic for Kadi | +65 |
| `src/kadi/handlers.clj` | HTTP handlers, form parsing | +20 |
| `src/kadi/views.clj` | UI elements, banners, accessibility | +140 |
| `test/kadi/game_test.clj` | Comprehensive test suite | +200 |
| `docs/kadi-finishing-feature.md` | Feature documentation | +300 |
| `docs/CLOJURE_BOOTSTRAP_BRIEF.md` | Update game rules | +30 |

**Total**: ~760 lines

---

## Implementation Order

1. ✅ **Schema** → Safe, no side effects
2. ✅ **Tests** → TDD approach, define expected behavior
3. ✅ **Game Logic** → Pure functions, well-tested
4. ✅ **Handlers** → Wire up to game logic
5. ✅ **UI** → Visual elements with accessibility
6. ✅ **Documentation** → Capture implementation
7. ✅ **Manual Testing** → Validate with game 86AYWN

---

## Manual Testing Checklist (Game 86AYWN)

Current state: Mo has 1 card (6♣), top card K♣

**Test scenarios**:

- [ ] Mo plays 6♣ **WITH** Kadi → Wins game, winner banner appears
- [ ] Mo plays 6♣ **WITHOUT** Kadi → Becomes cardless, game continues
- [ ] Kadi banner shows Mo's status to all players
- [ ] Winner banner shows correct player name
- [ ] Game disables all actions when finished
- [ ] Tooltip on Kadi checkbox is clear and helpful
- [ ] Screen reader announces Kadi status
- [ ] Keyboard navigation works on all new checkboxes
- [ ] Maintain Kadi checkbox appears ONLY for voluntary draw
- [ ] Event history tracks `declare-kadi?` and `hand-size-before`
- [ ] Player in Kadi accepts penalty → automatically exits Kadi

---

## Accessibility Compliance

All new UI elements include:

- ✅ **ARIA labels** - `aria-label`, `aria-describedby`, `aria-live`
- ✅ **Roles** - `role="region"`, `role="status"`, `role="alert"`
- ✅ **Semantic HTML** - Proper `<label for="">` associations
- ✅ **Keyboard navigation** - Focus rings, tab order
- ✅ **Screen reader support** - Descriptive text, status announcements
- ✅ **Tooltips** - `title` attributes with clear explanations
- ✅ **Visual indicators** - High contrast, clear badges

---

## Risk Assessment

### Low Risk
- Schema changes (additive only)
- New UI elements (don't affect existing)
- Event tracking (backward compatible)

### Medium Risk
- `check-cardless` logic change (affects existing cardless behavior)
  - **Mitigation**: Comprehensive tests for all cardless scenarios
- `draw-card` parameter addition (changes function signature)
  - **Mitigation**: Optional parameter, backward compatible

### High Risk
- None identified (all changes are additive or well-tested)

---

## Summary

This plan implements a complete Kadi finishing system with:

- **Strategic gameplay** - Optional declaration with risk/reward
- **Clear winning condition** - Kadi + valid last card
- **Penalty handling** - Involuntary draws auto-reset Kadi
- **Voluntary draw choice** - Maintain or drop Kadi when drawing by choice
- **Accessible UI** - Full ARIA support, tooltips, keyboard navigation
- **Event tracking** - Comprehensive history for replays/analytics
- **Visual feedback** - Banners visible to all players
- **Robust testing** - 10 test cases covering all scenarios
- **Complete documentation** - Feature doc + updated brief

**Estimated effort**: ~760 lines of code/docs/tests  
**Risk level**: Low-Medium  
**Backward compatibility**: 100% (all changes additive)

---

## Ready for Implementation ✅

All requirements validated, edge cases considered, accessibility ensured, penalty handling verified.
