defmodule Games.Kadi.Player do
  @moduledoc """
  A struct representing a player in the game.
  TODO: This concept can be abstracted away. A player is common in each game.
  How can it be reused between different games?
  """
  defstruct [:name, :cards]

  def play_hand(server, player, cards) do
    # Choose from the available cards. Send to server.
    # GenServer.call(server, {:play_hand, player, cards})
  end
end
