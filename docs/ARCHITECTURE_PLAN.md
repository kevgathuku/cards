# Kadi Architecture Plan: Hybrid HTMX + ClojureScript

**Date:** 2026-02-08  
**Status:** Proposed  
**Priority:** Real-time Multiplayer UX

---

## Executive Summary

**Decision: Hybrid Architecture**
- **HTMX** for simple pages (home, auth, lobby list, game lobby)
- **ClojureScript/Reagent** for live game (real-time multiplayer)
- **Mono-repo** with shared `.cljc` game logic
- **Single deployment** (one JAR with embedded ClojureScript assets)

**Timeline:** 2 weeks  
**Current State:** Server-rendered HTMX only, no real-time updates (manual refresh)  
**Goal:** Real-time multiplayer card game with smooth UX

---

## Current State Analysis

### What We Have
- **Backend:** Clojure (2,706 LOC)
  - Ring + Reitit HTTP server
  - SQLite database with event sourcing
  - Pure game logic (immutable state transitions)
- **Frontend:** Server-rendered Hiccup + HTMX (560 LOC)
  - 6 HTMX directives for partial updates
  - Manual "Refresh" buttons for state sync
- **Real-time:** **NONE** - no WebSockets yet
- **Mobile:** Responsive CSS only

### Critical Gap
The spec document (CLOJURE_BOOTSTRAP_BRIEF.md) explicitly requires:
- 15+ broadcast events (`:player-joined`, `:cards-played`, `:direction-changed`, etc.)
- WebSocket-based real-time updates
- Recommended: Sente (Clojure/ClojureScript WebSocket library)
- Recommended frontend: ClojureScript + Reagent

---

## Architecture Options Considered

### Option 1: Enhanced HTMX (HTMX + WebSockets)
**Approach:** Keep server-rendered HTML, add WebSocket for real-time fragment updates

**Pros:**
- Minimal code changes (~1 week)
- No build step
- Simple deployment

**Cons:**
- Non-standard pattern (few examples)
- HTML over wire is inefficient
- Limited animation capabilities
- Can't leverage client-side validation
- Harder debugging (DOM updates via WS)

**Verdict:** ❌ Rejected - doesn't meet real-time UX requirements

---

### Option 2: Pure ClojureScript (Full SPA)
**Approach:** Rewrite entire UI in ClojureScript/Reagent

**Pros:**
- Real-time first design
- Efficient EDN/JSON wire format
- Smooth animations
- Share validation logic client/server
- Optimistic updates

**Cons:**
- Major rewrite (throw away 560 LOC HTMX views)
- 2-3 weeks vs 1.5 weeks for hybrid
- Heavier bundle for simple pages

**Verdict:** ⚠️ Over-engineered for simple pages (auth, lobby)

---

### Option 3: Hybrid (HTMX + ClojureScript) ✅ SELECTED
**Approach:** HTMX for simple pages, ClojureScript for live game

**Architecture:**
```
Marketing / Lobby (HTMX)              Live Game (ClojureScript)
┌────────────────────┐                ┌──────────────────────┐
│ /                  │                │ /game/:code          │
│ /auth/signin       │                │                      │
│ /games (list)      │  Redirect →    │ Reagent + Sente      │
│ /games/:code/lobby │  on start      │ Real-time updates    │
│                    │                │ Smooth animations    │
│ Server-rendered    │                │ Client state         │
│ Fast, simple       │                │ Rich UX              │
└────────────────────┘                └──────────────────────┘
```

**Why This Wins:**
1. **Play to each stack's strengths**
   - HTMX: Simple forms, SEO, fast page loads
   - ClojureScript: Complex interactions, real-time, animations
2. **Progressive enhancement**
   - Only users who play games load ClojureScript bundle
   - Auth/lobby remain fast and JavaScript-free
3. **Faster time to market**
   - Don't rewrite working auth/lobby code
   - Focus effort on game UX where it matters
4. **Shared code**
   - `.cljc` files work in both Clojure and ClojureScript
   - Game logic, validation, card utilities shared
