defmodule Kadi.Registry do
  use GenServer

  require Logger
  alias Kadi.Games.Poker

  @doc """
  Starts the registry with the given options

  `:name` is always required.
  """
  def start_link(opts) do
    Logger.debug("Kadi.Registry opts: #{inspect(opts)}")
    server = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, server, opts)
  end

  @doc """
  Looks up the game pid for `name` stored in `server`.

  Returns `{:ok, pid}` if the game exists, `:error` otherwise.
  """
  def lookup(server, name) do
    # Lookup directly in ETS without a server call
    case :ets.lookup(server, name) do
      [{^name, pid}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Create or return the game associated with the given `name` in `server`.
  """
  def create(server, name, payload \\ %{}) do
    Logger.warning("Payload: #{inspect(payload)}")
    GenServer.call(server, {:create, name, payload})
  end

  # Server callbacks

  @impl true
  def init(table) do
    Logger.debug("Table name: #{inspect(table)}")
    names = :ets.new(table, [:named_table, read_concurrency: true])
    refs = %{}
    {:ok, {names, refs}}
  end

  @impl true
  def handle_call({:create, name, payload}, _from, {names, refs}) do
    case lookup(names, name) do
      {:ok, game} ->
        {:reply, game, {names, refs}}

      :error ->
        {:ok, game} = DynamicSupervisor.start_child(Kadi.GameSupervisor, {Poker.Server, payload})
        ref = Process.monitor(game)
        refs = Map.put(refs, ref, name)
        :ets.insert(names, {name, game})
        {:reply, game, {names, refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
    {name, refs} = Map.pop(refs, ref)
    :ets.delete(names, name)
    {:noreply, {names, refs}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in Kadi.Registry: #{inspect(msg)}")
    {:noreply, state}
  end
end
