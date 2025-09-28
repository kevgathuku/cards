defmodule KadiWeb.GameLive do
  use KadiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, game_session: nil)}
  end

  @impl true
  def handle_params(%{"game_id" => game_id}, _uri, socket) do
    case Kadi.Fetcher.get_game_session(game_id) do
      {:ok, game_session} ->
        {:noreply,
         socket
         |> assign(:game_session, game_session)
        }

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Game not found")
         |> redirect(to: ~p"/lobby")}
    end
  end
end