5. **Future-proof**
   - Clean API for mobile clients later
   - Can add React Native with shared logic

**Timeline:** 2 weeks (vs 3 weeks for pure ClojureScript)

---

## Detailed Design

### Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Server** | Clojure (JVM 11+) | Backend logic |
| **Web Framework** | Ring + Reitit | HTTP routing |
| **WebSocket** | Sente | Bidirectional communication |
| **Database** | SQLite + next.jdbc | Event sourcing persistence |
| **Server Views** | Hiccup + HTMX | Lobby, auth pages |
| **Client** | ClojureScript + Reagent | Live game UI |
| **State Management** | re-frame | Client-side game state |
| **Build Tool** | shadow-cljs | ClojureScript compilation |
| **Deployment** | Uberjar | Single JAR with embedded assets |

### File Organization

```
cards/
├── src/
│   ├── kadi/                    # Server (Clojure)
│   │   ├── game.cljc            # ← SHARED (server + client)
│   │   ├── cards.cljc           # ← SHARED
│   │   ├── validation.cljc      # ← SHARED
│   │   ├── schema.cljc          # ← SHARED
│   │   ├── db.clj               # Server only
│   │   ├── handlers.clj         # HTTP/WS handlers
│   │   ├── views.clj            # HTMX views (lobby, auth)
│   │   ├── auth.clj             # Authentication
│   │   └── server.clj           # Server startup
│   └── kadi_ui/                 # Client (ClojureScript)
│       ├── core.cljs            # Entry point
│       ├── game.cljs            # Game view components
│       ├── events.cljs          # re-frame events
│       ├── subs.cljs            # re-frame subscriptions
│       └── ws.cljs              # WebSocket setup
├── test/
│   └── kadi/
│       ├── game_test.clj        # Server tests (existing)
│       └── ui_test.cljs         # Client tests (optional)
├── resources/
│   └── public/
│       ├── js/
│       │   └── game.js          # Compiled ClojureScript
│       └── css/
│           └── game.css         # Shared styles
├── deps.edn                     # Clojure dependencies
├── shadow-cljs.edn              # ClojureScript build config
└── package.json                 # NPM deps (shadow-cljs)
```

**Key Points:**
- `.cljc` extension = works in both Clojure and ClojureScript
- Shared logic: game rules, card utilities, validation
- Server-only: database, handlers, HTMX views
- Client-only: Reagent components, re-frame state

### Routing Strategy

```clojure
;; src/kadi/handlers.clj
(defn routes []
  [["/" 
    {:get home-page}]                        ; HTMX
   
   ["/auth/signin" 
    {:get signin-page                        ; HTMX
     :post signin-post}]
   
   ["/games" 
    {:get games-list                         ; HTMX (list of lobbies)
     :post create-game}]
   
   ["/games/:code/lobby" 
    {:get game-lobby-htmx}]                  ; HTMX (waiting room)
   
   ["/game/:code" 
    {:get game-shell-html}]                  ; ClojureScript shell
   
   ["/api/ws" 
    {:get ws-handler}]                       ; Sente WebSocket
   
   ["/api/game/:code/action"
    {:post game-action-handler}]])           ; JSON API fallback
```

**User Journey:**
1. Visit `/` → HTMX home page
2. Click "Sign In" → `/auth/signin` → HTMX form
3. Create/join game → `/games/:code/lobby` → HTMX lobby
4. Click "Start Game" → Redirect to `/game/:code`
5. `/game/:code` loads ClojureScript app → connects to `/api/ws`
6. Real-time game begins

### WebSocket Protocol

**Server → Client Events:**
```clojure
[:game/state-updated {:state {...}}]        ; Full state sync
[:game/player-joined {:player {...}}]       ; Lobby event
[:game/cards-played {:player-id 1 :cards [...]}]
[:game/direction-changed {:direction :counter-clockwise}]
[:game/penalty-created {:penalty {...}}]
```

