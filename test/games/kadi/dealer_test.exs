defmodule Games.Kadi.DealerTest do
  use ExUnit.Case, async: true
  alias Games.Kadi.Dealer

  setup do
    registry = start_supervised!(Dealer)
    %{registry: registry}
  end

  test "generates valid state on init", %{registry: registry} do
    %{deck: deck, players: players} = Dealer.report(registry)

    assert length(deck) == 44
    assert length(players) == 2
  end

  test "adds players to the game", %{registry: registry} do
    name = "iniesta"
    assert Dealer.lookup(registry, name) == :error

    Dealer.add_player(registry, name)
    player = Dealer.lookup(registry, name)

    assert player.name == name
    assert length(player.cards) == 4

    %{deck: deck, players: players} = Dealer.report(registry)
    assert length(players) == 3
    assert length(deck) == 40
  end

  test "does not add duplicate players", %{registry: registry} do
    name = "iniesta"

    Dealer.add_player(registry, name)
    Dealer.add_player(registry, name)

    %{deck: deck, players: players} = Dealer.report(registry)
    assert length(players) == 3
    assert length(deck) == 40
  end
end
