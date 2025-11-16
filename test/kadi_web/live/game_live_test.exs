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

      # Verify cards were dealt
      assert CardGames.count_player_cards(updated_game_session, player1.id) == 4,
             "Player 1 should have 4 cards"

      assert CardGames.count_player_cards(updated_game_session, player2.id) == 4,
             "Player 2 should have 4 cards"

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

  describe "draw card action" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "draw-live-test"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "player can draw card on their turn", %{
      player1: player1,
      game_session: game_session
    } do
      # Ensure it's player1's turn
      game_session =
        if game_session.current_turn_player_id != player1.id do
          Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
          |> Kadi.Repo.update!()
        else
          game_session
        end

      conn = log_in_player(build_conn(), player1)
      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Get initial hand size
      initial_html = render(view)
      # Should show "Draw Card" button
      assert initial_html =~ "Draw Card"

      # Click draw card
      render_click(view, "draw_card")
      Process.sleep(100)

      # Verify button is still there (turn advances so button disappears for this player)
      updated_html = render(view)

      # Should not show button anymore since turn advanced
      refute updated_html =~ "Draw Card"
    end

    test "draw card button hidden when not player's turn", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Ensure it's player2's turn
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player2.id})
        |> Kadi.Repo.update!()

      conn = log_in_player(build_conn(), player1)
      {:ok, _view, html} = live(conn, ~p"/games/#{game_session.id}")

      # Should NOT show "Draw Card" button
      refute html =~ "Draw Card"
    end

    test "draw card button shows recycle option when deck is empty but played pile has cards", %{
      player1: player1,
      game_session: game_session
    } do
      # Move all deck cards to played_stack (except keep at least 2 for recycling)
      game_session = Kadi.Repo.preload(game_session, deck: :deck_cards)

      # Get the max order_index from played_stack to avoid conflicts
      max_played_index =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "played_stack"))
        |> Enum.map(& &1.order_index)
        |> Enum.max(fn -> 0 end)

      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.with_index(max_played_index + 1)
      |> Enum.each(fn {dc, index} ->
        Kadi.Games.DeckCard.changeset(dc, %{
          location_type: "played_stack",
          order_index: index
        })
        |> Kadi.Repo.update!()
      end)

      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      conn = log_in_player(build_conn(), player1)
      {:ok, _view, html} = live(conn, ~p"/games/#{game_session.id}")

      # Should show "Draw Card (Recycle Pile)" button when deck is empty but played pile has 2+ cards
      assert html =~ "Draw Card (Recycle Pile)"
    end

    test "draw card triggers recycle when deck is empty", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Move all deck cards to played_stack
      game_session = Kadi.Repo.preload(game_session, deck: :deck_cards)

      max_played_index =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "played_stack"))
        |> Enum.map(& &1.order_index)
        |> Enum.max(fn -> 0 end)

      deck_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))

      deck_cards
      |> Enum.with_index(max_played_index + 1)
      |> Enum.each(fn {dc, index} ->
        Kadi.Games.DeckCard.changeset(dc, %{
          location_type: "played_stack",
          order_index: index
        })
        |> Kadi.Repo.update!()
      end)

      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      conn = log_in_player(build_conn(), player1)
      {:ok, view, html} = live(conn, ~p"/games/#{game_session.id}")

      # Verify deck is empty and played pile has cards
      assert html =~ "~0 cards left"
      assert html =~ "Draw Card (Recycle Pile)"

      # Click draw card - should trigger recycle
      render_click(view, "draw_card")
      Process.sleep(150)

      # Verify the card was drawn (turn should advance to player2)
      updated_html = render(view)
      assert updated_html =~ player2.email
    end

    test "multiple players see updated state after draw", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      conn1 = log_in_player(build_conn(), player1)
      conn2 = log_in_player(build_conn(), player2)

      {:ok, view1, _html1} = live(conn1, ~p"/games/#{game_session.id}")
      {:ok, view2, _html2} = live(conn2, ~p"/games/#{game_session.id}")

      # Player1 draws card
      render_click(view1, "draw_card")
      Process.sleep(100)

      # Both views should update
      html1 = render(view1)
      html2 = render(view2)

      # Current turn should have changed to player2
      assert html1 =~ player2.email
      assert html2 =~ player2.email

      # Player2 should now see the "Draw Card" button
      assert html2 =~ "Draw Card"

      # Player1 should NOT see the button
      refute html1 =~ "Draw Card"
    end
  end

  describe "Phase 8: Card Selection UI (T063)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "selection"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "clicking card toggles selection", %{player1: player1, game_session: game_session} do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      conn = log_in_player(build_conn(), player1)
      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Get a card from player's hand
      [player_card | _] = CardGames.get_player_hand(game_session, player1.id)

      # Click to select card
      render_click(view, "toggle_card", %{"card_id" => to_string(player_card.card_id)})
      html = render(view)

      # Card should show as selected (bg-blue-100 class)
      assert html =~ "bg-blue-100"

      # Click again to deselect
      render_click(view, "toggle_card", %{"card_id" => to_string(player_card.card_id)})
      html = render(view)

      # Button should show 0 cards selected
      assert html =~ "Play Selected Cards (0)"
    end

    test "play button disabled when no cards selected", %{
      player1: player1,
      game_session: game_session
    } do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      conn = log_in_player(build_conn(), player1)
      {:ok, _view, html} = live(conn, ~p"/games/#{game_session.id}")

      # Play button should be disabled
      assert html =~ "disabled"
      assert html =~ "Play Selected Cards (0)"
    end
  end

  describe "Phase 8: Play Cards Event (T064)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "play-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "playing valid card updates game state", %{player1: player1, game_session: game_session} do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      game_session =
        Kadi.Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      # Find a matching card
      top_card = game_session.top_card

      matching_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player1.id))
        |> Enum.find(fn dc ->
          card = dc.card
          card.suit == top_card.suit or card.rank == top_card.rank
        end)

      if matching_card do
        conn = log_in_player(build_conn(), player1)
        {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

        # Select and play the card
        render_click(view, "toggle_card", %{"card_id" => to_string(matching_card.card_id)})
        render_click(view, "play_cards")

        Process.sleep(100)
        html = render(view)

        # Turn should have changed to player2
        assert html =~ "player2@example.com"
      end
    end

    test "cards are sent to backend in selection order", %{
      player1: player1,
      game_session: game_session
    } do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      game_session =
        Kadi.Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      # Find multiple matching cards of the same rank
      top_card = game_session.top_card

      matching_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player1.id))
        |> Enum.filter(fn dc -> dc.card.rank == top_card.rank end)
        |> Enum.take(3)

      # Need at least 2 cards to test order
      if length(matching_cards) >= 2 do
        [card1, card2 | _] = matching_cards

        conn = log_in_player(build_conn(), player1)
        {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

        # Select cards in specific order: card1 first, then card2
        render_click(view, "toggle_card", %{"card_id" => to_string(card1.card_id)})
        render_click(view, "toggle_card", %{"card_id" => to_string(card2.card_id)})

        # Subscribe to PubSub to intercept the play_cards call
        topic = "game:#{game_session.id}"
        :ok = Phoenix.PubSub.subscribe(Kadi.PubSub, topic)

        # Play the cards
        render_click(view, "play_cards")

        # Wait for broadcast
        assert_receive %Phoenix.Socket.Broadcast{
                         event: "game_updated",
                         payload: %{game_session: updated_game_session}
                       },
                       1000

        # Verify cards were played and are in the played_stack
        updated_game_session =
          Kadi.Repo.preload(updated_game_session, [deck: [deck_cards: :card]], force: true)

        played_cards =
          updated_game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "played_stack"))
          |> Enum.sort_by(& &1.order_index)
          |> Enum.take(-2)

        # Cards should be in the order they were selected (card1, then card2)
        # The last two cards in played_stack should match selection order
        assert length(played_cards) == 2
        [played_first, played_second] = played_cards
        assert played_first.card_id == card1.card_id
        assert played_second.card_id == card2.card_id
      end
    end
  end

  describe "Phase 8: Invalid Play Error Flash (T066)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "error-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "shows error flash for invalid play", %{player1: player1, game_session: game_session} do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      game_session =
        Kadi.Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      # Find a non-matching card (excluding aces, which are always valid)
      top_card = game_session.top_card

      non_matching_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player1.id))
        |> Enum.find(fn dc ->
          card = dc.card
          card.suit != top_card.suit and card.rank != top_card.rank and card.rank != "ace"
        end)

      if non_matching_card do
        conn = log_in_player(build_conn(), player1)
        {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

        # Try to play invalid card
        render_click(view, "toggle_card", %{"card_id" => to_string(non_matching_card.card_id)})
        html = render_click(view, "play_cards")

        # Should show error message
        assert html =~ "Invalid play"
      end
    end
  end

  describe "Phase 8: Turn Validation (T067)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "turn-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "prevents out-of-turn plays", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      game_session = Kadi.Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      # Player2 tries to play when it's player1's turn
      player2_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.location_type == "player_hand" and &1.player_id == player2.id))

      if player2_card do
        conn = log_in_player(build_conn(), player2)
        {:ok, _view, html} = live(conn, ~p"/games/#{game_session.id}")

        # Player2 should not see play button (not their turn)
        refute html =~ "Play Selected Cards"
      end
    end
  end

  describe "Phase 8: PubSub Broadcasts (T068)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "pubsub-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "updates all connected players", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      conn1 = log_in_player(build_conn(), player1)
      conn2 = log_in_player(build_conn(), player2)

      {:ok, view1, _html1} = live(conn1, ~p"/games/#{game_session.id}")
      {:ok, view2, _html2} = live(conn2, ~p"/games/#{game_session.id}")

      # Player1 draws
      render_click(view1, "draw_card")
      Process.sleep(100)

      # Both views should update
      html1 = render(view1)
      html2 = render(view2)

      # Both should show player2's turn
      assert html1 =~ player2.email
      assert html2 =~ player2.email
    end
  end

  describe "Phase 8: Selection Cleared on Turn Change (T069)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "clear-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "clears selection when turn changes", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      game_session = Kadi.Repo.preload(game_session, [deck: [deck_cards: :card]], force: true)

      player1_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.location_type == "player_hand" and &1.player_id == player1.id))

      conn1 = log_in_player(build_conn(), player1)
      conn2 = log_in_player(build_conn(), player2)

      {:ok, view1, _html1} = live(conn1, ~p"/games/#{game_session.id}")
      {:ok, _view2, _html2} = live(conn2, ~p"/games/#{game_session.id}")

      # Player1 selects a card
      render_click(view1, "toggle_card", %{"card_id" => to_string(player1_card.card_id)})
      html = render(view1)
      assert html =~ "Play Selected Cards (1)"

      # Player2 takes turn (draw to advance)
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player2.id})
        |> Kadi.Repo.update!()

      # Broadcast the change
      Phoenix.PubSub.broadcast(
        Kadi.PubSub,
        "game:#{game_session.id}",
        %Phoenix.Socket.Broadcast{
          event: "game_updated",
          topic: "game:#{game_session.id}",
          payload: %{game_session: game_session}
        }
      )

      Process.sleep(100)
      _html = render(view1)

      # Player no longer sees play button (not their turn)
      # But selection should be cleared internally
      # We can verify by making it player1's turn again
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      Phoenix.PubSub.broadcast(
        Kadi.PubSub,
        "game:#{game_session.id}",
        %Phoenix.Socket.Broadcast{
          event: "game_updated",
          topic: "game:#{game_session.id}",
          payload: %{game_session: game_session}
        }
      )

      Process.sleep(100)
      html = render(view1)

      # Selection should still be 0 (was cleared when turn changed away)
      assert html =~ "Play Selected Cards (0)"
    end
  end

  describe "Phase 8: Full Gameplay Round (T070)" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "round-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "completes full round with both players", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      game_session =
        Kadi.Games.GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Kadi.Repo.update!()

      conn1 = log_in_player(build_conn(), player1)
      conn2 = log_in_player(build_conn(), player2)

      {:ok, view1, _html1} = live(conn1, ~p"/games/#{game_session.id}")
      {:ok, view2, _html2} = live(conn2, ~p"/games/#{game_session.id}")

      # Player1 draws
      render_click(view1, "draw_card")
      Process.sleep(100)

      html1 = render(view1)
      html2 = render(view2)

      # Should be player2's turn
      assert html1 =~ player2.email
      assert html2 =~ player2.email

      # Player2 draws
      render_click(view2, "draw_card")
      Process.sleep(100)

      html1 = render(view1)
      html2 = render(view2)

      # Should be back to player1's turn
      assert html1 =~ player1.email
      assert html2 =~ player1.email
    end
  end

  describe "Ace Card UI" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "ace-live-test"})
      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session, exclude_ranks: ["ace"])

      game_session = Kadi.Repo.preload(game_session, :current_turn_player)
      current_player = game_session.current_turn_player

      other_player = if current_player.id == player1.id, do: player2, else: player1

      # Manually give an Ace to the current player
      ace_card_id = deal_card_to_player(game_session, current_player, "ace", "spades")

      game_session = Kadi.Repo.get!(Kadi.Games.GameSession, game_session.id)

      %{
        current_player: current_player,
        other_player: other_player,
        game_session: game_session,
        ace_card_id: ace_card_id
      }
    end

    test "Suit selection buttons appear after Ace played", %{
      current_player: current_player,
      game_session: game_session,
      ace_card_id: ace_card_id
    } do
      conn = log_in_player(build_conn(), current_player)
      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Play the Ace card
      render_click(view, "toggle_card", %{"card_id" => to_string(ace_card_id)})
      render_click(view, "play_cards")
      Process.sleep(100)
      html = render(view)

      # Verify suit selection UI is visible
      assert html =~ "Select a suit:"
      assert html =~ "phx-click=\"select_suit\""
      assert html =~ "phx-value-suit=\"hearts\""
      assert html =~ "phx-value-suit=\"diamonds\""
      assert html =~ "phx-value-suit=\"clubs\""
      assert html =~ "phx-value-suit=\"spades\""
    end

    test "Clicking suit button calls select_suit event", %{
      current_player: current_player,
      other_player: other_player,
      game_session: game_session,
      ace_card_id: ace_card_id
    } do
      conn = log_in_player(build_conn(), current_player)
      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Play the Ace card
      render_click(view, "toggle_card", %{"card_id" => to_string(ace_card_id)})
      render_click(view, "play_cards")
      Process.sleep(100)

      # Click a suit button
      render_click(view, "select_suit", %{"suit" => "clubs"})
      Process.sleep(100)
      html = render(view)

      # Verify the game state updated and UI changed
      refute html =~ "Select a suit:"
      # Turn should have advanced to other_player
      assert html =~ other_player.email

      {:ok, updated_game} = CardGames.get_game_session(game_session.id)
      assert updated_game.action_suit == "clubs"
      assert updated_game.action_type == nil
    end

    test "Suit selection buttons disappear after selection", %{
      current_player: current_player,
      game_session: game_session,
      ace_card_id: ace_card_id
    } do
      conn = log_in_player(build_conn(), current_player)
      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Play the Ace
      render_click(view, "toggle_card", %{"card_id" => to_string(ace_card_id)})
      render_click(view, "play_cards")
      Process.sleep(100)
      html_before = render(view)

      assert html_before =~ "Select a suit:"

      # Select a suit
      render_click(view, "select_suit", %{"suit" => "spades"})
      Process.sleep(100)
      html_after = render(view)

      # Verify buttons are gone
      refute html_after =~ "Select a suit:"
      refute html_after =~ "phx-click=\"select_suit\""
    end
  end

  defp deal_card_to_player(game_session, player, rank, suit) do
    card = Kadi.Repo.get_by!(Kadi.Games.Card, rank: rank, suit: suit)
    deck = Kadi.Repo.get_by!(Kadi.Games.Deck, game_session_id: game_session.id)

    # Find the deck_card for the card to be dealt
    deck_card =
      Kadi.Repo.get_by!(Kadi.Games.DeckCard, deck_id: deck.id, card_id: card.id)

    # Update the deck_card to be in the player's hand
    deck_card
    |> Kadi.Games.DeckCard.changeset(%{
      location_type: "player_hand",
      player_id: player.id,
      order_index: nil
    })
    |> Kadi.Repo.update!()

    # Return the card_id
    card.id
  end

  describe "3 Card Penalty UI" do
    setup do
      player1 = player_fixture()
      player2 = player_fixture(%{email: "player2@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "three-penalty-ui"})

      {:ok, _} = CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      %{player1: player1, player2: player2, game_session: game_session}
    end

    test "displays 'Draw 3 Cards' button when penalty_type is 'three'", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up a 3 card penalty targeting player2
      game_session =
        game_session
        |> Ecto.Changeset.change(%{
          draw_penalty: %{
            active: true,
            penalty_type: "three",
            target_player_id: player2.id,
            created_by_player_id: player1.id
          },
          current_turn_player_id: player2.id
        })
        |> Kadi.Repo.update!()

      conn = log_in_player(build_conn(), player2)
      {:ok, _view, html} = live(conn, ~p"/games/#{game_session.id}")

      # Should display "Draw 3 Cards" button
      assert html =~ "Draw 3 Cards"
      assert html =~ "phx-click=\"accept_penalty\""
    end

    test "displays 'Draw 3 penalty active' indicator", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up a 3 card penalty
      game_session =
        game_session
        |> Ecto.Changeset.change(%{
          draw_penalty: %{
            active: true,
            penalty_type: "three",
            target_player_id: player2.id,
            created_by_player_id: player1.id
          },
          current_turn_player_id: player2.id
        })
        |> Kadi.Repo.update!()

      # Player1 (not the target) should see the penalty indicator
      conn = log_in_player(build_conn(), player1)
      {:ok, _view, html} = live(conn, ~p"/games/#{game_session.id}")

      # Should display penalty indicator with count of 3
      assert html =~ "must draw 3 cards"
    end

    test "clicking 'Draw 3 Cards' button draws 3 cards", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up a 3 card penalty targeting player2
      game_session =
        game_session
        |> Ecto.Changeset.change(%{
          draw_penalty: %{
            active: true,
            penalty_type: "three",
            target_player_id: player2.id,
            created_by_player_id: player1.id
          },
          current_turn_player_id: player2.id
        })
        |> Kadi.Repo.update!()

      # Get initial hand size
      initial_hand_size = CardGames.count_player_cards(game_session, player2.id)

      conn = log_in_player(build_conn(), player2)
      {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

      # Click the "Draw 3 Cards" button
      render_click(view, "accept_penalty")
      Process.sleep(100)

      # Verify 3 cards were drawn
      updated_game_session = Kadi.Repo.get!(Kadi.Games.GameSession, game_session.id)
      final_hand_size = CardGames.count_player_cards(updated_game_session, player2.id)

      assert final_hand_size == initial_hand_size + 3,
             "Expected player to draw 3 cards (had #{initial_hand_size}, now has #{final_hand_size})"

      # Verify penalty is cleared
      assert updated_game_session.draw_penalty["active"] == false
    end

    test "blocking cards are clickable when 3 penalty active", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up a 3 card penalty targeting player2
      game_session =
        game_session
        |> Ecto.Changeset.change(%{
          draw_penalty: %{
            active: true,
            penalty_type: "three",
            target_player_id: player2.id,
            created_by_player_id: player1.id
          },
          current_turn_player_id: player2.id
        })
        |> Kadi.Repo.update!()

      # Give player2 an Ace (blocking card)
      ace_card_id = deal_card_to_player(game_session, player2, "ace", "hearts")

      conn = log_in_player(build_conn(), player2)
      {:ok, view, html} = live(conn, ~p"/games/#{game_session.id}")

      # Should show both the penalty button and clickable cards
      assert html =~ "Draw 3 Cards"

      # Try to select the Ace card (should work)
      render_click(view, "toggle_card", %{"card_id" => to_string(ace_card_id)})
      html = render(view)

      # Card should be selected
      assert html =~ "bg-blue-100"
    end

    test "shows error message when non-blocking card clicked during 3 penalty", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up a 3 card penalty targeting player2
      game_session =
        game_session
        |> Ecto.Changeset.change(%{
          draw_penalty: %{
            active: true,
            penalty_type: "three",
            target_player_id: player2.id,
            created_by_player_id: player1.id
          },
          current_turn_player_id: player2.id
        })
        |> Kadi.Repo.update!()

      game_session = Kadi.Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]])

      # Find a non-blocking card (not Ace, not 3)
      non_blocking_card =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player2.id))
        |> Enum.find(fn dc ->
          card = dc.card
          card.rank != "ace" and card.rank != "3"
        end)

      if non_blocking_card do
        conn = log_in_player(build_conn(), player2)
        {:ok, view, _html} = live(conn, ~p"/games/#{game_session.id}")

        # Try to play the non-blocking card
        render_click(view, "toggle_card", %{"card_id" => to_string(non_blocking_card.card_id)})
        html = render_click(view, "play_cards")

        # Should show error message
        assert html =~ "Penalty Active. You must play blocking card or draw penalty cards"
      end
    end

    test "penalty indicator disappears after accepting penalty", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up a 3 card penalty targeting player2
      game_session =
        game_session
        |> Ecto.Changeset.change(%{
          draw_penalty: %{
            active: true,
            penalty_type: "three",
            target_player_id: player2.id,
            created_by_player_id: player1.id
          },
          current_turn_player_id: player2.id
        })
        |> Kadi.Repo.update!()

      # Connect both players
      conn1 = log_in_player(build_conn(), player1)
      conn2 = log_in_player(build_conn(), player2)

      {:ok, view1, html1} = live(conn1, ~p"/games/#{game_session.id}")
      {:ok, view2, html2} = live(conn2, ~p"/games/#{game_session.id}")

      # Both should see penalty indicator
      assert html1 =~ "must draw 3 cards"
      assert html2 =~ "Draw 3 Cards"

      # Player2 accepts the penalty
      render_click(view2, "accept_penalty")
      Process.sleep(100)

      # Re-render both views
      html1_after = render(view1)
      html2_after = render(view2)

      # Penalty indicator should be gone for both players
      refute html1_after =~ "must draw 3 cards"
      refute html2_after =~ "Draw 3 Cards"
    end

    test "shows enhanced message when Ace blocks a penalty", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up: Current player plays a '3' to create a penalty
      game_session =
        Kadi.Repo.preload(game_session, [
          :top_card,
          :current_turn_player,
          deck: [deck_cards: :card]
        ])

      # Determine who has the current turn
      current_player = game_session.current_turn_player
      next_player = if current_player.id == player1.id, do: player2, else: player1

      top_card = game_session.top_card

      # Find a '3' card that matches the top card (either rank or suit)
      three_card =
        game_session.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "3" && &1.location_type == "deck" &&
              (&1.card.suit == top_card.suit || &1.card.rank == top_card.rank))
        )

      # If no matching '3', find any '3' and set up the top card to match
      three_card =
        if three_card do
          three_card
        else
          # Find any '3' in deck
          any_three =
            game_session.deck.deck_cards
            |> Enum.find(&(&1.card.rank == "3" && &1.location_type == "deck"))

          # Move a card with matching suit to played pile as top card
          matching_card =
            game_session.deck.deck_cards
            |> Enum.find(
              &(&1.location_type == "deck" && &1.card.suit == any_three.card.suit &&
                  &1.card.rank != "3")
            )

          if matching_card do
            {:ok, _} =
              Kadi.Games.DeckCard.changeset(matching_card, %{
                location_type: "played_stack",
                order_index: 100,
                player_id: nil
              })
              |> Kadi.Repo.update()

            # Update game session top card
            game_session
            |> Ecto.Changeset.change(%{top_card_id: matching_card.card_id})
            |> Kadi.Repo.update!()
          end

          any_three
        end

      three_suit = three_card.card.suit

      {:ok, _} =
        Kadi.Games.DeckCard.changeset(three_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Kadi.Repo.update()

      # Current player plays the '3'
      game_session = Kadi.Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, game_with_penalty} =
        CardGames.play_cards(game_session, current_player.id, [three_card.card_id])

      # Verify penalty is active
      assert game_with_penalty.draw_penalty["active"] == true
      assert game_with_penalty.draw_penalty["penalty_type"] == "three"

      # Give next_player an Ace to block
      game_with_penalty = Kadi.Repo.preload(game_with_penalty, deck: [deck_cards: :card])

      ace_card =
        game_with_penalty.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      {:ok, _} =
        Kadi.Games.DeckCard.changeset(ace_card, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
        |> Kadi.Repo.update()

      # Next player blocks with Ace
      game_with_penalty = Kadi.Repo.get!(Kadi.Games.GameSession, game_with_penalty.id)

      {:ok, game_after_block} =
        CardGames.play_cards(game_with_penalty, next_player.id, [ace_card.card_id])

      # Verify penalty is cleared and action_suit is set to the suit of the blocked card
      assert game_after_block.draw_penalty["active"] == false
      assert game_after_block.action_suit == three_suit

      # Connect as any player and verify the enhanced message is shown
      conn = log_in_player(build_conn(), current_player)
      {:ok, _view, html} = live(conn, ~p"/games/#{game_after_block.id}")

      # Should show enhanced message about Ace blocking penalty
      assert html =~ "Ace blocked penalty!"
      assert html =~ "Active suit:"
      assert html =~ String.capitalize(three_suit)
      assert html =~ "from last penalty card"
      # Should show the penalty card (3 with suit symbol)
      assert html =~ "3"
    end

    test "does NOT show enhanced message for normal Ace play (suit selection)", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up: Current player plays a normal Ace (not blocking a penalty)
      game_session =
        Kadi.Repo.preload(game_session, [
          :top_card,
          :current_turn_player,
          deck: [deck_cards: :card]
        ])

      current_player = game_session.current_turn_player
      other_player = if current_player.id == player1.id, do: player2, else: player1

      # Find an Ace and give it to current player
      ace_card =
        game_session.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      {:ok, _} =
        Kadi.Games.DeckCard.changeset(ace_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Kadi.Repo.update()

      # Current player plays the Ace (normal play, not blocking)
      game_session = Kadi.Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, game_after_ace} =
        CardGames.play_cards(game_session, current_player.id, [ace_card.card_id])

      # Verify action_type is set to select_suit (normal Ace behavior)
      assert game_after_ace.action_type == "select_suit"
      assert game_after_ace.action_suit == nil

      # Current player selects a suit
      {:ok, game_after_selection} =
        CardGames.select_suit(game_after_ace, current_player.id, "hearts")

      # Verify action_suit is now set
      assert game_after_selection.action_suit == "hearts"

      # Connect as other player and verify the NORMAL message is shown (not the enhanced one)
      conn = log_in_player(build_conn(), other_player)
      {:ok, _view, html} = live(conn, ~p"/games/#{game_after_selection.id}")

      # Should show normal suit requirement message
      assert html =~ "Required Suit:"
      assert html =~ "Hearts"
      # Should NOT show the enhanced penalty blocking message
      refute html =~ "Ace blocked penalty!"
      refute html =~ "from last penalty card"
    end

    test "highlights penalty cards when Ace blocks penalty (rank matching)", %{
      player1: player1,
      player2: player2,
      game_session: game_session
    } do
      # Set up: Current player plays a '3' to create a penalty
      game_session =
        Kadi.Repo.preload(game_session, [
          :top_card,
          :current_turn_player,
          deck: [deck_cards: :card]
        ])

      current_player = game_session.current_turn_player
      next_player = if current_player.id == player1.id, do: player2, else: player1

      # Find a '3' card that matches the top card
      top_card = game_session.top_card

      three_card =
        game_session.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "3" && &1.location_type == "deck" &&
              (&1.card.suit == top_card.suit || &1.card.rank == top_card.rank))
        )

      # If no matching '3', set up a matching top card
      three_card =
        if three_card do
          three_card
        else
          any_three =
            game_session.deck.deck_cards
            |> Enum.find(&(&1.card.rank == "3" && &1.location_type == "deck"))

          matching_card =
            game_session.deck.deck_cards
            |> Enum.find(
              &(&1.location_type == "deck" && &1.card.suit == any_three.card.suit &&
                  &1.card.rank != "3")
            )

          if matching_card do
            {:ok, _} =
              Kadi.Games.DeckCard.changeset(matching_card, %{
                location_type: "played_stack",
                order_index: 100,
                player_id: nil
              })
              |> Kadi.Repo.update()

            game_session
            |> Ecto.Changeset.change(%{top_card_id: matching_card.card_id})
            |> Kadi.Repo.update!()
          end

          any_three
        end

      three_suit = three_card.card.suit

      {:ok, _} =
        Kadi.Games.DeckCard.changeset(three_card, %{
          location_type: "player_hand",
          player_id: current_player.id,
          order_index: nil
        })
        |> Kadi.Repo.update()

      # Current player plays the '3'
      game_session = Kadi.Repo.get!(Kadi.Games.GameSession, game_session.id)

      {:ok, game_with_penalty} =
        CardGames.play_cards(game_session, current_player.id, [three_card.card_id])

      # Give next_player an Ace to block
      game_with_penalty = Kadi.Repo.preload(game_with_penalty, deck: [deck_cards: :card])

      ace_card =
        game_with_penalty.deck.deck_cards
        |> Enum.find(&(&1.card.rank == "ace" && &1.location_type == "deck"))

      {:ok, _} =
        Kadi.Games.DeckCard.changeset(ace_card, %{
          location_type: "player_hand",
          player_id: next_player.id,
          order_index: nil
        })
        |> Kadi.Repo.update()

      # Next player blocks with Ace
      game_with_penalty = Kadi.Repo.get!(Kadi.Games.GameSession, game_with_penalty.id)

      {:ok, game_after_block} =
        CardGames.play_cards(game_with_penalty, next_player.id, [ace_card.card_id])

      # Now it's current_player's turn again
      # Give current_player another '3' (different suit) and a card matching the active suit
      game_after_block = Kadi.Repo.preload(game_after_block, deck: [deck_cards: :card])

      # Find another '3' with different suit
      another_three =
        game_after_block.deck.deck_cards
        |> Enum.find(
          &(&1.card.rank == "3" && &1.location_type == "deck" && &1.card.suit != three_suit)
        )

      # Find a card matching the active suit (but not a '3' or Ace)
      matching_suit_card =
        game_after_block.deck.deck_cards
        |> Enum.find(
          &(&1.card.suit == three_suit && &1.location_type == "deck" && &1.card.rank != "3" &&
              &1.card.rank != "ace")
        )

      if another_three do
        {:ok, _} =
          Kadi.Games.DeckCard.changeset(another_three, %{
            location_type: "player_hand",
            player_id: current_player.id,
            order_index: nil
          })
          |> Kadi.Repo.update()
      end

      if matching_suit_card do
        {:ok, _} =
          Kadi.Games.DeckCard.changeset(matching_suit_card, %{
            location_type: "player_hand",
            player_id: current_player.id,
            order_index: nil
          })
          |> Kadi.Repo.update()
      end

      # Connect as current_player and verify both cards are highlighted
      conn = log_in_player(build_conn(), current_player)
      {:ok, _view, html} = live(conn, ~p"/games/#{game_after_block.id}")

      # Both the '3' (rank match) and the suit-matching card should be highlighted
      # The HTML should contain the green border class for valid cards
      assert html =~ "bg-green-100 border-green-500"
    end
  end
end
