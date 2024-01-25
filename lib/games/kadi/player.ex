defmodule Games.Kadi.Player do
  @moduledoc """
  A struct representing a player in the game.
  """
  defstruct [:name, :cards]

  def play_hand(_server, _player, _cards) do
    # Choose from the available cards. Send to server.
    # GenServer.call(server, {:play_hand, player, cards})
  end
end