**Client → Server Actions:**
```clojure
[:game/play-cards {:cards [{:suit :hearts :rank "7"}]}]
[:game/draw-card {}]
[:game/accept-penalty {}]
[:game/select-suit {:suit :spades}]
[:game/answer-question {:cards [...]}]
```

**Event Flow:**
```
Client                Server               Other Clients
  |                     |                        |
  | :game/play-cards    |                        |
  |-------------------->|                        |
  |                     | Validate               |
  |                     | Apply action           |
  |                     | Persist event          |
  |                     | Update cache           |
  |                     |                        |
  | :game/state-updated |                        |
  |<--------------------|                        |
  |                     | :game/state-updated    |
  |                     |----------------------->|
  |                     |                        |
  | Render new state    |                   Render new state
```

---

## Implementation Plan

### Phase 1: WebSocket Infrastructure (2 days)

**Goal:** Add Sente WebSocket support, test with HTMX lobby

**Tasks:**
1. Add Sente dependency to `deps.edn`
2. Create WebSocket handler in `src/kadi/handlers.clj`
3. Set up connection routing in `src/kadi/server.clj`
4. Add lobby real-time updates (player joins) via WS
5. Test: HTMX lobby auto-refreshes when player joins

**Code:**
```clojure
;; deps.edn
{:deps {com.taoensso/sente {:mvn/version "1.19.2"}}}

;; src/kadi/server.clj
(defonce socket (atom nil))

(defn start-websocket! []
  (let [{:keys [ch-recv send-fn connected-uids
                ajax-post-fn ajax-get-or-ws-handshake-fn]}
        (sente/make-channel-socket-server!
          (sente/get-sch-adapter) 
          {:user-id-fn (fn [ring-req] 
                        (get-in ring-req [:session :player-id]))})]
    (reset! socket {:recv ch-recv
                    :send-fn send-fn
                    :connected-uids connected-uids
                    :ajax-post ajax-post-fn
                    :ajax-get ajax-get-or-ws-handshake-fn})
    socket))

;; src/kadi/handlers.clj
(defn ws-handler [request]
  (let [ws-fns @server/socket]
    ((:ajax-get-or-ws-handshake-fn ws-fns) request)))

(defn broadcast-to-game! [game-id event]
  (let [player-ids (db/get-game-player-ids game-id)
        send-fn (:send-fn @server/socket)]
    (doseq [pid player-ids]
      (send-fn pid event))))
```

**Testing:**
```bash
# Terminal 1: Start server
clj -M:repl
user=> (require '[kadi.core :as core])
user=> (core/-main)

# Terminal 2: Connect with wscat
npm install -g wscat
wscat -c ws://localhost:3000/api/ws

# Should see handshake
```

---

### Phase 2: ClojureScript Setup (1 day)

**Goal:** Set up shadow-cljs, create basic Reagent app

**Tasks:**
1. Add `shadow-cljs.edn` configuration
2. Add `package.json` for NPM dependencies
3. Create `src/kadi_ui/core.cljs` entry point
4. Create minimal Reagent component
5. Test: Load `/game/TEST` and see "Hello ClojureScript"

**Code:**
```clojure
;; shadow-cljs.edn
{:source-paths ["src"]
 :dependencies [[reagent "1.2.0"]
                [re-frame "1.4.3"]
                [com.taoensso/sente "1.19.2"]]
 :builds
 {:app
  {:target :browser
   :output-dir "resources/public/js"
   :asset-path "/js"
   :modules {:game {:init-fn kadi-ui.core/init!}}
   :devtools {:http-root "resources/public"
              :http-port 8021}}}}
```

```json
// package.json
{
  "name": "kadi-ui",
  "version": "1.0.0",
  "devDependencies": {
    "shadow-cljs": "^2.28.0"
  },
  "scripts": {
    "watch": "shadow-cljs watch app",
    "release": "shadow-cljs release app"
  }
}
```

```clojure
;; src/kadi_ui/core.cljs
(ns kadi-ui.core
  (:require [reagent.dom :as rdom]))

(defn app []
  [:div
   [:h1 "Kadi Game"]
   [:p "ClojureScript is working!"]])

(defn ^:export init! []
  (rdom/render [app] (js/document.getElementById "app")))
```

