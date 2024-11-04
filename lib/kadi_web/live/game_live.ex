defmodule KadiWeb.GameLive do
  use KadiWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :hello, "Player TWO")}
  end
end
