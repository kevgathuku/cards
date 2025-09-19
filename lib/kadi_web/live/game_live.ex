defmodule KadiWeb.GameLive do
  use KadiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, game_id: nil, game_state: nil, current_player: nil)}
  end

  @impl true
  def handle_params(%{"game_id" => game_id}, _uri, socket) do
    case Kadi.Fetcher.get_game_state(game_id) do
      {:ok, game_session} ->
        {:noreply,
         socket
         |> assign(:game_id, game_session.short_code)
         |> assign(:current_player_name, game_session.created_by)
        }

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Game not found")
         |> redirect(to: ~p"/")}
    end
  end
end