```clojure
;; src/kadi/handlers.clj - add route
(defn game-shell-html [request]
  {:status 200
   :headers {"Content-Type" "text/html; charset=utf-8"}
   :body "<!DOCTYPE html>
          <html>
          <head>
            <meta charset=\"utf-8\">
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
            <title>Kadi Game</title>
            <link rel=\"stylesheet\" href=\"/css/game.css\">
          </head>
          <body>
            <div id=\"app\"></div>
            <script src=\"/js/game.js\"></script>
          </body>
          </html>"})
```

**Setup:**
```bash
npm install
npm run watch  # Starts ClojureScript compiler
```

---

### Phase 3: Re-frame State Management (2 days)

**Goal:** Set up re-frame, connect to WebSocket, manage game state

**Tasks:**
1. Create re-frame app-db schema
2. Add WebSocket connection in `src/kadi_ui/ws.cljs`
3. Add events for WS messages
4. Add subscriptions for game state
5. Test: Connect to game, see state updates

**Code:**
```clojure
;; src/kadi_ui/ws.cljs
(ns kadi-ui.ws
  (:require [taoensso.sente :as sente]
            [re-frame.core :as rf]))

(defonce socket (atom nil))

(defn connect! []
  (let [{:keys [chsk ch-recv send-fn]}
        (sente/make-channel-socket-client!
          "/api/ws" 
          {:type :auto
           :packer :edn})]
    (reset! socket {:chsk chsk
                    :ch-recv ch-recv
                    :send-fn send-fn})
    
    ;; Route messages to re-frame
    (sente/start-client-chsk-router!
      ch-recv
      (fn [[event-type data]]
        (rf/dispatch [:ws/message event-type data])))))

(defn send! [event]
  ((:send-fn @socket) event))
```

```clojure
;; src/kadi_ui/events.cljs
(ns kadi-ui.events
  (:require [re-frame.core :as rf]
            [kadi-ui.ws :as ws]))

;; Initialize app state
(rf/reg-event-db
 :initialize
 (fn [_ _]
   {:game nil
    :player nil
    :pending-action nil}))

;; WebSocket message handler
(rf/reg-event-db
 :ws/message
 (fn [db [_ event-type data]]
   (case event-type
     :game/state-updated (assoc db :game data :pending-action nil)
     :game/player-joined (update-in db [:game :state :players] conj data)
     db)))

;; Player actions
(rf/reg-event-fx
 :play-cards
 (fn [{:keys [db]} [_ cards]]
   {:db (assoc db :pending-action {:type :play :cards cards})
    :dispatch [:ws/send [:game/play-cards {:cards cards}]]}))

(rf/reg-event-fx
 :ws/send
 (fn [_ [_ event]]
   (ws/send! event)
   {}))
```

```clojure
;; src/kadi_ui/subs.cljs
(ns kadi-ui.subs
  (:require [re-frame.core :as rf]
            [kadi.game :as game]))  ; ← Shared .cljc file!

(rf/reg-sub
 :game
 (fn [db _]
   (:game db)))

(rf/reg-sub
 :current-player
 (fn [db _]
   (:player db)))

(rf/reg-sub
 :can-play?
 :<- [:game]
 :<- [:current-player]
 (fn [[game player] [_ cards]]
   (when game
     (game/can-play? (:state game) player cards))))  ; ← Reuse server logic!
```

---

### Phase 4: Game UI Components (4 days)

**Goal:** Build Reagent components for live game

**Tasks:**
1. Player hand component (show cards, click to select)
2. Play area component (discard pile, deck, top card)
3. Other players component (show card counts, current turn)
4. Action buttons (play, draw, accept penalty, select suit)
5. Animations (card plays, direction changes)
6. Test: Full game playable

