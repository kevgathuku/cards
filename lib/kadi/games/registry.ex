defmodule Kadi.Games.Registry do
  use GenServer

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:lookup, name}, _from, games) do
    {:reply, Map.fetch(games, name), games}
  end

  @impl true
  def handle_call({:create, name}, _from, games) do
    if Map.has_key?(games, name) do
      {:reply, games}
    else
      {:ok, game} = Finitomata.start_fsm Kadi.Games.Poker.FsmServer, name, %{}
      {:reply, game, Map.put(games, name, game)}
    end
  end
end
