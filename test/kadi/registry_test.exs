defmodule Kadi.RegistryTest do
  use ExUnit.Case, async: true

  alias Kadi.Games.Poker

  setup do
    registry = start_supervised!(Kadi.Registry)
    %{registry: registry}
  end

  test "can create and lookup games", %{registry: registry} do
    assert Kadi.Registry.lookup(registry, "game_one") == :error

    Kadi.Registry.create(registry, "game_one")
    assert {:ok, game} = Kadi.Registry.lookup(registry, "game_one")

    {state, _data} = Poker.Server.get_state(game)
    assert state == :lobby
  end
end