**Code:**
```clojure
;; src/kadi_ui/game.cljs
(ns kadi-ui.game
  (:require [reagent.core :as r]
            [re-frame.core :as rf]
            [kadi.cards :as cards]))  ; ← Shared .cljc file!

(defn card-view [{:keys [suit rank selected? on-click]}]
  [:div.card
   {:class (str "suit-" (name suit) 
                (when selected? " selected"))
    :on-click on-click}
   [:div.rank (str rank)]
   [:div.suit (cards/suit-symbol suit)]])  ; ← Reuse server code!

(defn player-hand []
  (let [game @(rf/subscribe [:game])
        player @(rf/subscribe [:current-player])
        selected (r/atom #{})]
    (fn []
      (let [hand (game/player-hand (:state game) (:id player))]
        [:div.hand
         [:h3 "Your Hand"]
         [:div.cards
          (for [card hand]
            ^{:key (str (:suit card) (:rank card))}
            [card-view 
             {:suit (:suit card)
              :rank (:rank card)
              :selected? (contains? @selected card)
              :on-click #(if (contains? @selected card)
                          (swap! selected disj card)
                          (swap! selected conj card))}])]
         [:button 
          {:disabled (empty? @selected)
           :on-click #(do (rf/dispatch [:play-cards @selected])
                         (reset! selected #{}))}
          "Play Selected Cards"]]))))

(defn play-area []
  (let [game @(rf/subscribe [:game])]
    [:div.play-area
     [:div.discard-pile
      [:h3 "Top Card"]
      (when-let [top-card (game/top-card (:state game))]
        [card-view {:suit (:suit top-card)
                    :rank (:rank top-card)}])]
     [:div.deck
      [:h3 "Deck"]
      [:div.card-back 
       (str (count (get-in game [:state :deck])) " cards")]]]))

(defn other-players []
  (let [game @(rf/subscribe [:game])
        current-player @(rf/subscribe [:current-player])]
    [:div.other-players
     [:h3 "Players"]
     (for [p (get-in game [:state :players])]
       (when (not= (:id p) (:id current-player))
         ^{:key (:id p)}
         [:div.player
          {:class (when (= (:id p) (game/current-player-id (:state game)))
                   "current-turn")}
          [:span.name (:name p)]
          [:span.card-count 
           (str (count (game/player-hand (:state game) (:id p))) " cards")]]))]))

(defn game-view []
  [:div.game-container
   [play-area]
   [other-players]
   [player-hand]])
```

**CSS (basic):**
```css
/* resources/public/css/game.css */
.game-container {
  display: flex;
  flex-direction: column;
  height: 100vh;
  padding: 1rem;
}

.play-area {
  display: flex;
  justify-content: space-around;
  padding: 2rem;
}

.hand {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: white;
  padding: 1rem;
  box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
}

.cards {
  display: flex;
  gap: 0.5rem;
  overflow-x: auto;
}

.card {
  width: 80px;
  height: 120px;
  border: 2px solid #333;
  border-radius: 8px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: transform 0.2s;
}

.card.selected {
  transform: translateY(-20px);
  border-color: #2563eb;
}

.suit-hearts, .suit-diamonds { color: red; }
.suit-clubs, .suit-spades { color: black; }

.current-turn {
  background: #fef3c7;
  font-weight: bold;
}
```

---

### Phase 5: Server Integration (2 days)

**Goal:** Connect ClojureScript actions to server handlers

**Tasks:**
1. Add server-side action handlers for WS events
2. Broadcast game state updates to all players
3. Handle edge cases (disconnection, reconnection)
4. Test: Multi-player game works across browser tabs

