(ns kadi.server-test
  (:require [clojure.test :refer [deftest testing is]]
            [kadi.server :as server]))

(deftest derive-session-secret-test
  (testing "returns exactly 16 bytes for a 16-char key"
    (let [result (server/derive-session-secret "exactly16chars!!")]
      (is (some? result))
      (is (= 16 (count (seq result))))))

  (testing "returns exactly 16 bytes for a longer key (e.g. base64 output)"
    (let [result (server/derive-session-secret "aVeryLongSecretKeyGeneratedByOpenSSL123")]
      (is (some? result))
      (is (= 16 (count (seq result))))))

  (testing "returns nil for key shorter than 16 chars"
    (is (nil? (server/derive-session-secret "tooshort"))))

  (testing "returns nil for nil input"
    (is (nil? (server/derive-session-secret nil))))

  (testing "returns nil for empty string"
    (is (nil? (server/derive-session-secret ""))))

  (testing "same input always produces same output"
    (let [key "myProductionSecret123"
          a (server/derive-session-secret key)
          b (server/derive-session-secret key)]
      (is (java.util.Arrays/equals a b))))

  (testing "different inputs produce different outputs"
    (let [a (server/derive-session-secret "secretKeyAlpha!!")
          b (server/derive-session-secret "secretKeyBravo!!")]
      (is (not (java.util.Arrays/equals a b))))))
