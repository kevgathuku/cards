(ns kadi.routes-auth-test
  (:require [clojure.test :refer [deftest testing is use-fixtures]]
            [kadi.handlers :as handlers]
            [kadi.db :as db]
            [kadi.game :as game]))

;; Ensure DB schema exists for tests
(defn setup-db [_]
  (db/init!))

(use-fixtures :once setup-db)

(defn make-game-with-code [code]
  (let [state (game/new-game {:id nil :short-code code})
        row   (db/create-game! state)]
    (assoc row :state state)))

(deftest protect-game-route-requires-auth
  (testing "unauthenticated access redirects to signin"
    (let [code "ABC123"
          _    (make-game-with-code code)
          req  {:request-method :get
                 :path-params {:code code}}
          resp ((handlers/require-auth handlers/get-game) req)]
      (is (= 302 (:status resp)))
      (is (= "/auth/signin" (get-in resp [:headers "Location"])))))

  (testing "authenticated access returns 200"
    (let [code "XYZ789"
          game (make-game-with-code code)
          player (db/create-player! {:name "Alice" :email "alice@example.com"})
          req {:request-method :get
               :path-params {:code code}
               :session {:player-id (:id player)}}
          resp ((handlers/require-auth handlers/get-game) req)]
      (is (= 200 (:status resp)))
      (is (string? (:body resp))))))
