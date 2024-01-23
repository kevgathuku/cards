defmodule Games.Kadi.ServerTest do
  use ExUnit.Case, async: true
  alias Games.Kadi.Server

  setup context do
    # Read the :num_players tag value
    case context do
      %{num_players: num_players} ->
        %{state: %{num_players: num_players}}

      _ ->
        # registry = start_supervised!(Dealer)
        %{registry: registry}
    end
  end

  test "generates valid deck on init", %{registry: registry} do
    %{deck: deck} = :sys.get_state(registry)

    suits = ~w(Hearts Flowers Diamonds Spades)

    assert length(deck) == 52
    assert Enum.all?(deck, fn {_, suit} -> Enum.member?(suits, suit) end)
  end

  test "deals 4 cards to each player on start game", %{registry: registry} do
    Dealer.add_player(registry, "Kevin")
    Dealer.add_player(registry, "King")
    Dealer.start_game(registry)

    %{players: players, deck: deck} = :sys.get_state(registry)

    assert length(players) == 2
    assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true
    assert length(deck) == 44
  end

  test "assigns correct first card on start" do
    Dealer.add_player("Kevin")
    Dealer.add_player("King")
    %{played: played} = Dealer.start_game()

    {num, _} = hd(played)

    assert length(played) == 1
    refute num in [?A, ?K, ?J, ?Q, 2, 3, 8]
  end

  test "add player by name", %{registry: registry} do
    name = "iniesta"

    %{deck: deck, players: players} = Dealer.add_player(registry, name)
    player = Enum.find(players, fn player -> player.name == name end)

    assert player in players
    assert player.name == name
    # No cards assigned at this point yet
    assert length(player.cards) == 0

    assert length(players) == 1
    assert length(deck) == 52
  end

  test "does not add duplicate players", %{registry: registry} do
    name = "iniesta"

    Dealer.add_player(registry, name)
    Dealer.add_player(registry, name)

    %{deck: deck, players: players} = :sys.get_state(registry)
    assert length(players) == 1
    assert length(deck) == 52
  end

  test "accepts a play from the next player", %{registry: registry} do
    Dealer.add_player(registry, "Boo")
    Dealer.add_player(registry, "Doo")

    # TODO: Figure out a way to mock the cards to assign
    Dealer.play_hand(registry, "Boo", [])
  end

  test "does not accept a play from other players", %{registry: registry} do
    Dealer.add_player(registry, "Boo")
    Dealer.add_player(registry, "Doo")

    state_before = :sys.get_state(registry)

    # TODO: Figure out a way to mock the cards to assign
    Dealer.play_hand(registry, "Doo", [])
    state_after = :sys.get_state(registry)
    assert state_before == state_after
  end
end
