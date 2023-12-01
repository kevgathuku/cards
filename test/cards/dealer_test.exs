defmodule Cards.DealerTest do
  use ExUnit.Case, async: true

  setup do
    registry = start_supervised!(Cards.Dealer)
    %{registry: registry}
  end

  test "generates a valid deck on init", %{registry: registry} do
    %{remaining: deck} = Cards.Dealer.report(registry)

    assert length(deck) == 52
    assert Enum.member?(deck, {:two, :hearts}) == true
    assert Enum.member?(deck, {:three, :diamonds}) == true
  end

  test "adds players to the game", %{registry: registry} do
    name = "iniesta"
    assert Cards.Dealer.lookup(registry, name) == :error

    Cards.Dealer.add_player(registry, name)
    player = Cards.Dealer.lookup(registry, name)

    assert player.name == name
    assert length(player.cards) == 4

    %{remaining: deck} = Cards.Dealer.report(registry)
    assert length(deck) == 48
  end
end
