(ns user
  "Development utilities for REPL session."
  (:require [kadi.db :as db]
            [kadi.server :as server]
            [kadi.game :as game]
            [kadi.cards :as cards]
            [kadi.validation :as validation]
            [clojure.pprint :refer [pprint]]))

(defn start-server
  "Start the development server and initialize the database."
  ([] (start-server 3000))
  ([port]
   (println "Initializing database...")
   (db/init!)
   (println (str "Starting Kadi server on port " port "..."))
   (server/start! {:port port})
   (println (str "✓ Kadi is running at http://localhost:" port))
   (println "\nDevelopment REPL started!")
   (println "Available functions: (start-server port), (stop-server), (restart-server)")))

(defn stop-server
  "Stop the development server."
  []
  (println "Stopping server...")
  (server/stop!)
  (println "✓ Server stopped"))

(defn restart-server
  "Restart the development server."
  ([] (restart-server 3000))
  ([port]
   (stop-server)
   (Thread/sleep 500)
   (start-server port)))

(defn help
  "Display available development commands."
  []
  (println "\n=== Kadi Development REPL ===")
  (println "Server Management:")
  (println "  (start-server)          - Start the server on port 3000")
  (println "  (start-server port)     - Start the server on specified port")
  (println "  (stop-server)           - Stop the server")
  (println "  (restart-server)        - Restart the server")
  (println "\nGame Exploration:")
  (println "  (game/new-game ...)     - Create a new game state")
  (println "  (pprint some-state)     - Pretty-print game state")
  (println "\nNamespaces loaded:")
  (println "  kadi.db, kadi.server, kadi.game, kadi.cards, kadi.validation")
  (println "\nType (help) to see this message again.\n"))

(println "\n=== Kadi Development REPL ===")
(println "Type (help) to see available commands")
(help)
