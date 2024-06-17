defmodule Kadi.Games.Registry do
  use GenServer

  @doc """
  Starts the registry.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Looks up the bucket pid for `name` stored in `server`.

  Returns `{:ok, pid}` if the bucket exists, `:error` otherwise.
  """
  def lookup(server, name) do
    GenServer.call(server, {:lookup, name})
  end

  @doc """
  Ensures there is a bucket associated with the given `name` in `server`.
  """
  def create(server, name) do
    GenServer.call(server, {:create, name})
  end

  ## Server callbacks

  @impl true
  def init(:ok) do
    games = %{}
    refs = %{}
    {:ok, {games, refs}}
  end

  def handle_call({:lookup, name}, _from, state) do
    {games, _} = state
    {:reply, Map.fetch(games, name), state}
  end

  @impl true
  def handle_call({:create, name}, _from, {games, refs}=state) do
    if Map.has_key?(games, name) do
      {:reply, name, state}
    else
      {:ok, game} = Finitomata.start_fsm(Kadi.Games.Poker.FsmServer, name, %{})
      ref = Process.monitor(game)
      refs = Map.put(refs, ref, name)
      games = Map.put(games, name, game)
      {:reply, name, {games, refs}}
    end
  end
end
