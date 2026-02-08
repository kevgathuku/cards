(ns kadi.views
  "HTML views using Hiccup."
  (:require [hiccup2.core :as h]
            [hiccup.util :refer [raw-string]]
            [kadi.cards :as cards]
            [kadi.game :as game]))

;; =============================================================================
;; Layout
;; =============================================================================

(defn layout
  "Base HTML layout with HTMX."
  [{:keys [title flash player]} & body]
  (str
   (h/html
    {:mode :html}
    (raw-string "<!DOCTYPE html>")
    [:html {:lang "en"}
     [:head
      [:meta {:charset "utf-8"}]
      [:meta {:name "viewport" :content "width=device-width, initial-scale=1"}]
      [:title (or title "Kadi")]
      ;; HTMX
      [:script {:src "https://unpkg.com/htmx.org@2.0.4"
                :integrity "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
                :crossorigin "anonymous"}]
      ;; Basic styles
      [:style
       "* { box-sizing: border-box; }
        body { font-family: system-ui, sans-serif; max-width: 800px; margin: 0 auto; padding: 1rem; }
        .flash { padding: 0.75rem 1rem; margin-bottom: 1rem; border-radius: 4px; }
        .flash-info { background: #e0f2fe; color: #0369a1; }
        .flash-error { background: #fee2e2; color: #dc2626; }
        .btn { display: inline-block; padding: 0.5rem 1rem; border: none; border-radius: 4px;
               cursor: pointer; text-decoration: none; font-size: 1rem; }
        .btn-primary { background: #2563eb; color: white; }
        .btn-primary:hover { background: #1d4ed8; }
        .btn-secondary { background: #e5e7eb; color: #374151; }
        .btn-secondary:hover { background: #d1d5db; }
        input[type=email], input[type=text] {
          padding: 0.5rem; border: 1px solid #d1d5db; border-radius: 4px; font-size: 1rem; width: 100%; }
        .form-group { margin-bottom: 1rem; }
        label { display: block; margin-bottom: 0.25rem; font-weight: 500; }
        .card { border: 1px solid #e5e7eb; border-radius: 8px; padding: 1.5rem; margin-bottom: 1rem; }
        .card h2 { margin-top: 0; }
        nav { display: flex; justify-content: space-between; align-items: center;
              padding: 1rem 0; border-bottom: 1px solid #e5e7eb; margin-bottom: 1.5rem; }
        nav a { text-decoration: none; color: #2563eb; }
        .game-list { list-style: none; padding: 0; }
        .game-list li { padding: 0.75rem; border: 1px solid #e5e7eb; border-radius: 4px; margin-bottom: 0.5rem; }
        .hand { display: flex; gap: 0.5rem; flex-wrap: wrap; }
        .playing-card { width: 60px; height: 84px; border: 2px solid #333; border-radius: 4px;
                        display: flex; align-items: center; justify-content: center;
                        background: white; cursor: pointer; font-size: 1.25rem; }
        .playing-card.selected, input:checked + .playing-card { border-color: #2563eb; background: #e0f2fe; }
        .playing-card.hearts, .playing-card.diamonds { color: #dc2626; }
        .playing-card.clubs, .playing-card.spades { color: #1f2937; }
         .htmx-indicator { display: none; }
         .htmx-request .htmx-indicator { display: inline; }
         .htmx-request.htmx-indicator { display: inline; }
         .loading { opacity: 0.5; }"]
      ;; Card selection order tracking
      [:script (raw-string
                "document.addEventListener('DOMContentLoaded', function() {
           // Track selected cards in order
           const selectedCards = [];
           
           function updateOrderedCardsInput() {
             const orderedInput = document.getElementById('ordered-cards');
             if (orderedInput) {
               orderedInput.value = selectedCards.join(',');
             }
           }
           
           // Listen for checkbox changes
           document.addEventListener('change', function(e) {
             if (e.target.classList.contains('card-checkbox')) {
               const cardId = e.target.dataset.cardId;
               
               if (e.target.checked) {
                 // Add to selection order if not already there
                 if (!selectedCards.includes(cardId)) {
                   selectedCards.push(cardId);
                 }
               } else {
                 // Remove from selection order
                 const index = selectedCards.indexOf(cardId);
                 if (index > -1) {
                   selectedCards.splice(index, 1);
                 }
               }
               
               updateOrderedCardsInput();
             }
           });
           
           // Clear selection order when form is submitted
           document.addEventListener('submit', function(e) {
             if (e.target.id === 'play-form') {
               // Form will submit with current ordered-cards value
             }
           });
         });")]]
     [:body
      [:nav
       [:div {:style "display: flex; gap: 1rem; align-items: center;"}
        [:a {:href "/"} [:strong "Kadi"]]
        (when player
          (list
           [:a {:href "/games"} "Games"]
           [:a {:href "/join"} "Join Game"]))]
       (if player
         [:div
          [:span (str "Hi, " (:name player) " ")]
          [:form {:method "post" :action "/auth/signout" :style "display:inline"}
           [:button.btn.btn-secondary {:type "submit"} "Sign out"]]]
         [:a.btn.btn-primary {:href "/auth/signin"} "Sign in"])]
      (when flash
        [:div.flash {:class (str "flash-" (name (:type flash)))}
         (:message flash)])
      body]])))

;; =============================================================================
;; Auth Pages
;; =============================================================================

(defn signin-page
  "Sign-in page with email form."
  [{:keys [flash]}]
  (layout {:title "Sign In" :flash flash}
          [:div.card
           [:h2 "Sign in to Kadi"]
           [:p "Enter your email and we'll send you a sign-in link."]
           [:form {:method "post" :action "/auth/send-link"}
            [:div.form-group
             [:label {:for "email"} "Email"]
             [:input {:type "email" :id "email" :name "email"
                      :placeholder "you@example.com" :required true :autofocus true}]]
            [:button.btn.btn-primary {:type "submit"} "Send sign-in link"]]]))

(defn check-email-page
  "Page shown after sending sign-in link."
  [{:keys [email]}]
  (layout {:title "Check Your Email"}
          [:div.card
           [:h2 "Check your email"]
           [:p (str "We sent a sign-in link to " [:strong email] ".")]
           [:p "Click the link in the email to sign in. The link expires in 30 minutes."]
           [:p [:a {:href "/auth/signin"} "Didn't receive it? Try again"]]]))

;; =============================================================================
;; Game Pages
;; =============================================================================

(defn join-page
  "Join game page with code input form."
  [{:keys [player flash]}]
  (layout {:title "Join Game" :player player :flash flash}
          [:div.card
           [:h2 "Join a Game"]
           [:p "Enter the 6-character game code to join."]
           [:form {:method "post" :action "/join"}
            [:div.form-group
             [:label {:for "code"} "Game Code"]
             [:input {:type "text" :id "code" :name "code"
                      :placeholder "e.g., ABC123"
                      :required true
                      :autofocus true
                      :maxlength "6"
                      :style "text-transform: uppercase;"}]]
            [:button.btn.btn-primary {:type "submit"} "Join Game"]]
           [:p {:style "margin-top: 1.5rem;"}
            [:a {:href "/games"} "← Browse available games instead"]]]))

(defn auth-error-page
  "Auth error page."
  [{:keys [message]}]
  (layout {:title "Sign In Error"}
          [:div.card
           [:h2 "Sign in failed"]
           [:p (or message "The sign-in link is invalid or has expired.")]
           [:p [:a.btn.btn-primary {:href "/auth/signin"} "Try again"]]]))

;; =============================================================================
;; Home / Lobby Pages
;; =============================================================================

(defn home-page
  "Home page for authenticated users."
  [{:keys [player games flash]}]
  (layout {:title "Kadi" :player player :flash flash}
          [:div.card
           [:h2 "Welcome to Kadi!"]
           [:p "A multiplayer card game."]
           [:div {:style "display: flex; gap: 1rem; align-items: center;"}
            [:form {:method "post" :action "/games"}
             [:button.btn.btn-primary {:type "submit"} "Create Game"]]
            [:a.btn.btn-secondary {:href "/games"} "Browse Games"]]]
          (when (seq games)
            [:div.card
             [:h3 "Your Active Games"]
             [:ul.game-list
              (for [game games]
                (let [status (get-in game [:state :status])
                      short-code (:short_code game)]
                  [:li
                   [:a {:href (str "/games/" short-code)}
                    (str "Game " short-code
                         (when status (str " - " (name status))))]]))]])))

(defn guest-home-page
  "Home page for guests."
  [{:keys [flash]}]
  (layout {:title "Kadi" :flash flash}
          [:div.card
           [:h2 "Welcome to Kadi!"]
           [:p "Kadi is a multiplayer card game popular in Kenya."]
           [:p "Sign in to create or join games."]
           [:a.btn.btn-primary {:href "/auth/signin"} "Sign in"]]))

;; =============================================================================
;; Fragments (for HTMX partial updates)
;; =============================================================================

(defn players-list-fragment
  "HTMX fragment for player list."
  [{:keys [players]}]
  (str
   (h/html
    [:ul.game-list
     (for [p players]
       [:li (:name p)])])))

(defn lobby-status-fragment
  "HTMX fragment for lobby status - includes player list and action buttons.
   This allows dynamic updates when players join without full page refresh."
  [{:keys [player game]}]
  (let [players (get-in game [:state :players])
        can-start? (>= (count players) 2)
        is-player? (some #(= (:id player) (:id %)) players)
        creator (first players)
        is-creator? (= (:id player) (:id creator))
        short-code (:short_code game)]
    (str
     (h/html
      [:div {:id "lobby-status"}
       [:div.card
        [:div {:style "display: flex; justify-content: space-between; align-items: center;"}
         [:h3 "Players in this game"]
         [:button.btn.btn-secondary
          {:hx-get (str "/games/" short-code "/lobby-status")
           :hx-target "#lobby-status"
           :hx-swap "outerHTML"}
          "Refresh"]]
        [:div {:id "player-list"}
         [:ul.game-list
          (for [p players]
            [:li (:name p)])]]]
       [:div.card
        (if is-player?
          (if (and can-start? is-creator?)
            [:form {:method "post" :action (str "/games/" short-code "/start")}
             [:button.btn.btn-primary {:type "submit"} "Start Game"]]
            [:p (if can-start?
                  "Waiting for the game creator to start..."
                  "Waiting for more players... (need at least 2)")])
          [:form {:method "post" :action (str "/games/" short-code "/join")}
           [:button.btn.btn-primary {:type "submit"} "Join Game"]])]]))))

;; =============================================================================
;; Game Pages
;; =============================================================================

(defn games-list-page
  "List of available games in lobby."
  [{:keys [player games flash]}]
  (layout {:title "Games" :player player :flash flash}
          [:div {:style "display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;"}
           [:h2 {:style "margin: 0;"} "Available Games"]
           [:a.btn.btn-primary {:href "/join"} "Join with Code"]]
          [:div.card
           [:form {:method "post" :action "/games" :style "margin-bottom: 1rem;"}
            [:button.btn.btn-primary {:type "submit"} "Create New Game"]]
           (if (seq games)
             [:ul.game-list
              (for [game games]
                [:li {:style "display: flex; justify-content: space-between; align-items: center;"}
                 [:span (str "Game " (:short_code game)
                             " (" (count (get-in game [:state :players])) " players)")]
                 [:a.btn.btn-secondary {:href (str "/games/" (:short_code game))} "Join"]])]
             [:p "No games available. Create one!"])]))

(defn game-lobby-page
  "Game lobby - waiting for players."
  [{:keys [player game flash]}]
  (layout {:title (str "Game " (:short_code game)) :player player :flash flash}
          [:div.card
           [:h2 "Game Lobby"]
           [:p "Share this code with friends to let them join:"]
           [:div {:style "background: #f3f4f6; padding: 1rem; border-radius: 4px; text-align: center; margin: 1rem 0;"}
            [:code {:style "font-size: 2rem; font-weight: bold; letter-spacing: 0.2em;"}
             (:short_code game)]]]
          ;; Use the fragment directly in the page so refresh updates everything
          (raw-string (lobby-status-fragment {:player player :game game}))))

;; =============================================================================
;; Game Play Page
;; =============================================================================

(defn card-class [card]
  (str "playing-card " (name (:suit card))))

(defn- suit-symbol
  "Get suit symbol for a given suit keyword."
  [suit]
  (case suit
    :hearts "♥"
    :diamonds "♦"
    :clubs "♣"
    :spades "♠"
    ""))

(defn card-display [card]
  (str (:rank card) (suit-symbol (:suit card))))

(defn- effect-banner
  "Render a banner for active game effects."
  [state {:keys [is-my-turn? current-player-name]}]
  (let [effects (:effects state)
        penalty (first (filter #(= :penalty (:type %)) effects))
        select-suit (first (filter #(= :select-suit (:type %)) effects))
        suit-selected (first (filter #(= :suit-selected (:type %)) effects))
        awaiting-answer (first (filter #(= :awaiting-answer (:type %)) effects))]
    (cond
      penalty
      (let [penalty-type (name (:penalty-type penalty))
            count (case (:penalty-type penalty) :two 2 :three 3 0)]
        [:div {:style "background: #fee2e2; border: 1px solid #dc2626; padding: 0.75rem 1rem; border-radius: 4px; margin-bottom: 0.5rem;"}
         (if is-my-turn?
           (str "⚠️ Penalty active (" count " cards)! Play " penalty-type " to block, or accept.")
           (str "⚠️ Penalty active (" count " cards). Waiting for " current-player-name "."))])

      select-suit
      [:div {:style "background: #fef3c7; border: 1px solid #fbbf24; padding: 0.75rem 1rem; border-radius: 4px; margin-bottom: 0.5rem;"}
       (if is-my-turn?
         "Ace played! Select a suit below."
         (str "Waiting for " current-player-name " to select a suit."))]

      suit-selected
      (let [required-suit (:suit suit-selected)
            suit-display (str (suit-symbol required-suit) " " (clojure.string/capitalize (name required-suit)))]
        [:div {:style "background: #dbeafe; border: 1px solid #3b82f6; padding: 0.75rem 1rem; border-radius: 4px; margin-bottom: 0.5rem;"}
         (str "🎴 Required suit: " suit-display)])

      awaiting-answer
      [:div {:style "background: #eff6ff; border: 1px solid #bfdbfe; padding: 0.75rem 1rem; border-radius: 4px; margin-bottom: 0.5rem;"}
       (if is-my-turn?
         "Question asked! You must draw to answer."
         (str "Question asked! Waiting for " current-player-name " to draw."))])))

(defn- suit-picker
  "Render suit selection buttons."
  [short-code]
  [:div {:style "margin-top: 1rem;"}
   [:p {:style "font-weight: 500;"} "Select a suit:"]
   [:div {:style "display: flex; gap: 0.5rem; margin-top: 0.5rem;"}
    (for [suit [:hearts :diamonds :clubs :spades]]
      [:form {:method "post" :action (str "/games/" short-code "/select-suit") :style "display: inline;"}
       [:input {:type "hidden" :name "suit" :value (name suit)}]
       [:button.btn.btn-secondary {:type "submit"}
        (str (suit-symbol suit) " " (clojure.string/capitalize (name suit)))]])]])

(defn game-play-content
  "Game play content fragment - used for initial render and HTMX polling updates.
   Returns HTML string with HTMX attributes for auto-refresh when not player's turn."
  [{:keys [player game]}]
  (let [state (:state game)
        current-player-idx (game/current-player-index state)
        players (:players state)
        current-player (get players current-player-idx)
        my-player (first (filter #(= (:id player) (:id %)) players))
        my-hand (when player (game/get-hand state (:id player)))
        is-my-turn? (= (:id player) (:id current-player))
        top-card (last (get-in state [:zones :played-stack]))
        deck-count (count (get-in state [:zones :deck]))
        direction (:direction state)
        has-select-suit? (game/has-effect? state :select-suit)
        has-penalty? (game/has-effect? state :penalty)
        has-awaiting-answer? (game/has-effect? state :awaiting-answer)
        penalty-effect (game/get-effect state :penalty)
        penalty-draw-count (when penalty-effect
                             (case (:penalty-type penalty-effect) :two 2 :three 3 0))
        game-finished? (= :finished (:status state))
        ;; Only poll when it's NOT my turn and game is NOT finished
        should-poll? (and (not is-my-turn?) (not game-finished?))]
    (str
     (h/html
      [:div {:id "game-content"
             :hx-get (when should-poll? (str "/games/" (:short_code game) "/state"))
             :hx-trigger (when should-poll? "every 2s")
             :hx-swap "outerHTML"}
       ;; Game finished banner
       (when game-finished?
         (let [winner-player (first (filter #(= (:id %) (:winner state)) players))]
           [:div {:style "background: linear-gradient(135deg, #10b981 0%, #059669 100%); border: 2px solid #047857; padding: 1.5rem; border-radius: 0.5rem; margin-bottom: 1rem; text-align: center;"}
            [:p {:style "font-size: 1.5rem; font-weight: 700; color: white; margin: 0 0 0.5rem 0;"}
             "🎉 Game Finished! 🎉"]
            [:p {:style "font-size: 1.125rem; color: #d1fae5; margin: 0 0 1rem 0;"}
             "Winner: " (:name winner-player)]
            [:a.btn.btn-secondary {:href "/games" :style "background: white; color: #047857; font-weight: 600;"}
             "Back to Games"]]))
       [:div.card
        [:h2 (str "Game: " (:short_code game))]
        (when direction
          [:p (str "Direction: " (name direction))])
        (effect-banner state {:is-my-turn? is-my-turn?
                              :current-player-name (:name current-player)})
        [:div {:style "display: flex; gap: 2rem;"}
         [:div
          [:h3 "Top Card"]
          (when top-card
            [:div {:class (card-class top-card)}
             (card-display top-card)])]
         [:div
          [:h3 "Deck"]
          [:p (str deck-count " cards")]]]]

       [:div.card
        [:h3 "Players"]
        [:ul.game-list
         (for [[idx p] (map-indexed vector players)]
           (let [is-current (= idx current-player-idx)
                 status-text (cond
                               (= :kadi (:status p)) " 🎯 KADI"
                               (= :cardless (:status p)) " ⚠️ CARDLESS (must draw)"
                               :else "")]
             [:li {:style (when is-current "font-weight: bold; background: #fef3c7;")}
              (str (:name p) " - " (count (game/get-hand state (:id p))) " cards"
                   (when is-current " (current turn)")
                   status-text)]))]]

       (when my-player
         [:div.card {:id "my-hand"}
          [:h3 (if is-my-turn? "Your Turn!" "Your Hand")]

          ;; Cardless warning message
          (when (and is-my-turn? (= :cardless (:status my-player)))
            [:div {:style "background: #fee2e2; border: 1px solid #dc2626; padding: 1rem; border-radius: 4px; margin-bottom: 1rem; color: #991b1b;"}
             [:p {:style "margin: 0; font-weight: bold;"}
              "⚠️ You are CARDLESS — you must draw a card first!"]])

          ;; Only show play form if NOT cardless
          (when (not= :cardless (:status my-player))
            [:form {:method "post" :action (str "/games/" (:short_code game) "/play")
                    :id "play-form"}
             ;; Hidden input to track ordered card IDs
             [:input {:type "hidden" :name "ordered-cards" :id "ordered-cards" :value ""}]
             [:div.hand
              (for [[idx card] (map-indexed vector my-hand)]
                [:label
                 [:input {:type "checkbox" :name "cards" :value (cards/card->id card)
                          :style "display: none"
                          :disabled (not is-my-turn?)
                          :data-card-id (cards/card->id card)
                          :class "card-checkbox"}]
                 [:div {:class (card-class card)}
                  (card-display card)]])]

             ;; Declare Kadi checkbox (only during normal play, not penalty/suit-select/question)
             (when (and is-my-turn?
                        (not has-select-suit?)
                        (not has-awaiting-answer?)
                        (not has-penalty?)
                        (not game-finished?))
               [:div {:style "background: #fef3c7; border: 1px solid #fbbf24; padding: 0.75rem; border-radius: 4px; margin-top: 1rem;"}
                [:label {:style "display: flex; align-items: center; gap: 0.5rem; cursor: pointer;"}
                 [:input {:type "checkbox" :name "declare-kadi" :id "declare-kadi"}]
                 [:span {:style "font-weight: 500;"}
                  "Declare Kadi (required to win)"]
                 [:span {:style "font-size: 0.875rem; color: #78350f;" :title "Check this box when playing your last card(s) to declare 'Kadi' and attempt to win. You MUST declare to finish the game."}
                  "ℹ️"]]])

             (when (and is-my-turn?
                        (not has-select-suit?)
                        (not has-awaiting-answer?)
                        (not game-finished?))
               (cond
                 ;; Penalty active: show play-to-block inside the play form
                 has-penalty?
                 [:div {:style "margin-top: 1rem; display: flex; gap: 0.5rem;"}
                  [:button.btn.btn-primary {:type "submit"} "Play to Block"]]

                 ;; Normal: just show play button (draw button is separate form below)
                 :else
                 [:div {:style "margin-top: 1rem;"}
                  [:button.btn.btn-primary {:type "submit"} "Play Selected"]]))])

          ;; Draw button - show for cardless OR normal voluntary draw
          ;; For cardless: only show if NOT facing penalty (penalty takes priority)
          ;; For normal: show if not in special states
          (when (and is-my-turn?
                     (not game-finished?))
            (cond
              ;; Cardless + Penalty: Don't show draw button (accept-penalty shown below)
              (and (= :cardless (:status my-player)) has-penalty?)
              nil

              ;; Cardless (no penalty): MUST draw, show only draw button
              (= :cardless (:status my-player))
              [:form {:method "post" :action (str "/games/" (:short_code game) "/draw") :id "draw-form" :style "margin-top: 0.5rem;"}
               [:button.btn.btn-primary {:type "submit"} "Draw Card (Required)"]]

              ;; Normal voluntary draw
              (and (not has-select-suit?)
                   (not has-awaiting-answer?)
                   (not has-penalty?))
              ;; Draw button form
              [:form {:method "post" :action (str "/games/" (:short_code game) "/draw") :id "draw-form" :style "margin-top: 0.5rem;"}
               ;; Maintain Kadi checkbox (only show if player is in :kadi status)
               (when (= :kadi (:status my-player))
                 [:div {:style "background: #fef3c7; border: 1px solid #fbbf24; padding: 0.75rem; border-radius: 4px; margin-bottom: 0.5rem;"}
                  [:label {:style "display: flex; align-items: center; gap: 0.5rem; cursor: pointer;"}
                   [:input {:type "checkbox" :name "maintain-kadi" :id "maintain-kadi" :checked true}]
                   [:span {:style "font-weight: 500; font-size: 0.875rem;"}
                    "Stay in Kadi after drawing"]
                   [:span {:style "font-size: 0.75rem; color: #78350f;" :title "Keep this checked to maintain your Kadi declaration after voluntary draw. Uncheck to exit Kadi status."}
                    "ℹ️"]]])
               [:button.btn.btn-secondary {:type "submit"} "Draw Card"]]))

          ;; Separate forms OUTSIDE the play form for special actions
          ;; Note: Penalty acceptance is available to ALL players (including cardless)
          (when (and is-my-turn?
                     (not game-finished?))
            (cond
              ;; Suit selection: only for non-cardless players
              (and has-select-suit? (not= :cardless (:status my-player)))
              (suit-picker (:short_code game))

              ;; Awaiting answer: only for non-cardless players
              (and has-awaiting-answer? (not= :cardless (:status my-player)))
              [:form {:method "post" :action (str "/games/" (:short_code game) "/answer-question")
                      :style "margin-top: 1rem;"}
               [:button.btn.btn-primary {:type "submit"} "Draw to Answer"]]

              ;; Penalty active: ALL players (including cardless) can accept
              has-penalty?
              [:form {:method "post" :action (str "/games/" (:short_code game) "/accept-penalty")
                      :style "margin-top: 1rem;"}
               [:button.btn.btn-secondary {:type "submit"}
                (str "Accept Penalty (Draw " penalty-draw-count ")")]]

              :else nil))])]))))

(defn game-play-page
  "Live game page - wraps game-play-content fragment in layout."
  [{:keys [player game flash]}]
  (layout {:title (str "Game " (:short_code game)) :player player :flash flash}
          (raw-string (game-play-content {:player player :game game}))))

