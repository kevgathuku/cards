(ns kadi.server
  "HTTP server and WebSocket handling."
  (:require [ring.adapter.jetty :as jetty]
            [ring.middleware.params :refer [wrap-params]]
            [ring.middleware.keyword-params :refer [wrap-keyword-params]]
            [reitit.ring :as ring]
            [kadi.routes :as routes]))

(defonce ^:private server (atom nil))

(defn app []
  (ring/ring-handler
   (ring/router routes/routes)
   (ring/routes
    (ring/create-default-handler
     {:not-found (constantly {:status 404 :body "Not found"})}))))

(defn start!
  "Start the HTTP server."
  [{:keys [port] :or {port 3000}}]
  (when @server
    (.stop @server))
  (reset! server
          (jetty/run-jetty (-> (app)
                               wrap-keyword-params
                               wrap-params)
                           {:port port :join? false})))

(defn stop!
  "Stop the HTTP server."
  []
  (when @server
    (.stop @server)
    (reset! server nil)))
