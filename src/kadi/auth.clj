(ns kadi.auth
  "Email-based authentication."
  (:require [kadi.db :as db]
            [kadi.schema :as schema]
            [malli.core :as m]
            [crypto.random :as random]
            [clojure.string :as str]
            [clojure.tools.logging :as log]
            [clj-http.client :as http]
            [jsonista.core :as json])
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
  "Check if an expiration timestamp (ISO-8601 string) is before the given instant."
  [expires-at now]
  (.isBefore (Instant/parse expires-at) now))

(defn- used?
  "Check if a used flag (integer) indicates the token has been consumed."
  [used-flag]
  (pos? (long (or used-flag 0))))

(defn- valid-token?
  "Check if a token record is valid (matches schema, not expired, not used)."
  [{:keys [expires_at used] :as token-record} now]
  (boolean
   (and token-record
        (m/validate schema/AuthToken token-record)
        (not (used? used))
        (not (expired? expires_at now)))))

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
    (when (valid-token? record (Instant/now))
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
  (let [api-key (System/getenv "RESEND_API_KEY")
        from-email (or (System/getenv "FROM_EMAIL") "onboarding@resend.dev")
        payload {:from (str "Kadi <" from-email ">")
                 :to to
                 :subject subject
                 :html html}]
    (when-not api-key
      (throw (ex-info "RESEND_API_KEY environment variable not set" {})))
    (let [resp (http/post "https://api.resend.com/emails"
                          {:headers {"Authorization" (str "Bearer " api-key)
                                     "Content-Type" "application/json"
                                     "User-Agent" "resend-lib/clojure-0.1.0"}
                           :body (.getBytes (json/write-value-as-string payload))})]
      (log/info "Resend response:" (:status resp) (:body resp)))))

(defn send-signin-email!
  "Send a sign-in email with the magic link.
   In dev mode, prints to console instead of sending."
  [{:keys [email token] :as request}]
  (when-not (m/validate schema/SigninEmailRequest request)
    (throw (ex-info "Invalid signin email request"
                    {:errors (m/explain schema/SigninEmailRequest request)})))
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

(defn valid-email?
  "Check if an email address is valid. Does not trim — callers should
   normalize input before validation so the validated value is what gets stored."
  [email]
  (boolean
   (and (string? email)
        (m/validate schema/Email email))))

;; =============================================================================
;; Session Helpers
;; =============================================================================

(defn current-player
  "Get the current player from the session."
  [request]
  (when-let [player-id (get-in request [:session :player-id])]
    (db/get-player player-id)))

(defn authenticated?
  "Check if the request has an authenticated session with a valid player."
  [request]
  (some? (current-player request)))
