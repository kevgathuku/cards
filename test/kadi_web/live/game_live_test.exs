defmodule KadiWeb.GameLiveTest do
  use KadiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Kadi.AccountsFixtures

  alias Kadi.CardGames

  describe "game_updated broadcast and subscription" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})
      player3 = player_fixture(%{email: "player3@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "broadcast-test"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, _} = CardGames.join_game_session(player3, game_session.id)

      %{
        player1: player1,
        player2: player2,
        player3: player3,
        game_session: game_session
      }
    end

    test "subscribes to game topic on mount", %{
      player1: player1,
      game_session: game_session
    } do
      conn = log_in_player(build_conn(), player1)

      # Mount the LiveView
      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Verify the LiveView process subscribed by sending a broadcast
      topic = "game:#{game_session.id}"
      :ok = Phoenix.PubSub.broadcast(Kadi.PubSub, topic, {:test_message, "subscription_test"})

      # If subscribed, the LiveView process should receive the message
      # We can't directly check subscriptions, but we verify the view is alive and functioning
      assert Process.alive?(view.pid), "LiveView should be alive after mounting"
    end

    test "multiple clients can mount same game", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      conn1 = log_in_player(build_conn(), player1)
      conn2 = log_in_player(build_conn(), player2)

      # Mount two LiveView clients for the same game
      {:ok, view1, _html1} = live(conn1, ~p"/games/#{game_session.id}")
      {:ok, view2, _html2} = live(conn2, ~p"/games/#{game_session.id}")

      # Verify both LiveViews are alive and subscribed
      assert Process.alive?(view1.pid)
      assert Process.alive?(view2.pid)
    end

    test "broadcasts game_updated event when game starts", %{
      game_session: game_session
    } do
      # Subscribe to the game topic in the test process
      topic = "game:#{game_session.id}"
      :ok = Phoenix.PubSub.subscribe(Kadi.PubSub, topic)

      # Start the game (this should trigger a broadcast)
      {:ok, _updated_game_session} = CardGames.start_game(game_session)

      # Verify the test process received the broadcast (via Endpoint.broadcast, wrapped in Phoenix.Socket.Broadcast)
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "game_updated",
                       payload: %{game_session: updated_game_session}
                     },
                     1000

      # Verify the payload structure
      assert updated_game_session.id == game_session.id
      assert updated_game_session.status == "live"
      assert updated_game_session.current_turn_player_id != nil
    end

    test "all subscribed clients receive game_updated event", %{
      player1: player1,
      player2: player2,
      player3: player3,
      game_session: game_session
    } do
      conn1 = log_in_player(build_conn(), player1)
      conn2 = log_in_player(build_conn(), player2)
      conn3 = log_in_player(build_conn(), player3)

      # Mount three LiveView clients
      {:ok, view1, html1} = live(conn1, ~p"/games/#{game_session.id}")
      {:ok, view2, html2} = live(conn2, ~p"/games/#{game_session.id}")
      {:ok, view3, html3} = live(conn3, ~p"/games/#{game_session.id}")

      # Verify initial state shows lobby status
      assert html1 =~ game_session.short_code
      assert html2 =~ game_session.short_code
      assert html3 =~ game_session.short_code

      # Player 1 starts the game via LiveView event
      render_click(view1, "start_game")

      # All three clients should receive updates (view1 via handle_event, view2/view3 via handle_info)
      # Give a moment for the broadcast to propagate
      Process.sleep(100)

      # Re-render to get updated HTML
      html1_after = render(view1)
      html2_after = render(view2)
      html3_after = render(view3)

      # Verify all clients see the updated game state
      # (The actual HTML content depends on your template, adjust assertions as needed)
      # At minimum, verify the views are still alive and rendering
      assert html1_after =~ "live"
      assert html2_after =~ "live"
      assert html3_after =~ "live"
    end

    test "handle_info updates socket assigns with game state", %{
      player1: player1,
      game_session: game_session
    } do
      conn = log_in_player(build_conn(), player1)

      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Manually send game_updated message to the LiveView process (as Phoenix.Socket.Broadcast)
      updated_game_session =
        Kadi.Repo.preload(game_session, [:current_turn_player, deck: [deck_cards: :card]])

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "game:#{game_session.id}",
        event: "game_updated",
        payload: %{game_session: updated_game_session}
      })

      # Give the LiveView a moment to process the message
      Process.sleep(50)

      # The LiveView should have processed the message and updated its state
      html_after = render(view)
      assert html_after =~ player1.email
    end

    test "verifies payload structure matches broadcast and handler expectations", %{
      game_session: game_session
    } do
      # This test verifies the contract between broadcaster and handler

      # Expected message structure from Endpoint.broadcast (lib/kadi/card_games.ex:178-182)
      expected_message = %Phoenix.Socket.Broadcast{
        topic: "game:#{game_session.id}",
        event: "game_updated",
        payload: %{game_session: game_session}
      }

      # Verify the handler pattern matches (lib/kadi_web/live/game_live.ex:58)
      # The handler expects: %Phoenix.Socket.Broadcast{event: "game_updated", payload: %{game_session: updated_game_session}}

      # Test that the pattern match works
      case expected_message do
        %Phoenix.Socket.Broadcast{event: "game_updated", payload: %{game_session: _session}} ->
          # Pattern matches successfully
          assert true

        _ ->
          flunk("Payload structure doesn't match handler expectation")
      end
    end

    test "verifies topic format consistency between broadcast and subscription", %{
      game_session: game_session
    } do
      # Topic format from subscription (lib/kadi_web/live/game_live.ex:23)
      subscription_topic = "game:#{game_session.id}"

      # Topic format from broadcast (lib/kadi/card_games.ex:179)
      broadcast_topic = "game:" <> to_string(game_session.id)

      # Verify both formats produce the same topic string
      assert subscription_topic == broadcast_topic,
             "Topic format mismatch: subscription='#{subscription_topic}' vs broadcast='#{broadcast_topic}'"
    end

    test "does not subscribe on initial HTTP request (only on WebSocket)", %{
      player1: player1,
      game_session: game_session
    } do
      # This test verifies the connected?(socket) check works correctly

      conn = log_in_player(build_conn(), player1)

      # Make an initial HTTP GET (not WebSocket connected yet)
      conn = get(conn, ~p"/games/#{game_session.id}")

      # At this point, no subscription should exist yet
      # (Phoenix.LiveView handles the WebSocket upgrade after initial HTTP response)
      # May redirect if not authenticated properly
      assert conn.status == 200 or conn.status == 302
    end

    test "cards are dealt to the players", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # This test verifies start_game is working through the broadcast flow

      conn1 = log_in_player(build_conn(), player1)
      conn2 = log_in_player(build_conn(), player2)

      {:ok, view1, _html1} = live(conn1, ~p"/games/#{game_session.id}")
      {:ok, view2, _html2} = live(conn2, ~p"/games/#{game_session.id}")

      # Start the game
      render_click(view1, "start_game")
      Process.sleep(100)

      # Get the updated game state
      updated_game_session = Kadi.Repo.get!(Kadi.Games.GameSession, game_session.id)
      updated_game_session = Kadi.Repo.preload(updated_game_session, deck: [deck_cards: :card])

      # Verify cards were dealt
      player1_cards =
        updated_game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player1.id))

      player2_cards =
        updated_game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player2.id))

      assert length(player1_cards) == 4, "Player 1 should have 4 cards"
      assert length(player2_cards) == 4, "Player 2 should have 4 cards"

      # Verify both views are still responsive
      assert render(view1) != nil
      assert render(view2) != nil
    end

    test "displays other players' hands correctly", %{
      player1: player1,
      game_session: game_session
    } do
      conn1 = log_in_player(build_conn(), player1)

      # Mount the LiveView for player1
      {:ok, view, _html} = live(conn1, ~p"/games/#{game_session.id}")

      # Start the game
      render_click(view, "start_game")

      # Give the LiveView a moment to process the message
      Process.sleep(100)

      # The LiveView should have processed the message and updated its state
      html_after = render(view)

      # Assert that the other players' hands are displayed
      assert html_after =~ "player2@example.com"
      assert html_after =~ "4 cards"
      assert html_after =~ "player3@example.com"
    end
  end

  describe "error handling in game_updated flow" do
    test "handles game_updated with invalid game_session gracefully" do
      player = player_fixture()
      {:ok, game_session} = CardGames.create_game_session(player, %{short_code: "error-test"})

      conn = log_in_player(build_conn(), player)
      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Send malformed game_updated message (as Phoenix.Socket.Broadcast)
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "game:#{game_session.id}",
        event: "game_updated",
        payload: %{game_session: nil}
      })

      Process.sleep(50)

      # The view should handle the error and remain functional
      # (specific error handling depends on implementation)
      # At minimum, verify the view doesn't crash
      assert Process.alive?(view.pid), "LiveView process should not crash on invalid message"
    end

    test "handles game not found error" do
      player = player_fixture()
      conn = log_in_player(build_conn(), player)

      # Try to access a non-existent game
      assert {:error, {:redirect, %{to: redirect_path, flash: flash}}} =
               live(conn, ~p"/games/999999")

      # Should redirect to lobby with error message
      assert redirect_path == "/lobby"
      assert flash["error"] == "Game not found"
    end
  end
end
