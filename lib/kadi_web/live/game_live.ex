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
       current_turn_player: nil
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
  def handle_info({:game_updated, %{game_session: updated_game_session}}, socket) do
    socket = assign_game_state(socket, updated_game_session)
    {:noreply, socket}
  end

  defp assign_game_state(socket, game_session) do
    current_player_id = socket.assigns.current_player.id

    game_session =
      game_session
      |> Kadi.Repo.preload([:current_turn_player, deck: [deck_cards: :card]])

    all_deck_cards = game_session.deck.deck_cards

    player_hand =
      Enum.filter(
        all_deck_cards,
        &(&1.location_type == "player_hand" and &1.player_id == current_player_id)
      )

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
      current_turn_player: game_session.current_turn_player
    )
  end
end
