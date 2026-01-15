(ns kadi.routes
  "HTTP routes."
  (:require [kadi.handlers :as h]))

(def routes
  [["/" {:get h/index}]

   ["/api"
    ["/games"
     ["" {:get h/list-games
          :post h/create-game}]
     ["/:id" {:get h/get-game}]
     ["/:id/join" {:post h/join-game}]
     ["/:id/start" {:post h/start-game}]
     ["/:id/action" {:post h/game-action}]]

    ["/players"
     ["" {:post h/create-player}]
     ["/:id" {:get h/get-player}]]]])
