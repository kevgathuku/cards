defmodule KadiWeb.LobbyLive do
  use KadiWeb, :live_view
  alias Kadi.Fetcher

  on_mount {KadiWeb.PlayerAuth, :mount_current_player}

  @impl true
  def mount(_params, _session, socket) do
    current_player = socket.assigns.current_player
    games = Fetcher.list_user_games(current_player.id)
    {:ok, assign(socket, games: games, current_player: current_player)}
  end

  @impl true
  def handle_event("create_game", _params, socket) do
    short_code = Ecto.UUID.generate()

    case Fetcher.create_game_session(socket.assigns.current_player, %{short_code: short_code}) do
      {:ok, game_session} ->

        {:noreply,
         socket
         |> put_flash(:info, "Game Session created!")
         |> redirect(to: ~p"/games/#{game_session.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        error_msg = changeset.errors
                    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
                    |> Enum.join(", ")
        {:noreply, put_flash(socket, :error, "Failed to create game: #{error_msg}")}
    end
  end
end
