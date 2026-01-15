(ns kadi.core
  "Kadi card game - main entry point."
  (:require [kadi.db :as db]
            [kadi.server :as server])
  (:gen-class))

(defn -main
  "Start the Kadi game server."
  [& args]
  (let [port (or (some-> (first args) parse-long) 3000)]
    (println "Initializing database...")
    (db/init!)
    (println (str "Starting Kadi server on port " port "..."))
    (server/start! {:port port})
    (println (str "Kadi is running at http://localhost:" port))))
