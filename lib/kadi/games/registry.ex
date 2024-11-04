defmodule Kadi.Games.Registry do
  @doc """
  Looks up the game pid for `name` stored in `server`.

  Returns `{:ok, pid}` if the bucket exists, `:error` otherwise.
  """
  def lookup(name) do
    case Finitomata.lookup(name) do
      pid when is_pid(pid) -> {:ok, pid}
      _ -> :error
    end
  end

  @doc """
  Create or return the game associated with the given `name` in `server`.
  """
  def create(name, payload) do
    existing_game = Finitomata.lookup(name)

    if existing_game == nil do
      Finitomata.start_fsm(Kadi.Games.Poker.FsmServer, name, payload)
    else
      {:ok, existing_game}
    end
  end
end
