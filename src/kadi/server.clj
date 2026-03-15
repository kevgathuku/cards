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

(defn derive-session-secret
  "Derive a 16-byte session secret for Ring cookie-store.
   Accepts any string >= 16 chars, hashed to exactly 16 bytes via MD5.
   Returns nil if input is nil or too short."
  [env-key]
  (when (and env-key (>= (count env-key) 16))
    (let [md (java.security.MessageDigest/getInstance "MD5")]
      (.digest md (.getBytes env-key)))))

;; Session secret key - must be exactly 16 bytes for Ring cookie-store.
;; In production (ENV=production), SESSION_SECRET must be set.
(def ^:private session-secret
  (let [env-key (System/getenv "SESSION_SECRET")
        production? (= "production" (System/getenv "ENV"))
        derived (derive-session-secret env-key)]
    (cond
      derived                derived
      (not production?)      (.getBytes "kadi-dev-secret!")
      :else                  (throw (ex-info "SESSION_SECRET must be set in production (16+ chars)"
                                             {:env "production"})))))

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
  [{:keys [port host] :or {port 3000 host "0.0.0.0"}}]
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
                           {:port port :host host :join? false}))
  (println (str "Server started on http://" host ":" port)))

(defn stop!
  "Stop the HTTP server."
  []
  (when @server
    (.stop @server)
    (reset! server nil)
    (println "Server stopped")))
