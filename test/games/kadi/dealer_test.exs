defmodule Games.Kadi.DealerTest do
  use ExUnit.Case, async: true
  alias Games.Kadi.Dealer

  setup do
    registry = start_supervised!(Dealer)
    %{registry: registry}
  end

  test "generates a valid deck on init", %{registry: registry} do
    %{remaining: deck} = Dealer.report(registry)

    assert length(deck) == 52
    assert Enum.member?(deck, {:two, :hearts}) == true
    assert Enum.member?(deck, {:three, :diamonds}) == true
  end

  test "adds players to the game", %{registry: registry} do
    name = "iniesta"
    assert Dealer.lookup(registry, name) == :error

    Dealer.add_player(registry, name)
    player = Dealer.lookup(registry, name)

    assert player.name == name
    assert length(player.cards) == 4

    %{remaining: deck} = Dealer.report(registry)
    assert length(deck) == 48
  end

  test "does not add duplicate players", %{registry: registry} do
    name = "iniesta"

    Dealer.add_player(registry, name)
    Dealer.add_player(registry, name)

    %{remaining: deck, players: players} = Dealer.report(registry)
    assert length(players) == 1
    assert length(deck) == 48
  end
end
