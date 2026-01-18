(ns kadi.server
  "HTTP server and WebSocket handling."
  (:require [ring.adapter.jetty :as jetty]
            [ring.middleware.params :refer [wrap-params]]
            [ring.middleware.keyword-params :refer [wrap-keyword-params]]
            [ring.middleware.session :refer [wrap-session]]
            [ring.middleware.session.cookie :refer [cookie-store]]
            [ring.middleware.flash :refer [wrap-flash]]
            [reitit.ring :as ring]
            [kadi.routes :as routes]))

(defonce ^:private server (atom nil))

;; Session secret key - in production, load from environment variable
(def ^:private session-secret
  (let [env-key (System/getenv "SESSION_SECRET")]
    (if (and env-key (>= (count env-key) 16))
      (.getBytes env-key)
      ;; Default key for development - 16 bytes
      (.getBytes "kadi-dev-secret!"))))

(defn app []
  (ring/ring-handler
   (ring/router routes/routes)
   (ring/routes
    (ring/create-default-handler
     {:not-found (constantly {:status 404
                              :headers {"Content-Type" "text/html"}
                              :body "<h1>Page not found</h1>"})}))))

(defn start!
  "Start the HTTP server."
  [{:keys [port] :or {port 3000}}]
  (when @server
    (.stop @server))
  (reset! server
          (jetty/run-jetty (-> (app)
                               wrap-keyword-params
                               wrap-params
                               wrap-flash
                               (wrap-session {:store (cookie-store {:key session-secret})
                                              :cookie-attrs {:http-only true
                                                             :same-site :lax
                                                             :max-age 604800}})) ;; 7 days
                           {:port port :join? false}))
  (println (str "Server started on http://localhost:" port)))

(defn stop!
  "Stop the HTTP server."
  []
  (when @server
    (.stop @server)
    (reset! server nil)
    (println "Server stopped")))