**Code:**
```clojure
;; src/kadi/handlers.clj
(defn handle-ws-event [event-map]
  (let [{:keys [event ?reply-fn uid]} event-map
        [event-type data] event]
    (case event-type
      :chsk/uidport-open
      (println "Client connected:" uid)
      
      :chsk/uidport-close
      (println "Client disconnected:" uid)
      
      :game/play-cards
      (let [player-id uid
            game-id (:game-id data)  ; Get from session/context
            action (merge data {:player-id player-id
                               :type :play-cards})]
        (try
          ;; Append event to log
          (db/append-event! game-id 
                           (str (random-uuid))
                           :play-cards
                           (java.time.Instant/now)
                           action)
          ;; Get fresh state
          (let [game (db/get-game-by-code (:short-code data))]
            ;; Broadcast to all players
            (broadcast-to-game! game-id [:game/state-updated game]))
          (catch Exception e
            (?reply-fn {:error (.getMessage e)}))))
      
      ;; Default
      (println "Unhandled event:" event-type))))

(defn start-ws-router! []
  (sente/start-server-chsk-router!
    (:ch-recv @server/socket)
    handle-ws-event))
```

---

### Phase 6: Polish & Testing (2 days)

**Goal:** Add animations, handle errors, test edge cases

**Tasks:**
1. Add CSS animations for card plays
2. Add loading states, error messages
3. Test disconnection/reconnection
4. Test across browsers (Chrome, Safari, Firefox)
5. Mobile responsive testing
6. Performance testing (10+ player game)

**Animations Example:**
```css
@keyframes card-play {
  0% { transform: translateY(0); }
  50% { transform: translateY(-100px) scale(1.2); }
  100% { transform: translateY(-200px) scale(0); }
}

.card.playing {
  animation: card-play 0.5s ease-out;
}
```

---

## Testing Strategy

### Unit Tests (Existing)
```bash
clj -M:test  # 71 tests, 310 assertions
```
All game logic tests already pass - no changes needed.

### Integration Tests (New)
```clojure
;; test/kadi/ws_test.clj
(deftest websocket-game-flow
  (testing "Full game over WebSocket"
    (let [client1 (connect-ws-client!)
          client2 (connect-ws-client!)
          game-code (create-game! client1)]
      (join-game! client2 game-code)
      (start-game! client1 game-code)
      
      ;; Play a card
      (send! client1 [:game/play-cards {:cards [...]}])
      
      ;; Both clients should receive update
      (is (= expected-state (receive! client1)))
      (is (= expected-state (receive! client2))))))
```

### Manual Testing Checklist
- [ ] Two browser tabs can play against each other
- [ ] Player joins are broadcast to lobby
- [ ] Card plays update all clients immediately
- [ ] Direction reversal shows correctly
- [ ] Penalty cards create penalties
- [ ] Ace suit selection works
- [ ] Question cards require answers
- [ ] Disconnection doesn't crash game
- [ ] Reconnection syncs state
- [ ] Mobile browser works (iOS Safari, Android Chrome)

---

## Deployment

### Development Workflow
```bash
# Terminal 1: Server REPL
clj -M:repl
user=> (require '[kadi.core :as core])
user=> (core/-main)
# Server at http://localhost:3000

# Terminal 2: ClojureScript auto-compile
npm run watch
# ClojureScript compiles to resources/public/js/game.js
# Changes reload automatically

# Visit:
# http://localhost:3000/              → HTMX home
# http://localhost:3000/games         → HTMX game list
# http://localhost:3000/game/ABC123   → ClojureScript game
```

### Production Build
```bash
# 1. Compile ClojureScript (release mode, optimized)
npm run release
# Output: resources/public/js/game.js (~300KB gzipped)

# 2. Build uberjar (includes compiled JS)
clj -T:build uber
# Output: target/kadi-standalone.jar

# 3. Deploy
scp target/kadi-standalone.jar server:/opt/kadi/
ssh server "systemctl restart kadi"
```

### Deployment Architecture (Production)
```
┌─────────────────────────────────────┐
│         Load Balancer / CDN         │
│      (Cloudflare, CloudFront)       │
└──────────────┬──────────────────────┘
               │
               ├─ /js/* → CDN cache (static)
               │
               └─ /* → App server
                      │
         ┌────────────▼────────────┐
         │   Kadi Server (JVM)     │
         │  - Ring HTTP            │
         │  - Sente WebSocket      │
         │  - SQLite database      │
         └─────────────────────────┘
```

