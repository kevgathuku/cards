(ns kadi.handlers-test
  (:require [clojure.test :refer [deftest testing is]]
            [kadi.handlers :as handlers]
            [kadi.auth :as auth]
            [kadi.db :as db]
            [kadi.views :as views]))

(deftest list-games-shows-only-player-games
  (let [live-game {:id 2 :short_code "BBB222" :state {:status :live :players [{:id 1 :name "Creator"} {:id 2 :name "mo"}]}}
        lobby-game {:id 4 :short_code "DDD444" :state {:status :lobby :players [{:id 2 :name "mo"}]}}
        finished-game {:id 3 :short_code "CCC333" :state {:status :finished :players [{:id 1 :name "Creator"} {:id 2 :name "mo"}]}}
        view-args (atom nil)]

    (testing "splits player games into active and finished"
      (with-redefs [auth/current-player (fn [_] {:id 2 :name "mo"})
                    db/get-player-games (fn [pid] (when (= 2 pid) [live-game lobby-game finished-game]))
                    views/games-list-page (fn [args] (reset! view-args args) "<html>")]
        (let [resp (handlers/list-games {:session {:player-id 2}})]
          (is (= 200 (:status resp)))
          ;; active games (lobby + live) passed as :games
          (is (= [live-game lobby-game] (:games @view-args)))
          ;; finished games passed as :finished-games
          (is (= [finished-game] (:finished-games @view-args))))))

    (testing "empty when player has no games"
      (with-redefs [auth/current-player (fn [_] {:id 3 :name "new-player"})
                    db/get-player-games (fn [_] [])
                    views/games-list-page (fn [args] (reset! view-args args) "<html>")]
        (handlers/list-games {:session {:player-id 3}})
        (is (empty? (:games @view-args)))
        (is (empty? (:finished-games @view-args)))))))
