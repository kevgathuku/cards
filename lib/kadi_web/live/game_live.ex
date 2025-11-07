defmodule KadiWeb.GameLive do
  use KadiWeb, :live_view

  alias Kadi.CardGames

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
       selected_cards: []
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
        {:noreply, put_flash(socket, :error, "No cards left in deck")}

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
      case CardGames.play_cards(game_session, current_player.id, selected_cards) do
        {:ok, _updated_game_session} ->
          # Clear selection and wait for broadcast
          {:noreply, assign(socket, selected_cards: [])}

        {:error, :not_your_turn} ->
          {:noreply,
           socket
           |> put_flash(:error, "It's not your turn")
           |> assign(selected_cards: [])}

        {:error, :invalid_play} ->
          {:noreply,
           socket
           |> put_flash(:error, "Invalid play - card(s) don't match the top card")
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

    socket = assign_game_state(socket, updated_game_session)
    {:noreply, socket}
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
          email: player.email,
          hand_size: hand_size
        }
      end)

    played_pile =
      all_deck_cards
      |> Enum.filter(&(&1.location_type == "played_stack"))
      |> Enum.sort_by(& &1.order_index)

    deck_size = Enum.count(all_deck_cards, &(&1.location_type == "deck"))

    assign(socket,
      game_session: game_session,
      player_hand: player_hand,
      played_pile: played_pile,
      deck_size: deck_size,
      current_turn_player: game_session.current_turn_player,
      other_players_hands: other_players_hands
    )
  end
end