**Why Single Server Works:**
- SQLite handles 1000s of reads/sec
- WebSocket connections: ~10K per server
- Stateless game logic (state in DB)
- Horizontal scale later: use PostgreSQL + Redis pub/sub

---

## Migration Checklist

### Pre-Migration
- [x] Current HTMX implementation works (71 tests passing)
- [x] Architecture plan documented (this file)
- [ ] Team agreement on hybrid approach
- [ ] Timeline confirmed (2 weeks)

### Phase 1: WebSocket (Day 1-2)
- [ ] Add Sente dependency
- [ ] Create WebSocket handlers
- [ ] Test connection with wscat
- [ ] Add lobby real-time updates (player joins)
- [ ] Test: HTMX lobby auto-updates

### Phase 2: ClojureScript Setup (Day 3)
- [ ] Install shadow-cljs and deps
- [ ] Create `shadow-cljs.edn` config
- [ ] Add basic Reagent app
- [ ] Verify compilation works
- [ ] Test: See "Hello ClojureScript" in browser

### Phase 3: Re-frame (Day 4-5)
- [ ] Set up app-db schema
- [ ] Add WebSocket connection
- [ ] Create events for WS messages
- [ ] Create subscriptions for game state
- [ ] Test: State updates from server

### Phase 4: Game UI (Day 6-9)
- [ ] Build player hand component
- [ ] Build play area component
- [ ] Build other players list
- [ ] Add action buttons
- [ ] Add card selection logic
- [ ] Test: Can play cards in UI

### Phase 5: Integration (Day 10-11)
- [ ] Connect actions to server
- [ ] Handle all game events
- [ ] Add error handling
- [ ] Test: Multi-tab gameplay

### Phase 6: Polish (Day 12-14)
- [ ] Add animations
- [ ] Mobile responsive testing
- [ ] Performance testing
- [ ] Production build
- [ ] Deploy to staging
- [ ] User acceptance testing

### Post-Launch
- [ ] Monitor WebSocket connections
- [ ] Track bundle size
- [ ] Gather user feedback
- [ ] Plan mobile native (if needed)

---

## Future Enhancements

### Near-term (1-3 months)
1. **Progressive Web App (PWA)**
   - Add manifest.json
   - Service worker for offline
   - "Add to home screen" prompt
   - **Effort:** 2-3 days

2. **Better Animations**
   - Card flip transitions
   - Direction change indicator
   - Penalty counter animation
   - **Effort:** 1 week

3. **Sound Effects**
   - Card play sound
   - Penalty sound
   - Turn notification
   - **Effort:** 2-3 days

4. **Game History**
   - View past games
   - Replay events
   - Statistics
   - **Effort:** 1 week

### Mid-term (3-6 months)
1. **Mobile Native (React Native)**
   - Reuse game logic (.cljc files)
   - Native UI components
   - Push notifications
   - **Effort:** 3-4 weeks

2. **Tournaments**
   - Multi-game brackets
   - Leaderboards
   - Rankings
   - **Effort:** 2-3 weeks

3. **AI Opponents**
   - Simple rule-based AI
   - Practice mode
   - **Effort:** 2 weeks

### Long-term (6-12 months)
1. **Scale to PostgreSQL**
   - If SQLite becomes bottleneck
   - Multi-server deployment
   - Redis pub/sub for WebSocket
   - **Effort:** 1-2 weeks

2. **iOS/Android Native Apps**
   - Swift/Kotlin clients
   - Same WebSocket API
   - Native features (camera for AR cards?)
   - **Effort:** 6-8 weeks per platform

---

## Risk Analysis

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| WebSocket scaling issues | Low | High | Start with single server, monitor connections |
| ClojureScript bundle too large | Medium | Medium | Code splitting, lazy loading |
| Mobile Safari WebSocket bugs | Medium | High | Test early, have fallback to polling |
| State sync bugs (race conditions) | Medium | High | Event sourcing provides audit trail |
| Database locks (SQLite) | Low | Medium | WAL mode enabled, quick transactions |

