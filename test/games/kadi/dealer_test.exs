defmodule Games.Kadi.DealerTest do
  use ExUnit.Case, async: true
  alias Games.Kadi.Dealer

  setup context do
    # Read the :num_players tag value
    case context do
      %{num_players: num_players} ->
        registry = start_supervised!({Dealer, [num_players: num_players]})
        %{registry: registry}
      _ ->
        registry = start_supervised!(Dealer)
        %{registry: registry}
    end
  end

  test "generates valid state on init", %{registry: registry} do
    %{deck: deck, players: players, direction: direction} = Dealer.report(registry)

    assert length(deck) == 44
    assert length(players) == 2
    assert direction == :clockwise
  end

  @tag num_players: 3
  test "adds specified number of players to the game", %{registry: registry} do
    %{deck: deck, players: players, direction: direction} = Dealer.report(registry)

    assert length(players) == 3
    assert length(deck) == 40
    assert direction == :clockwise
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
