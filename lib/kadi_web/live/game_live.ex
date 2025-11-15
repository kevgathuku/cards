defmodule KadiWeb.GameLive do
  use KadiWeb, :live_view

  alias Kadi.CardGames

  # Toast coalescing window (FR-025)
  @toast_coalesce_ms 2000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       game_session: nil,
       player_hand: [],
       played_pile: [],
       deck_size: 0,
       current_turn_player: nil,
       other_players_hands: [],
       selected_cards: [],
       direction: "clockwise",
       toast: nil,
       toast_timer: nil,
       show_penalty_animation: false
     )}
  end

  @impl true
  def handle_params(%{"game_id" => game_id}, _uri, socket) do
    case CardGames.get_game_session(game_id) do
      {:ok, game_session} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Kadi.PubSub, "game:#{game_id}")
        end

        socket = assign_game_state(socket, game_session)
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Game not found")
         |> redirect(to: ~p"/lobby")}
    end
  end

  @impl true
  def handle_event("start_game", _, socket) do
    game_session = socket.assigns.game_session

    case CardGames.start_game(game_session) do
      {:ok, updated_game_session} ->
        socket = assign_game_state(socket, updated_game_session)

        {:noreply,
         socket
         |> put_flash(:info, "Game started!")}

      {:error, :not_enough_players} ->
        {:noreply, put_flash(socket, :error, "Not enough players to start the game.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error starting game: #{reason}")}
    end
  end

  @impl true
  def handle_event("draw_card", _params, socket) do
    game_session = socket.assigns.game_session
    current_player = socket.assigns.current_player

    case CardGames.draw_card_from_deck(game_session, current_player.id) do
      {:ok, _updated_game_session} ->
        # Don't update socket directly - wait for broadcast
        {:noreply, socket}

      {:error, :not_your_turn} ->
        {:noreply, put_flash(socket, :error, "It's not your turn")}

      {:error, :deck_empty} ->
        {:noreply, put_flash(socket, :error, "No cards left in deck or played pile")}

      {:error, :deck_empty_after_recycle} ->
        {:noreply, put_flash(socket, :error, "No cards available after recycling")}

      {:error, :no_cards_in_played_stack} ->
        {:noreply, put_flash(socket, :error, "No cards to recycle from played pile")}

      {:error, :insufficient_cards_to_recycle} ->
        {:noreply, put_flash(socket, :error, "Need at least 2 cards in played pile to recycle")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error: #{reason}")}
    end
  end

  @impl true
  def handle_event("toggle_card", %{"card_id" => card_id_str}, socket) do
    card_id = String.to_integer(card_id_str)
    selected_cards = socket.assigns.selected_cards

    updated_selected =
      if card_id in selected_cards do
        List.delete(selected_cards, card_id)
      else
        [card_id | selected_cards]
      end

    {:noreply, assign(socket, selected_cards: updated_selected)}
  end

  @impl true
  def handle_event("play_cards", _params, socket) do
    game_session = socket.assigns.game_session
    current_player = socket.assigns.current_player
    selected_cards = socket.assigns.selected_cards

    if Enum.empty?(selected_cards) do
      {:noreply, put_flash(socket, :error, "Please select at least one card")}
    else
      # Reverse to send cards in the order they were selected (oldest first)
      cards_in_selection_order = Enum.reverse(selected_cards)

      case CardGames.play_cards(game_session, current_player.id, cards_in_selection_order) do
        {:ok, _updated_game_session} ->
          # Clear selection and wait for broadcast
          {:noreply, assign(socket, selected_cards: [])}

        {:error, :not_your_turn} ->
          {:noreply,
           socket
           |> put_flash(:error, "It's not your turn")
           |> assign(selected_cards: [])}

        {:error, :invalid_play} ->
          # T044: Check if penalty is active and show specific error (FR-006)
          draw_penalty = game_session.draw_penalty || %{}

          error_msg =
            if draw_penalty["active"] == true and
                 draw_penalty["target_player_id"] == current_player.id do
              "Penalty Active. You must play blocking card or draw penalty cards"
            else
              # T063: Show specific error when action_suit requirement not met
              if game_session.action_suit do
                "Invalid play - you must play a card matching the required suit (#{String.capitalize(game_session.action_suit)}) or an Ace"
              else
                "Invalid play - card(s) don't match the top card or are not yet implemented"
              end
            end

          {:noreply,
           socket
           |> put_flash(:error, error_msg)
           |> assign(selected_cards: [])}

        {:error, :cards_not_in_hand} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have those cards")
           |> assign(selected_cards: [])}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Error: #{inspect(reason)}")
           |> assign(selected_cards: [])}
      end
    end
  end

  @impl true
  def handle_event("select_suit", %{"suit" => suit}, socket) do
    game_session = socket.assigns.game_session
    current_player = socket.assigns.current_player

    case CardGames.select_suit(game_session, current_player.id, suit) do
      {:ok, _updated_game_session} ->
        # Wait for broadcast
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error selecting suit: #{reason}")}
    end
  end

  # T037: Handle explicit penalty acceptance via button click
  # T046: Button click clears penalty (not transfers) even if player has blocking cards (FR-007)
  @impl true
  def handle_event("accept_penalty", _params, socket) do
    game_session = socket.assigns.game_session
    current_player = socket.assigns.current_player

    # process_draw_penalty clears penalty (sets active=false) and advances turn
    # This gives players strategic choice: accept penalty OR play blocking card
    case CardGames.process_draw_penalty(game_session, current_player.id) do
      {:ok, _updated_game_session} ->
        # Don't update socket - wait for broadcast
        {:noreply, socket}

      {:error, :not_current_turn} ->
        {:noreply, put_flash(socket, :error, "It's not your turn")}

      {:error, :no_penalty} ->
        {:noreply, put_flash(socket, :error, "No penalty to accept")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot draw penalty: #{reason}")}
    end
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "game_updated", payload: %{game_session: nil}},
        socket
      ) do
    # Handle invalid game_session gracefully - keep existing state
    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "game_updated",
          payload: %{game_session: updated_game_session}
        },
        socket
      ) do
    # Auto-clear selected cards if turn changed to another player
    current_player_id = socket.assigns.current_player.id

    old_turn_player_id =
      socket.assigns.current_turn_player && socket.assigns.current_turn_player.id

    updated_game_session =
      updated_game_session
      |> Kadi.Repo.preload([:current_turn_player])

    new_turn_player_id = updated_game_session.current_turn_player_id

    socket =
      if old_turn_player_id != new_turn_player_id and new_turn_player_id != current_player_id do
        assign(socket, selected_cards: [])
      else
        socket
      end

    # Check for direction change and show toast (FR-025, T054)
    old_direction = socket.assigns.direction
    new_direction = updated_game_session.direction

    socket =
      if old_direction != new_direction do
        # Cancel existing toast timer if any (toast coalescing)
        if socket.assigns.toast_timer do
          Process.cancel_timer(socket.assigns.toast_timer)
        end

        # Set new toast with timer (auto-dismiss after 2s)
        timer_ref = Process.send_after(self(), :clear_toast, @toast_coalesce_ms)

        assign(socket,
          toast: %{
            message: "Direction reversed: now #{direction_label(new_direction)}",
            updated_at: System.monotonic_time()
          },
          toast_timer: timer_ref
        )
      else
        socket
      end

    # T026: Check for active penalty targeting current player (FR-011)
    socket =
      check_and_show_penalty_notification(
        socket,
        updated_game_session,
        current_player_id
      )

    # T038: Detect penalty clearing to trigger animation (FR-005)
    old_penalty = socket.assigns.game_session.draw_penalty || %{}
    new_penalty = updated_game_session.draw_penalty || %{}

    socket =
      if old_penalty["active"] == true and new_penalty["active"] != true and
           old_penalty["target_player_id"] == current_player_id do
        # Penalty was just cleared for current player - trigger animation
        assign(socket, show_penalty_animation: true)
      else
        assign(socket, show_penalty_animation: false)
      end

    socket = assign_game_state(socket, updated_game_session)
    {:noreply, socket}
  end

  # T055: Clear toast handler
  @impl true
  def handle_info(:clear_toast, socket) do
    {:noreply, assign(socket, toast: nil, toast_timer: nil)}
  end

  # Handle anomaly banner broadcasts (FR-019)
  @impl true
  def handle_info({:anomaly_banner, %{message: message}}, socket) do
    # Show anomaly as a toast notification
    # Cancel existing toast timer if any
    if socket.assigns.toast_timer do
      Process.cancel_timer(socket.assigns.toast_timer)
    end

    # Set anomaly toast with timer
    timer_ref = Process.send_after(self(), :clear_toast, @toast_coalesce_ms)

    {:noreply,
     assign(socket,
       toast: %{
         message: message,
         updated_at: System.monotonic_time(),
         type: :warning
       },
       toast_timer: timer_ref
     )}
  end

  # T026: Handle penalty notification broadcasts (FR-011)
  @impl true
  def handle_info({:penalty_notification, %{message: message}}, socket) do
    # Show penalty notification as a toast
    # Cancel existing toast timer if any
    if socket.assigns.toast_timer do
      Process.cancel_timer(socket.assigns.toast_timer)
    end

    # Set penalty toast with timer
    timer_ref = Process.send_after(self(), :clear_toast, @toast_coalesce_ms)

    {:noreply,
     assign(socket,
       toast: %{
         message: message,
         updated_at: System.monotonic_time(),
         type: :penalty
       },
       toast_timer: timer_ref
     )}
  end

  defp assign_game_state(socket, game_session) do
    current_player_id = socket.assigns.current_player.id

    game_session =
      game_session
      |> Kadi.Repo.preload([
        :current_turn_player,
        game_session_players: :player,
        deck: [deck_cards: :card]
      ])

    all_deck_cards = game_session.deck.deck_cards

    player_hand =
      Enum.filter(
        all_deck_cards,
        &(&1.location_type == "player_hand" and &1.player_id == current_player_id)
      )

    other_players =
      game_session.game_session_players
      |> Enum.map(& &1.player)
      |> Enum.filter(&(&1.id != current_player_id))

    other_players_hands =
      Enum.map(other_players, fn player ->
        hand_size =
          Enum.count(
            all_deck_cards,
            &(&1.location_type == "player_hand" and &1.player_id == player.id)
          )

        %{
          id: player.id,
          email: player.email,
          hand_size: hand_size
        }
      end)

    played_pile =
      all_deck_cards
      |> Enum.filter(&(&1.location_type == "played_stack"))
      |> Enum.sort_by(& &1.order_index)

    deck_size = Enum.count(all_deck_cards, &(&1.location_type == "deck"))

    # T058: Build player statuses map for cardless badge display
    player_statuses = build_player_statuses_map(game_session)

    assign(socket,
      game_session: game_session,
      player_hand: player_hand,
      played_pile: played_pile,
      deck_size: deck_size,
      current_turn_player: game_session.current_turn_player,
      other_players_hands: other_players_hands,
      selected_cards: socket.assigns[:selected_cards] || [],
      direction: game_session.direction || "clockwise",
      player_statuses: player_statuses
    )
  end

  # T037: Helper function to build player status map for UI tracking
  # Maps player_id -> status ("normal" | "cardless")
  # Used for future UI indicators of player states
  defp build_player_statuses_map(game_session) do
    game_session.game_session_players
    |> Enum.into(%{}, fn gsp -> {gsp.player_id, gsp.status} end)
  end

  # T039: Direction display helpers for UI
  # Returns Heroicon name for direction indicator
  defp direction_icon("clockwise"), do: "hero-arrow-path"
  defp direction_icon("counter_clockwise"), do: "hero-arrow-path"
  defp direction_icon(_), do: "hero-arrow-path"

  # Returns human-readable label for direction
  defp direction_label("clockwise"), do: "Clockwise"
  defp direction_label("counter_clockwise"), do: "Counter-clockwise"
  defp direction_label(_), do: "Clockwise"

  # T061: Suit symbol helper for UI display
  defp suit_symbol("hearts"), do: "♥"
  defp suit_symbol("diamonds"), do: "♦"
  defp suit_symbol("clubs"), do: "♣"
  defp suit_symbol("spades"), do: "♠"
  defp suit_symbol(_), do: ""

  # T062: Helper to determine card CSS class based on selection, required suit, and blocking cards
  defp card_class(is_selected, matches_required_suit, is_blocking_card) do
    cond do
      is_selected -> "bg-blue-100 border-blue-500 border-2 -translate-y-2"
      matches_required_suit -> "bg-green-100 border-green-500 border-2"
      is_blocking_card -> "bg-green-100 border-green-500 border-2"
      true -> "bg-white hover:bg-gray-50"
    end
  end

  # T026: Check if current player has an active penalty and show notification (FR-011)
  defp check_and_show_penalty_notification(socket, game_session, current_player_id) do
    draw_penalty = game_session.draw_penalty || %{}

    # Check if penalty is active and targets current player
    if draw_penalty["active"] == true and
         draw_penalty["target_player_id"] == current_player_id do
      # Only show notification if it's a new penalty (not already shown)
      old_penalty = socket.assigns.game_session.draw_penalty || %{}

      if old_penalty["active"] != true or
           old_penalty["target_player_id"] != current_player_id do
        # Find who played the '2' card (previous player)
        penalty_creator = find_penalty_creator(game_session)

        message =
          if penalty_creator do
            "You must draw #{draw_penalty["count"]} cards due to #{penalty_creator}'s '2' card"
          else
            "You must draw #{draw_penalty["count"]} cards due to a '2' card penalty"
          end

        # Cancel existing toast timer if any
        if socket.assigns.toast_timer do
          Process.cancel_timer(socket.assigns.toast_timer)
        end

        # Set penalty toast with timer
        timer_ref = Process.send_after(self(), :clear_toast, @toast_coalesce_ms)

        assign(socket,
          toast: %{
            message: message,
            updated_at: System.monotonic_time(),
            type: :penalty
          },
          toast_timer: timer_ref
        )
      else
        socket
      end
    else
      socket
    end
  end

  # T026: Find the player who created the penalty (for notification message)
  defp find_penalty_creator(game_session) do
    # Get all players in turn order
    players =
      game_session.game_session_players
      |> Enum.sort_by(& &1.inserted_at)
      |> Enum.map(& &1.player)

    # Find current turn player index
    current_index =
      Enum.find_index(players, fn p -> p.id == game_session.current_turn_player_id end)

    if current_index do
      # Previous player is the one who created the penalty
      previous_index = rem(current_index - 1 + length(players), length(players))
      previous_player = Enum.at(players, previous_index)
      previous_player.email
    else
      nil
    end
  end

  # T035: Helper to determine if penalty acceptance button should be shown
  # Shows button when: penalty is active AND it's the current player's turn
  defp show_penalty_button?(game_session, current_player_id) do
    draw_penalty = game_session.draw_penalty || %{}

    draw_penalty["active"] == true and
      draw_penalty["target_player_id"] == current_player_id and
      game_session.current_turn_player_id == current_player_id
  end
end
