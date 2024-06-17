defmodule Kadi.Games.Registry do

  @doc """
  Looks up the bucket pid for `name` stored in `server`.

  Returns `{:ok, pid}` if the bucket exists, `nil` otherwise.
  """
  def lookup(name) do
    Finitomata.lookup(name)
  end

  @doc """
  Ensures there is a bucket associated with the given `name` in `server`.
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