### Non-Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Timeline overrun | Medium | Medium | Phase 1-3 are MVP, can launch without polish |
| Team unfamiliar with re-frame | Low | Medium | Expert on team (confirmed) |
| Users prefer HTMX simplicity | Low | Low | Can keep `/classic` route as fallback |
| Mobile native becomes requirement | Medium | High | Architecture supports this (API-first) |

---

## Success Metrics

### Technical Metrics
- **WebSocket latency:** < 100ms round-trip
- **State sync accuracy:** 100% (no missed events)
- **Bundle size:** < 400KB gzipped
- **Page load time:** < 2s on 4G
- **Concurrent games:** 100+ on single server

### User Experience Metrics
- **Real-time feel:** Card plays appear instantly for all players
- **Animation smoothness:** 60 FPS on modern browsers
- **Mobile usability:** Touch-friendly card selection
- **Accessibility:** Keyboard navigation works

### Development Metrics
- **Code sharing:** > 50% of game logic shared (`.cljc`)
- **Test coverage:** Maintain 71+ tests
- **Build time:** < 30s for development, < 2min for production
- **Deployment time:** < 5min from commit to live

---

## Questions & Decisions

### Resolved
- ✅ Architecture: Hybrid HTMX + ClojureScript
- ✅ Repository: Mono-repo
- ✅ WebSocket library: Sente
- ✅ State management: re-frame
- ✅ Build tool: shadow-cljs
- ✅ Mobile strategy: Web first, native later if needed

### Pending
- ⏳ CSS framework: Tailwind vs custom CSS?
- ⏳ Animation library: CSS only vs react-spring?
- ⏳ Deployment target: DigitalOcean vs Heroku vs Fly.io?
- ⏳ Monitoring: LogRocket vs Sentry vs custom?
- ⏳ Analytics: Plausible vs Google Analytics vs none?

---

## References

- [CLOJURE_BOOTSTRAP_BRIEF.md](./CLOJURE_BOOTSTRAP_BRIEF.md) - Complete game specification
- [Sente Documentation](https://github.com/taoensso/sente) - WebSocket library
- [Re-frame Documentation](https://day8.github.io/re-frame/) - State management
- [Shadow-cljs User Guide](https://shadow-cljs.github.io/docs/UsersGuide.html) - Build tool
- [Reagent Documentation](https://reagent-project.github.io/) - React wrapper

---

## Appendix: Code Sharing Strategy

### Files to Convert to .cljc

These files should work in both Clojure (server) and ClojureScript (client):

```
src/kadi/game.clj     → src/kadi/game.cljc     ✅ Pure functions
src/kadi/cards.clj    → src/kadi/cards.cljc    ✅ Pure functions
src/kadi/validation.clj → src/kadi/validation.cljc ✅ Pure functions
src/kadi/schema.clj   → src/kadi/schema.cljc   ✅ Data schemas
```

**Changes needed:**
- Replace `java.time.Instant` with reader conditionals:
  ```clojure
  #?(:clj  (java.time.Instant/now)
     :cljs (js/Date.))
  ```
- Replace `java.util.UUID` with reader conditionals:
  ```clojure
  #?(:clj  (java.util.UUID/randomUUID)
     :cljs (random-uuid))
  ```

### Files That Stay .clj (Server Only)

```
src/kadi/db.clj        # JDBC, SQLite
src/kadi/handlers.clj  # Ring handlers
src/kadi/auth.clj      # Email tokens
src/kadi/views.clj     # HTMX Hiccup views
src/kadi/server.clj    # Server startup
```

### Files That Are .cljs (Client Only)

```
src/kadi_ui/core.cljs    # Entry point
src/kadi_ui/game.cljs    # Reagent components
src/kadi_ui/events.cljs  # Re-frame events
src/kadi_ui/subs.cljs    # Re-frame subscriptions
src/kadi_ui/ws.cljs      # WebSocket client
```

---

**Last Updated:** 2026-02-08  
**Status:** Ready for implementation  
**Next Step:** Team review and approval
