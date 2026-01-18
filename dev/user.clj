(ns user
  "Development utilities for REPL session."
  (:require [kadi.db :as db]
            [kadi.server :as server]))

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

(println "\n=== Kadi Development REPL ===")
(println "Type (start-server) to start the server")
(println "Type (stop-server) to stop the server")
(println "Type (restart-server) to restart the server\n")
