defmodule Kadi.Games.RegistryTest do
  use ExUnit.Case, async: true

  test "can create and lookup games" do
    assert Kadi.Games.Registry.lookup("game_one") == :error

    assert {:ok, _game} = Kadi.Games.Registry.create("game_one", %{})
    # assert {:ok, game} = Registry.lookup(registry, "game_one")

    assert :ok = Finitomata.transition("game_one", :start)

    assert %{current: :lobby} = Finitomata.state "game_one"
  end
end
