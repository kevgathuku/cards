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
      ["/:code" {:get (h/require-auth h/get-game)}]
      ["/:code/join" {:post (h/require-auth h/join-game)}]
      ["/:code/start" {:post (h/require-auth h/start-game)}]
      ["/:code/play" {:post (h/require-auth h/play-cards)}]
      ["/:code/draw" {:post (h/require-auth h/draw-card)}]
      ["/:code/players" {:get (h/require-auth h/get-players-fragment)}]]])
