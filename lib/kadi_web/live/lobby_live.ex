defmodule KadiWeb.LobbyLive do
  use KadiWeb, :live_view
  alias Kadi.Fetcher

  on_mount {KadiWeb.PlayerAuth, :mount_current_player}

  def mount(_params, _session, socket) do
    current_player = socket.assigns.current_player
    games = Fetcher.list_user_games(current_player.id)
    {:ok, assign(socket, games: games, current_player: current_player)}
  end
end
