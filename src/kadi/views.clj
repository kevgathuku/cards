(ns kadi.views
  "HTML views using Hiccup."
  (:require [hiccup2.core :as h]
            [hiccup.util :refer [raw-string]]))

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
        .playing-card.selected { border-color: #2563eb; background: #e0f2fe; }
        .playing-card.hearts, .playing-card.diamonds { color: #dc2626; }
        .playing-card.clubs, .playing-card.spades { color: #1f2937; }
        .htmx-indicator { display: none; }
        .htmx-request .htmx-indicator { display: inline; }
        .htmx-request.htmx-indicator { display: inline; }
        .loading { opacity: 0.5; }"]]
     [:body
      [:nav
       [:a {:href "/"} [:strong "Kadi"]]
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
  [{:keys [player games]}]
  (layout {:title "Kadi" :player player}
          [:div.card
           [:h2 "Welcome to Kadi!"]
           [:p "A multiplayer card game."]
           [:div {:style "display: flex; gap: 1rem;"}
            [:a.btn.btn-primary {:href "/games/new"} "Create Game"]
            [:a.btn.btn-secondary {:href "/games"} "Join Game"]]]
          (when (seq games)
            [:div.card
             [:h3 "Your Active Games"]
             [:ul.game-list
              (for [game games]
                [:li
                 [:a {:href (str "/games/" (:id game))}
                  (str "Game " (:short_code game) " - " (name (get-in game [:state :status])))]])]])))

(defn guest-home-page
  "Home page for guests."
  []
  (layout {:title "Kadi"}
          [:div.card
           [:h2 "Welcome to Kadi!"]
           [:p "Kadi is a multiplayer card game popular in Kenya."]
           [:p "Sign in to create or join games."]
           [:a.btn.btn-primary {:href "/auth/signin"} "Sign in to play"]]))

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

;; =============================================================================
;; Game Pages
;; =============================================================================

(defn games-list-page
  "List of available games in lobby."
  [{:keys [player games]}]
  (layout {:title "Games" :player player}
          [:div.card
           [:h2 "Available Games"]
           [:a.btn.btn-primary {:href "/games/new" :style "margin-bottom: 1rem; display: inline-block;"}
            "Create New Game"]
           (if (seq games)
             [:ul.game-list
              (for [game games]
                [:li {:style "display: flex; justify-content: space-between; align-items: center;"}
                 [:span (str "Game " (:short_code game)
                             " (" (count (get-in game [:state :players])) " players)")]
                 [:a.btn.btn-secondary {:href (str "/games/" (:id game) "/join")} "Join"]])]
             [:p "No games available. Create one!"])]))

(defn new-game-page
  "Create new game form."
  [{:keys [player]}]
  (layout {:title "New Game" :player player}
          [:div.card
           [:h2 "Create New Game"]
           [:form {:method "post" :action "/games"}
            [:button.btn.btn-primary {:type "submit"} "Create Game"]]]))

(defn game-lobby-page
  "Game lobby - waiting for players."
  [{:keys [player game]}]
  (let [players (get-in game [:state :players])
        can-start? (>= (count players) 2)
        is-player? (some #(= (:id player) (:id %)) players)]
    (layout {:title (str "Game " (:short_code game)) :player player}
            [:div.card
             [:h2 (str "Game: " (:short_code game))]
             [:p "Share this code with friends to let them join."]
             [:div {:id "player-list"
                    :hx-get (str "/games/" (:id game) "/players")
                    :hx-trigger "every 3s"}
              (players-list-fragment {:players players})]]
            [:div.card
             (if is-player?
               (if can-start?
                 [:form {:method "post" :action (str "/games/" (:id game) "/start")}
                  [:button.btn.btn-primary {:type "submit"} "Start Game"]]
                 [:p "Waiting for more players... (need at least 2)"])
               [:form {:method "post" :action (str "/games/" (:id game) "/join")}
                [:button.btn.btn-primary {:type "submit"} "Join Game"]])])))

;; =============================================================================
;; Game Play Page
;; =============================================================================

(defn card-class [card]
  (str "playing-card " (name (:suit card))))

(defn card-display [card]
  (let [suit-symbol (case (:suit card)
                      :hearts "♥"
                      :diamonds "♦"
                      :clubs "♣"
                      :spades "♠")]
    (str (:rank card) suit-symbol)))

(defn game-play-page
  "Live game page."
  [{:keys [player game]}]
  (let [state (:state game)
        current-player-idx (:current-player-index state)
        players (:players state)
        current-player (get players current-player-idx)
        my-player (first (filter #(= (:id player) (:id %)) players))
        is-my-turn? (= (:id player) (:id current-player))
        top-card (last (:played-stack state))]
    (layout {:title (str "Game " (:short_code game)) :player player}
            [:div.card
             [:h2 (str "Game: " (:short_code game))]
             [:p (str "Direction: " (name (:direction state)))]
             [:div {:style "display: flex; gap: 2rem;"}
              [:div
               [:h3 "Top Card"]
               (when top-card
                 [:div {:class (card-class top-card)}
                  (card-display top-card)])]
              [:div
               [:h3 "Deck"]
               [:p (str (count (:deck state)) " cards")]]]]

            [:div.card
             [:h3 "Players"]
             [:ul.game-list
              (for [[idx p] (map-indexed vector players)]
                [:li {:style (when (= idx current-player-idx) "font-weight: bold; background: #fef3c7;")}
                 (str (:name p) " - " (count (:hand p)) " cards"
                      (when (= idx current-player-idx) " (current turn)"))])]]

            (when my-player
              [:div.card {:id "my-hand"}
               [:h3 (if is-my-turn? "Your Turn!" "Your Hand")]
               [:form {:method "post" :action (str "/games/" (:id game) "/play")}
                [:div.hand
                 (for [[idx card] (map-indexed vector (:hand my-player))]
                   [:label
                    [:input {:type "checkbox" :name "cards[]" :value idx
                             :style "display: none"
                             :disabled (not is-my-turn?)}]
                    [:div {:class (card-class card)
                           :onclick "this.previousElementSibling.click(); this.classList.toggle('selected')"}
                     (card-display card)]])]
                (when is-my-turn?
                  [:div {:style "margin-top: 1rem; display: flex; gap: 0.5rem;"}
                   [:button.btn.btn-primary {:type "submit"} "Play Selected"]
                   [:button.btn.btn-secondary {:type "submit" :formaction (str "/games/" (:id game) "/draw")}
                    "Draw Card"]])]]))))

