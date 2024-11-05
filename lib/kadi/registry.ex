defmodule Kadi.Registry do
  use GenServer

  require Logger
  alias Kadi.Games.Poker

  @doc """
  Starts the registry.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Looks up the game pid for `name` stored in `server`.

  Returns `{:ok, pid}` if the bucket exists, `:error` otherwise.
  """
  def lookup(server, name) do
    GenServer.call(server, {:lookup, name})
  end

  @doc """
  Create or return the game associated with the given `name` in `server`.
  """
  def create(server, name, payload \\ %{}) do
    Logger.warning("Payload: #{inspect(payload)}")
    GenServer.cast(server, {:create, name, payload})
  end

  # Server callbacks

  @impl true
  def init(:ok) do
    names = %{}
    refs = %{}
    {:ok, {names, refs}}
  end

  @impl true
  def handle_call({:lookup, name}, _from, state) do
    {names, _} = state
    {:reply, Map.fetch(names, name), state}
  end

  @impl true
  def handle_cast({:create, name, payload}, {names, refs}) do
    if Map.has_key?(names, name) do
      {:noreply, names}
    else
      {:ok, game} =
        GenStateMachine.start_link(Poker.Server, payload)

      ref = Process.monitor(game)
      refs = Map.put(refs, ref, name)
      names = Map.put(names, name, game)

      {:noreply, {names, refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
    {name, refs} = Map.pop(refs, ref)
    names = Map.delete(names, name)
    {:noreply, {names, refs}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in Kadi.Registry: #{inspect(msg)}")
    {:noreply, state}
  end
end
