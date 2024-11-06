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

  test "can create and lookup games with payload", %{registry: registry} do
    assert Kadi.Registry.lookup(registry, "game_one") == :error

    Kadi.Registry.create(registry, "game_one", %{cards_to_deal: 5})
    assert {:ok, game} = Kadi.Registry.lookup(registry, "game_one")

    {state, data} = Poker.Server.get_state(game)
    assert state == :lobby
    assert data.rules.cards_to_deal == 5
  end

  test "removes games on exit", %{registry: registry} do
    Kadi.Registry.create(registry, "game")
    {:ok, game} = Kadi.Registry.lookup(registry, "game")
    GenServer.stop(game)
    assert Kadi.Registry.lookup(registry, "game") == :error
  end

  test "removes bucket on crash", %{registry: registry} do
    Kadi.Registry.create(registry, "game")
    {:ok, game} = Kadi.Registry.lookup(registry, "game")

    # Stop the bucket with non-normal reason
    GenStateMachine.stop(game, :shutdown)
    assert Kadi.Registry.lookup(registry, "game") == :error
  end
end
