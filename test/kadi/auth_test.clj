(ns kadi.auth-test
  (:require [clojure.test :refer [deftest testing is]]
            [kadi.auth :as auth]
            [kadi.db :as db]))

;; =============================================================================
;; Pure functions (no DB, no side effects)
;; =============================================================================

(deftest generate-token-test
  (testing "generates a non-empty string"
    (let [token (#'auth/generate-token)]
      (is (string? token))
      (is (pos? (count token)))))

  (testing "generates unique tokens"
    (let [tokens (repeatedly 10 #'auth/generate-token)]
      (is (= 10 (count (set tokens)))))))

(deftest token-expired?-test
  (testing "returns true for expired token"
    (is (true? (#'auth/token-expired? {:expires_at "2020-01-01T00:00:00Z" :used 0}))))

  (testing "returns false for future token"
    (is (false? (#'auth/token-expired? {:expires_at "2099-01-01T00:00:00Z" :used 0})))))

(deftest token-used?-test
  (testing "returns true when used=1"
    (is (true? (#'auth/token-used? {:used 1}))))

  (testing "returns true for any positive value"
    (is (true? (#'auth/token-used? {:used 2}))))

  (testing "returns false when used=0"
    (is (false? (#'auth/token-used? {:used 0}))))

  (testing "returns false when used key is missing"
    (is (false? (#'auth/token-used? {})))))

(deftest valid-token?-test
  (testing "returns true when not expired and not used"
    (is (true? (#'auth/valid-token? {:expires_at "2099-01-01T00:00:00Z" :used 0}))))

  (testing "returns false when expired"
    (is (false? (#'auth/valid-token? {:expires_at "2020-01-01T00:00:00Z" :used 0}))))

  (testing "returns false when used"
    (is (false? (#'auth/valid-token? {:expires_at "2099-01-01T00:00:00Z" :used 1}))))

  (testing "returns false when nil"
    (is (false? (#'auth/valid-token? nil)))))

(deftest valid-email?-test
  (testing "accepts valid emails"
    (is (true? (auth/valid-email? "test@example.com")))
    (is (true? (auth/valid-email? "user.name+tag@domain.co.uk"))))

  (testing "rejects invalid emails"
    (is (false? (auth/valid-email? "")))
    (is (false? (auth/valid-email? "not-an-email")))
    (is (false? (auth/valid-email? "@missing-local.com")))
    (is (false? (auth/valid-email? "missing-domain@")))
    (is (false? (auth/valid-email? nil)))
    (is (false? (auth/valid-email? 42)))))

(deftest email->display-name-test
  (testing "extracts local part before @"
    (is (= "alice" (#'auth/email->display-name "alice@example.com"))))

  (testing "preserves dots and plus tags"
    (is (= "user.name+tag" (#'auth/email->display-name "user.name+tag@domain.com")))))

(deftest signin-url-test
  (testing "generates URL with token"
    (let [url (#'auth/signin-url "abc123")]
      (is (string? url))
      (is (.endsWith url "/auth/verify/abc123")))))

;; =============================================================================
;; Side-effecting functions (DB stubbed with with-redefs)
;; =============================================================================

(deftest create-signin-token!-test
  (testing "creates token and persists via db"
    (let [created-args (atom nil)]
      (with-redefs [db/create-auth-token! (fn [args] (reset! created-args args))]
        (let [token (auth/create-signin-token! "test@example.com")]
          (is (string? token))
          (is (pos? (count token)))
          (is (= "test@example.com" (:email @created-args)))
          (is (string? (:token @created-args)))
          (is (string? (:expires-at @created-args))))))))

(deftest verify-token!-test
  (testing "returns player for valid unused token"
    (let [marked-used (atom false)]
      (with-redefs [db/get-auth-token    (fn [_] {:email "alice@test.com"
                                                  :expires_at "2099-01-01T00:00:00Z"
                                                  :used 0})
                    db/mark-token-used!  (fn [_] (reset! marked-used true))
                    db/get-player-by-email (fn [_] {:id 1 :name "alice"})]
        (let [result (auth/verify-token! "valid-token")]
          (is (= {:id 1 :name "alice"} result))
          (is (true? @marked-used))))))

  (testing "creates new player when none exists for email"
    (let [created-player (atom nil)]
      (with-redefs [db/get-auth-token      (fn [_] {:email "new@test.com"
                                                    :expires_at "2099-01-01T00:00:00Z"
                                                    :used 0})
                    db/mark-token-used!    (fn [_] nil)
                    db/get-player-by-email (fn [_] nil)
                    db/create-player!      (fn [args] (reset! created-player args)
                                             {:id 99 :name "new"})]
        (let [result (auth/verify-token! "new-token")]
          (is (= {:id 99 :name "new"} result))
          (is (= "new" (:name @created-player)))
          (is (= "new@test.com" (:email @created-player)))))))

  (testing "returns nil for unknown token"
    (with-redefs [db/get-auth-token (fn [_] nil)]
      (is (nil? (auth/verify-token! "unknown-token")))))

  (testing "returns nil for expired token"
    (with-redefs [db/get-auth-token (fn [_] {:email "x@test.com"
                                             :expires_at "2020-01-01T00:00:00Z"
                                             :used 0})]
      (is (nil? (auth/verify-token! "expired-token")))))

  (testing "returns nil for used token"
    (with-redefs [db/get-auth-token (fn [_] {:email "x@test.com"
                                             :expires_at "2099-01-01T00:00:00Z"
                                             :used 1})]
      (is (nil? (auth/verify-token! "used-token"))))))

(deftest send-signin-email!-test
  (testing "prints sign-in link in dev mode"
    (let [output (with-out-str
                   (auth/send-signin-email! {:email "dev@test.com" :token "tok123"}))]
      (is (.contains output "SIGN-IN LINK"))
      (is (.contains output "dev@test.com"))
      (is (.contains output "tok123")))))

(deftest current-player-test
  (testing "returns player when session has player-id"
    (with-redefs [db/get-player (fn [id] {:id id :name "Alice"})]
      (let [result (auth/current-player {:session {:player-id 42}})]
        (is (= {:id 42 :name "Alice"} result)))))

  (testing "returns nil when no session"
    (is (nil? (auth/current-player {}))))

  (testing "returns nil when no player-id in session"
    (is (nil? (auth/current-player {:session {}})))))

(deftest authenticated?-test
  (testing "true when session has player-id"
    (is (true? (auth/authenticated? {:session {:player-id 1}}))))

  (testing "false when no session"
    (is (false? (auth/authenticated? {}))))

  (testing "false when no player-id"
    (is (false? (auth/authenticated? {:session {}})))))
