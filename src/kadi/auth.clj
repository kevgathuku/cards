(ns kadi.auth
  "Email-based authentication."
  (:require [kadi.db :as db]
            [crypto.random :as random]
            [clojure.string :as str])
  (:import [java.time Instant Duration]))

(def ^:private token-expiry-minutes 30)

(def ^:private base-url
  (or (System/getenv "BASE_URL") "http://localhost:3000"))

(def ^:private dev-mode?
  (not= "production" (System/getenv "ENV")))

;; =============================================================================
;; Token Generation
;; =============================================================================

(defn generate-token
  "Generate a cryptographically secure URL-safe token."
  []
  (random/url-part 32))

(defn- expires-at
  "Calculate expiration time from now."
  []
  (-> (Instant/now)
      (.plus (Duration/ofMinutes token-expiry-minutes))
      str))

(defn create-signin-token!
  "Create a new sign-in token for the given email."
  [email]
  (let [token (generate-token)
        exp (expires-at)]
    (db/create-auth-token! {:email email
                            :token token
                            :expires-at exp})
    token))

;; =============================================================================
;; Token Validation
;; =============================================================================

(defn- token-expired?
  "Check if a token has expired."
  [token-record]
  (let [exp (Instant/parse (:expires_at token-record))]
    (.isBefore exp (Instant/now))))

(defn- token-used?
  "Check if a token has been used."
  [token-record]
  (= 1 (:used token-record)))

(defn valid-token?
  "Check if a token record is valid (not expired, not used)."
  [token-record]
  (and token-record
       (not (token-used? token-record))
       (not (token-expired? token-record))))

(defn verify-token!
  "Verify a token and return the player if valid.
   Creates a new player if one doesn't exist for the email.
   Returns nil if token is invalid."
  [token]
  (when-let [record (db/get-auth-token token)]
    (when (valid-token? record)
      (db/mark-token-used! token)
      (let [email (:email record)]
        (or (db/get-player-by-email email)
            (db/create-player! {:name (first (str/split email #"@"))
                                :email email}))))))

;; =============================================================================
;; Email Sending
;; =============================================================================

(defn signin-url
  "Generate the full sign-in URL for a token."
  [token]
  (str base-url "/auth/verify/" token))

(defn send-signin-email!
  "Send a sign-in email with the magic link.
   In dev mode, prints to console instead of sending."
  [{:keys [email token]}]
  (let [url (signin-url token)]
    (if dev-mode?
      (do
        (println)
        (println "========================================")
        (println "SIGN-IN LINK (dev mode)")
        (println "Email:" email)
        (println "URL:" url)
        (println "========================================")
        (println))
      ;; In production, integrate with email service
      ;; For now, just log - you'd replace this with actual email sending
      (do
        (println "TODO: Send email to" email "with link" url)
        ;; Example with postal:
        ;; (postal/send-message
        ;;   {:host (System/getenv "SMTP_HOST")}
        ;;   {:from "noreply@kadi.example.com"
        ;;    :to email
        ;;    :subject "Sign in to Kadi"
        ;;    :body (str "Click to sign in: " url "\n\nThis link expires in 30 minutes.")})
        ))))

;; =============================================================================
;; Email Validation
;; =============================================================================

(def ^:private email-pattern
  #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")

(defn valid-email?
  "Check if an email address is valid."
  [email]
  (and (string? email)
       (not (str/blank? email))
       (re-matches email-pattern (str/trim email))))

;; =============================================================================
;; Session Helpers
;; =============================================================================

(defn current-player
  "Get the current player from the session."
  [request]
  (when-let [player-id (get-in request [:session :player-id])]
    (db/get-player player-id)))

(defn authenticated?
  "Check if the request has an authenticated session."
  [request]
  (some? (get-in request [:session :player-id])))
