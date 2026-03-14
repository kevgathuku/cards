(ns kadi.handlers-test
  (:require [clojure.test :refer [deftest testing is]]
            [kadi.handlers :as handlers]
            [kadi.auth :as auth]
            [kadi.db :as db]
            [kadi.views :as views]))

(deftest list-games-shows-player-active-games
  (let [lobby-game {:id 1 :short_code "AAA111" :state {:status :lobby :players [{:id 10 :name "X"}]}}
        live-game {:id 2 :short_code "BBB222" :state {:status :live :players [{:id 1 :name "Creator"} {:id 2 :name "mo"}]}}
        finished-game {:id 3 :short_code "CCC333" :state {:status :finished :players [{:id 1 :name "Creator"} {:id 2 :name "mo"}]}}
        view-args (atom nil)]

    (testing "passes both lobby games and player's live games to the view"
      (with-redefs [auth/current-player (fn [_] {:id 2 :name "mo"})
                    db/list-games       (fn [status] (when (= :lobby status) [lobby-game]))
                    db/get-player-games (fn [pid] (when (= 2 pid) [live-game finished-game]))
                    views/games-list-page (fn [args] (reset! view-args args) "<html>")]
        (let [resp (handlers/list-games {:session {:player-id 2}})]
          (is (= 200 (:status resp)))
          ;; lobby games passed as :games
          (is (= [lobby-game] (:games @view-args)))
          ;; only live games passed as :my-games (not finished)
          (is (= [live-game] (:my-games @view-args))))))

    (testing "my-games is empty when player has no active games"
      (with-redefs [auth/current-player (fn [_] {:id 3 :name "new-player"})
                    db/list-games       (fn [_] [lobby-game])
                    db/get-player-games (fn [_] [])
                    views/games-list-page (fn [args] (reset! view-args args) "<html>")]
        (handlers/list-games {:session {:player-id 3}})
        (is (empty? (:my-games @view-args)))))))
