defmodule Games.Kadi.ServerTest do
  use ExUnit.Case, async: true
  alias Games.Kadi.Server
  doctest Games.Kadi.Server, import: true

  describe "init" do
    test "starts server on init with no options" do
      {:ok, state} = Server.init()

      assert state == %{players: [], deck: [], played: []}
    end
  end

  describe "add_players" do
    test "add player by name" do
      name = "iniesta"

      {:ok, init_state} = Server.init()
      {:ok, %{deck: deck, players: players}} = Server.add_player(init_state, name)
      player = Enum.find(players, fn player -> player.name == name end)

      assert player in players
      # No cards assigned at this point yet
      assert length(player.cards) == 0

      assert length(players) == 1
      assert length(deck) == 52
    end

    test "does not add duplicate players" do
      name = "iniesta"

      {:ok, init_state} = Server.init()
      {:ok, with_player_1} = Server.add_player(init_state, name)
      {:ok, %{players: players, deck: deck}} = Server.add_player(with_player_1, name)

      assert length(players) == 1
      assert length(deck) == 52
    end
  end

  describe "deal_start_cards_to_players" do
    test "assigns the right number of cards to each player" do
      state = %{
        deck: [1, 2, 3, 4, 5, 6, 7, 8],
        players: [
          %Games.Kadi.Player{name: "1", cards: []},
          %Games.Kadi.Player{name: "2", cards: []}
        ]
      }

      %{players: players, deck: deck} = Server.deal_start_cards_to_players(state)
      assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true
      assert length(deck) == 0
    end
  end

  describe "start_game" do
    test "assigns correct first card on start game" do
      {:ok, state} = Server.init()
      {:ok, with_player_1} = Server.add_player(state, "Kevin")
      {:ok, with_player_2} = Server.add_player(with_player_1, "King")

      {:ok, %{played: played, options: options}} = Server.start_game(with_player_2)

      card = hd(played)

      assert length(played) == 1
      refute card.number in options.start_cards_blocklist
    end

    test "deals 4 cards to each player on start game" do
      {:ok, state} = Server.init()
      {:ok, with_player_1} = Server.add_player(state, "Kevin")
      {:ok, with_player_2} = Server.add_player(with_player_1, "King")
      # {:ok, final_state} = Server.start_game(with_player_2)
      {:ok, %{players: players, deck: deck}} = Server.start_game(with_player_2)

      # %{players: players, deck: deck} = final_state

      assert length(players) == 2
      assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true
      assert length(deck) == 44
    end
  end

  # test "accepts a play from the next player", %{registry: registry} do
  #   {:ok, state} = Server.init()
  #   {:ok, with_player_1} = Server.add_player(state, "Boo")
  #   {:ok, with_player_2} = Server.add_player(with_player_1, "Doo")

  #   # TODO: Figure out a way to mock the cards to assign
  #   Server.play_hand(registry, "Boo", [])
  # end

  # test "does not accept a play from other players", %{registry: registry} do
  #   Server.add_player(registry, "Boo")
  #   Server.add_player(registry, "Doo")

  #   state_before = :sys.get_state(registry)

  #   # TODO: Figure out a way to mock the cards to assign
  #   Server.play_hand(registry, "Doo", [])
  #   state_after = :sys.get_state(registry)
  #   assert state_before == state_after
  # end
end
