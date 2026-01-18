(ns kadi.handlers
  "HTTP request handlers."
  (:require [kadi.db :as db]
            [kadi.game :as game]
            [kadi.auth :as auth]
            [kadi.views :as views]
            [ring.util.response :as resp]))

;; =============================================================================
;; Helpers
;; =============================================================================

(defn- html-response [body]
  {:status 200
   :headers {"Content-Type" "text/html; charset=utf-8"}
   :body body})

(defn- redirect
  ([path] (resp/redirect path))
  ([path flash]
   (-> (resp/redirect path)
       (assoc :flash flash))))

(defn- with-session [response session]
  (assoc response :session session))

(defn- parse-form [request]
  (or (:form-params request)
      (:params request)
      {}))

(defn require-auth
  "Middleware helper - redirects to signin if not authenticated."
  [handler]
  (fn [request]
    (if (auth/authenticated? request)
      (handler request)
      (redirect "/auth/signin" {:type :error :message "Please sign in to continue"}))))

(defn- player-in-game?
  "Check if player is in the game."
  [player game]
  (some #(= (:id player) (:id %)) (get-in game [:state :players])))

(defn- check-game-status
  "Check that game exists and has expected status. Returns [game error] pair."
  [short-code expected-status]
  (if-let [game (db/get-game-by-code short-code)]
    (let [actual-status (game/game-status (:state game))]
      (if (= actual-status expected-status)
        [game nil]
        [game (str "Game is in " (name actual-status) " status, not " (name expected-status))]))
    [nil "Game not found"]))

;; =============================================================================
;; Auth Handlers
;; =============================================================================

(defn signin-page [request]
  (if (auth/authenticated? request)
    (redirect "/")
    (html-response
     (views/signin-page {:flash (:flash request)}))))

(defn send-signin-link [request]
  (let [params (parse-form request)
        email (get params "email")]
    (if (auth/valid-email? email)
      (let [token (auth/create-signin-token! email)]
        (auth/send-signin-email! {:email email :token token})
        (html-response
         (views/check-email-page {:email email})))
      (redirect "/auth/signin" {:type :error :message "Please enter a valid email address"}))))

(defn verify-signin [request]
  (let [token (get-in request [:path-params :token])]
    (if-let [player (auth/verify-token! token)]
      (do
        (println "Auth success - player:" player)
        (-> (redirect "/")
            (with-session {:player-id (:id player)})))
      (do
        (println "Auth failed - token:" token)
        (html-response
         (views/auth-error-page {:message "This sign-in link is invalid or has expired."}))))))

(defn signout [_request]
  (-> (redirect "/")
      (with-session nil)))

;; =============================================================================
;; Page Handlers
;; =============================================================================

(defn index [request]
  (if-let [player (auth/current-player request)]
    (let [games (db/get-player-games (:id player))]
      (html-response
       (views/home-page {:player player :games games})))
    (html-response
     (views/guest-home-page))))

;; =============================================================================
;; Game Handlers
;; =============================================================================

(defn list-games [request]
  (let [player (auth/current-player request)
        games (db/list-games :lobby)]
    (html-response
     (views/games-list-page {:player player :games games}))))

(defn create-game [request]
  (if-let [player (auth/current-player request)]
    (let [action {:player (select-keys player [:id :name])}
          result (db/create-game! action)]
      (redirect (str "/games/" (:short-code result))))
    (redirect "/auth/signin")))

(defn get-game [request]
  (let [short-code (get-in request [:path-params :code])
        player (auth/current-player request)]
    (if-let [game (db/get-game-by-code short-code)]
      (let [status (game/game-status (:state game))]
        (html-response
         (if (= :lobby status)
           (views/game-lobby-page {:player player :game game})
           (views/game-play-page {:player player :game game}))))
      (redirect "/games" {:type :error :message "Game not found"}))))

(defn get-players-fragment [request]
  (let [short-code (get-in request [:path-params :code])]
    (if-let [game (db/get-game-by-code short-code)]
      {:status 200
       :headers {"Content-Type" "text/html; charset=utf-8"}
       :body (views/players-list-fragment {:players (get-in game [:state :players])})}
      {:status 404 :body "Game not found"})))

(defn join-game [request]
  (if-let [player (auth/current-player request)]
    (let [short-code (get-in request [:path-params :code])
          game (db/get-game-by-code short-code)]
      (if game
        (let [already-joined? (game/get-player (:state game) (:id player))
              result (if already-joined?
                       {:ok (:state game)} ; Silent success if already joined
                       (game/join-player (:state game) player))]
          (if (:error result)
            (redirect (str "/games/" short-code) {:type :error :message (:error result)})
            (do
              (when-not already-joined?
                (let [action {:player (select-keys player [:id :name])
                              :timestamp (java.time.Instant/now)}]
                  (db/apply-and-persist! (:id game) :join-game action)
                  (db/add-player-to-game! (:id game) (:id player))))
              (redirect (str "/games/" short-code)))))
        (redirect "/games" {:type :error :message "Game not found"})))
    (redirect "/auth/signin")))

(defn join-page [request]
  "Display the join game page with code input."
  (let [player (auth/current-player request)
        flash (get-in request [:session :flash])]
    (html-response (views/join-page {:player player :flash flash}))))

(defn join-game-by-code [request]
  "Join a game by short code from the join form."
  (if-let [player (auth/current-player request)]
    (let [short-code (clojure.string/upper-case (clojure.string/trim (get-in request [:params :code] "")))
          game (when (seq short-code) (db/get-game-by-code short-code))]
      (if game
        (let [already-joined? (game/get-player (:state game) (:id player))
              result (if already-joined?
                       {:ok (:state game)}
                       (game/join-player (:state game) player))]
          (if (:error result)
            (redirect "/games/join" {:type :error :message (:error result)})
            (do
              (when-not already-joined?
                (let [action {:player (select-keys player [:id :name])
                              :timestamp (java.time.Instant/now)}]
                  (db/apply-and-persist! (:id game) :join-game action)
                  (db/add-player-to-game! (:id game) (:id player))))
              (redirect (str "/games/" short-code)))))
        (redirect "/games/join" {:type :error :message (if (seq short-code)
                                                          "Game not found"
                                                          "Please enter a game code")})))
    (redirect "/auth/signin")))

(defn start-game [request]
  (if-let [player (auth/current-player request)]
    (let [short-code (get-in request [:path-params :code])
          game (db/get-game-by-code short-code)]
      (if game
        (if-not (player-in-game? player game)
          (redirect "/games" {:type :error :message "You are not in this game"})
          (let [result (game/start-game-cmd (:state game))]
            (if (:error result)
              (redirect (str "/games/" short-code) {:type :error :message (:error result)})
              (do
                (db/apply-and-persist! (:id game) :start-game {:timestamp (java.time.Instant/now)})
                (redirect (str "/games/" short-code))))))
        (redirect "/games" {:type :error :message "Game not found"})))
    (redirect "/auth/signin")))

(defn play-cards [request]
  (if-let [player (auth/current-player request)]
    (let [short-code (get-in request [:path-params :code])
          [game error-msg] (check-game-status short-code :live)]
      (if error-msg
        (redirect "/games" {:type :error :message error-msg})
        (if-not (player-in-game? player game)
          (redirect "/games" {:type :error :message "You are not in this game"})
          (let [params (parse-form request)
                card-indices (mapv parse-long (if (sequential? (get params "cards[]"))
                                                (get params "cards[]")
                                                [(get params "cards[]")]))
                hand (game/get-hand (:state game) (:id player))
                cards (mapv #(get hand %) card-indices)
                result (game/play-cards-cmd (:state game) (:id player) cards)]
            (if (:error result)
              (redirect (str "/games/" short-code) {:type :error :message (:error result)})
              (do
                (db/apply-and-persist! (:id game) :cards-played {:player-id (:id player)
                                                                  :cards cards
                                                                  :timestamp (java.time.Instant/now)})
                (redirect (str "/games/" short-code))))))))
    (redirect "/auth/signin")))

(defn draw-card [request]
  (if-let [player (auth/current-player request)]
    (let [short-code (get-in request [:path-params :code])
          [game error-msg] (check-game-status short-code :live)]
      (if error-msg
        (redirect "/games" {:type :error :message error-msg})
        (if-not (player-in-game? player game)
          (redirect "/games" {:type :error :message "You are not in this game"})
          (let [result (game/draw-card-cmd (:state game) (:id player))]
            (if (:error result)
              (redirect (str "/games/" short-code) {:type :error :message (:error result)})
              (do
                (db/apply-and-persist! (:id game) :card-drawn {:player-id (:id player)
                                                                :timestamp (java.time.Instant/now)})
                (redirect (str "/games/" short-code))))))))
    (redirect "/auth/signin")))
