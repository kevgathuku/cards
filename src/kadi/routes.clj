(ns kadi.routes
  "HTTP routes.
   All handlers are referenced via vars (#') so that reloading handler
   namespaces in the REPL takes effect without restarting the server."
  (:require [kadi.handlers :as h]))

(def routes
  [;; Home
   ["/" {:get #'h/index}]

   ;; Auth
   ["/auth"
    ["/signin" {:get #'h/signin-page}]
    ["/send-link" {:post #'h/send-signin-link}]
    ["/verify/:token" {:get #'h/verify-signin}]
    ["/signout" {:post #'h/signout}]]

   ;; Join game (separate to avoid conflict with /:code)
   ["/join" {:get (h/require-auth #'h/join-page)
             :post (h/require-auth #'h/join-game-by-code)}]

   ;; Games
   ["/games"
    ["" {:get #'h/list-games
         :post #'h/create-game}]
    ["/:code" {:get (h/require-auth #'h/get-game)}]
    ["/:code/join" {:post (h/require-auth #'h/join-game)}]
    ["/:code/start" {:post (h/require-auth #'h/start-game)}]
    ["/:code/play" {:post (h/require-auth #'h/play-cards)}]
    ["/:code/draw" {:post (h/require-auth #'h/draw-card)}]
    ["/:code/select-suit" {:post (h/require-auth #'h/select-suit)}]
    ["/:code/accept-penalty" {:post (h/require-auth #'h/accept-penalty)}]
    ["/:code/answer-question" {:post (h/require-auth #'h/answer-question)}]
    ["/:code/players" {:get (h/require-auth #'h/get-players-fragment)}]
    ["/:code/lobby-status" {:get (h/require-auth #'h/get-lobby-status-fragment)}]
    ["/:code/state" {:get (h/require-auth #'h/get-game-state-fragment)}]]])
