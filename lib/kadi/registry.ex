defmodule Kadi.Registry do
  use GenServer

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
    GenServer.cast(server, {:create, name, payload})
  end

  # Server callbacks

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:lookup, name}, _from, names) do
    {:reply, Map.fetch(names, name), names}
  end

  @impl true
  def handle_cast({:create, name, payload}, names) do
    if Map.has_key?(names, name) do
      {:noreply, names}
    else
      {:ok, game} =
        GenStateMachine.start_link(Poker.Server, payload,
          name: {:via, Registry, {Kadi.Registry, name}}
        )

      {:noreply, Map.put(names, name, game)}
    end
  end
end
