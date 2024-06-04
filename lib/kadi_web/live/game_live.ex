defmodule KadiWeb.GameLive do
  use KadiWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :hello, "Player One")}
  end

  def render(assigns) do
    ~H"""
    <section class="phx-hero">
      <h1 class="text-brand mt-10 flex items-center text-sm font-semibold leading-6">
      Welcome to Poker! <%= @hello %>!
      </h1>

      <button class="button">Start new game</button>
      <button class="button">Provide game code</button>
    </section>
    """
  end
end
