(ns kadi.routes
  "HTTP routes."
  (:require [kadi.handlers :as h]))

(def routes
  [;; Home
   ["/" {:get h/index}]

   ;; Auth
   ["/auth"
    ["/signin" {:get h/signin-page}]
    ["/send-link" {:post h/send-signin-link}]
    ["/verify/:token" {:get h/verify-signin}]
    ["/signout" {:post h/signout}]]

   ;; Games
   ["/games"
    ["" {:get h/list-games
         :post h/create-game}]
    ["/:id" {:get h/get-game}]
    ["/:id/join" {:post h/join-game}]
    ["/:id/start" {:post h/start-game}]
    ["/:id/play" {:post h/play-cards}]
    ["/:id/draw" {:post h/draw-card}]
    ["/:id/players" {:get h/get-players-fragment}]]])
