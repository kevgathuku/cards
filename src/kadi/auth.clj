(ns kadi.auth
  "Email-based authentication."
  (:require [kadi.db :as db]
            [crypto.random :as random]
            [clojure.string :as str]
            [clojure.tools.logging :as log]
            [clj-http.client :as http])
  (:import [java.time Instant Duration]))

(def ^:private token-expiry-minutes 30)
(def ^:private token-byte-length 32)

(defn- base-url []
  (or (System/getenv "BASE_URL") "http://localhost:3000"))

(defn- dev-mode? []
  (not= "production" (System/getenv "ENV")))

;; =============================================================================
;; Token Generation
;; =============================================================================

(defn- generate-token
  "Generate a cryptographically secure URL-safe token."
  []
  (random/url-part token-byte-length))

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

(defn- expired?
  "Check if an expiration timestamp (ISO-8601 string) is in the past."
  [expires-at]
  (.isBefore (Instant/parse expires-at) (Instant/now)))

(defn- used?
  "Check if a used flag (integer) indicates the token has been consumed."
  [used-flag]
  (pos? (long (or used-flag 0))))

(defn- valid-token?
  "Check if a token record is valid (not expired, not used)."
  [{:keys [expires_at used] :as token-record}]
  (boolean
   (and token-record
        (not (used? used))
        (not (expired? expires_at)))))

(defn- email->display-name
  "Derive a display name from an email address (local part before @)."
  [email]
  (first (str/split email #"@")))

(defn- find-or-create-player!
  "Look up a player by email, creating one if none exists."
  [email]
  (or (db/get-player-by-email email)
      (db/create-player! {:name (email->display-name email)
                          :email email})))

(defn verify-token!
  "Verify a token and return the player if valid.
   Creates a new player if one doesn't exist for the email.
   Returns nil if token is invalid."
  [token]
  (when-let [record (db/get-auth-token token)]
    (when (valid-token? record)
      (db/mark-token-used! token)
      (find-or-create-player! (:email record)))))

;; =============================================================================
;; Email Sending
;; =============================================================================

(defn- signin-url
  "Generate the full sign-in URL for a token."
  [token]
  (str (base-url) "/auth/verify/" token))

(defn- send-email!
  "Send an email using Resend API."
  [to subject html]
  (let [api-key (System/getenv "RESEND_API_KEY")]
    (when-not api-key
      (throw (ex-info "RESEND_API_KEY environment variable not set" {})))
    (http/post "https://api.resend.com/emails"
               {:form-params {:from "Kadi <kevgathuku@gmail.com>"
                              :to to
                              :subject subject
                              :html html}
                :basic-auth [api-key ""]})))

(defn send-signin-email!
  "Send a sign-in email with the magic link.
   In dev mode, prints to console instead of sending."
  [{:keys [email token]}]
  (let [url (signin-url token)
        is-dev (dev-mode?)]
    (log/info "Sending sign-in email to" email "dev-mode?" is-dev)
    (if is-dev
      (printf "\n== SIGN-IN LINK (dev) ==\nEmail: %s\nURL:   %s\n\n" email url)
      (let [html (str "<p>Click the link below to sign in to Kadi:</p>"
                      "<p><a href=\"" url "\">" url "</a></p>"
                      "<p>This link expires in 30 minutes.</p>")]
        (try
          (send-email! email "Sign in to Kadi" html)
          (log/info "Sign-in email sent to" email)
          (catch Exception e
            (log/error e "Failed to send email to" email)))))))

;; =============================================================================
;; Email Validation
;; =============================================================================

(def ^:private email-pattern
  #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")

(defn valid-email?
  "Check if an email address is valid. Does not trim — callers should
   normalize input before validation so the validated value is what gets stored."
  [email]
  (boolean
   (and (string? email)
        (re-matches email-pattern email))))

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
