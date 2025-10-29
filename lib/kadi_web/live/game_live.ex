defmodule KadiWeb.GameLive do
  use KadiWeb, :live_view

  alias Kadi.CardGames

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, game_session: nil)}
  end

  @impl true
  def handle_params(%{"game_id" => game_id}, _uri, socket) do
    case CardGames.get_game_session(game_id) do
      {:ok, game_session} ->
        {:noreply,
         socket
         |> assign(:game_session, game_session)}

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
        {:noreply,
         socket
         |> assign(:game_session, updated_game_session)
         |> put_flash(:info, "Game started!")}

      {:error, :not_enough_players} ->
        {:noreply, put_flash(socket, :error, "Not enough players to start the game.")}
    end
  end
end
