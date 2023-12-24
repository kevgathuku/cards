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

  test "generates valid deck on init", %{registry: registry} do
    %{deck: deck, direction: direction} = Dealer.report(registry)

    assert direction == :clockwise
    assert length(deck) == 44
    assert Enum.member?(deck, {2, "Hearts"}) == true
    assert Enum.member?(deck, {2, "Diamonds"}) == true
    assert Enum.member?(deck, {2, "Spades"}) == true
    assert Enum.member?(deck, {2, "Flowers"}) == true
  end

  test "deals 4 cards to each player on init", %{registry: registry} do
    %{players: players} = Dealer.report(registry)

    assert length(players) == 2
    assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true
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
