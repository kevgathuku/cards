defmodule Kadi.Games.Poker.ServerTest do
  use ExUnit.Case, async: true
  alias Kadi.Games.Poker.Server
  alias Kadi.Games.Poker.Card
  # alias Kadi.Games.Poker.Player
  doctest Server, import: true

  setup context do
    case context do
      %{payload: payload} ->
        {:ok, game} = GenStateMachine.start_link(Server, payload)
        %{game: game}

      _ ->
        # game = start_supervised!(Server)
        {:ok, game} = GenStateMachine.start_link(Server, %{})
        %{game: game}
    end
  end

  describe "init" do
    test "starts server on init with no options", %{game: game} do
      {state, data} = :sys.get_state(game)

      assert state == :lobby

      assert data == %{
               players: [],
               deck: [],
               played: [],
               player_turn: 0,
               rules: Server.default_rules()
             }
    end

    @tag payload: %{cards_to_deal: 5}
    test "starts server on init with valid options", %{game: game} do
      {state, data} = :sys.get_state(game)

      assert state == :lobby

      assert Map.take(data, [:players, :deck, :played]) == %{players: [], deck: [], played: []}

      assert data.rules.cards_to_deal == 5
    end

    @tag payload: %{obviously_this_is_invalid: ~c"wowww"}
    test "discards invalid rules and starts server on init", %{game: game} do
      {_, data} = :sys.get_state(game)

      assert Map.take(data, [:players, :deck, :played]) == %{players: [], deck: [], played: []}
      assert data.rules == Server.default_rules()
    end
  end

  describe "add_players" do
    test "add player by name", %{game: game} do
      name = "iniesta"

      Server.add_player(game, name)
      {_, %{players: players}} = :sys.get_state(game)
      player = Enum.find(players, fn player -> player.name == name end)

      assert player in players
      # No cards assigned at this point yet
      assert length(player.cards) == 0
      assert length(players) == 1
    end

    test "does not add duplicate players", %{game: game} do
      name = "iniesta"

      Server.add_player(game, name)
      Server.add_player(game, name)

      {_, %{players: players}} = :sys.get_state(game)

      assert length(players) == 1
    end
  end

  describe "start_game" do
    test "assigns the right number of cards to each player", %{game: game} do
      init_deck = [1, 2, 3, 4, 5, 6, 7, 8]

      Server.add_player(game, "player 1")
      Server.add_player(game, "player 2")
      Server.start_game(game, init_deck)

      {state, %{players: players, deck: deck}} = :sys.get_state(game)

      assert state == :live
      assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true
      assert length(deck) == 0
    end

    test "assigns correct first card on start game", %{game: game} do
      Server.add_player(game, "Kevin")
      Server.add_player(game, "King")
      Server.start_game(game)

      {state, %{played: played, rules: rules, deck: deck}} = :sys.get_state(game)

      card = hd(played)

      assert state == :live
      assert length(played) == 1
      assert card not in deck
      refute card.number in rules.start_cards_blocklist
    end

    test "deals 4 cards to each player by default on start game", %{game: game} do
      Server.add_player(game, "Kevin")
      Server.add_player(game, "King")
      Server.start_game(game)

      {state, %{players: players, deck: deck, rules: %{cards_to_deal: cards_to_deal}}} =
        :sys.get_state(game)

      # cards assigned to each player + starting card
      assigned_cards = length(players) * cards_to_deal + 1

      assert state == :live
      assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true
      assert length(deck) == 52 - assigned_cards
    end

    @tag payload: %{cards_to_deal: 5}
    test "deals configured number of cards to each player on start game", %{game: game} do
      Server.add_player(game, "Kevin")
      Server.add_player(game, "King")
      Server.start_game(game)

      {state, %{players: players, deck: deck, rules: %{cards_to_deal: cards_to_deal}}} =
        :sys.get_state(game)

      assigned_cards = length(players) * cards_to_deal + 1

      assert state == :live
      assert cards_to_deal == 5
      assert Enum.all?(players, fn player -> length(player.cards) == 5 end) == true
      assert length(deck) == 52 - assigned_cards
    end

    test "does not start game without minimum players", %{game: game} do
      Server.add_player(game, "Kevin")
      Server.start_game(game)

      {state, _} = :sys.get_state(game)

      # Does not progress to the next state
      assert state == :lobby
    end

    test "does not allow adding players after game starts", %{game: game} do
      Server.add_player(game, "Kevin")
      Server.add_player(game, "King")
      Server.start_game(game)

      {state, %{players: players}} = :sys.get_state(game)

      # Try to add a player after game is in progress
      Server.add_player(game, "Peppa")

      # Game is still live
      assert state == :live
      # No new players added
      assert length(players) == 2
    end
  end

  describe "play_hand" do
    @tag payload: %{cards_to_deal: 3}
    test "accepts a play from the next player", %{game: game} do
      Server.add_player(game, "Boo")
      Server.add_player(game, "Doo")

      deck = [
        # Player 1
        %Card{suit: :hearts, number: :five},
        %Card{suit: :hearts, number: :eight},
        %Card{suit: :hearts, number: :six},
        # Player 2
        %Card{suit: :flowers, number: :eight},
        %Card{suit: :flowers, number: :seven},
        %Card{suit: :flowers, number: :six},
        # Start card
        %Card{suit: :diamonds, number: :six},
        # Remaining stack
        %Card{suit: :diamonds, number: :eight}
      ]

      Server.start_game(game, deck)

      hand = [
        %Card{suit: :hearts, number: :six}
      ]

      Server.play_hand(game, hand)

      {state, %{players: players, played: played, player_turn: player_turn}} =
        :sys.get_state(game)

      assert state == :live
      # Updated to the next player
      assert player_turn == 1
      assert hd(played) == hd(hand)

      player_one = Enum.find(players, fn player -> player.name == "Boo" end)
      assert length(player_one.cards) == 2
    end

    test "does not accept a play from other players" do
      {:ok, state} = Server.init(%{cards_to_deal: 3})
      {:ok, state_1} = Server.add_player(state, "Boo")
      {:ok, state_2} = Server.add_player(state_1, "Doo")

      deck = [
        # Player 1
        %Card{suit: :hearts, number: :five},
        %Card{suit: :hearts, number: :eight},
        %Card{suit: :hearts, number: :six},
        # Player 2
        %Card{suit: :flowers, number: :eight},
        %Card{suit: :flowers, number: :seven},
        %Card{suit: :flowers, number: :six},
        # Start card
        %Card{suit: :diamonds, number: :six},
        # Remaining stack
        %Card{suit: :diamonds, number: :eight}
      ]

      {:ok, %{played: played} = started_game} = Server.start_game(state_2, deck)

      # Card from player 2. Invalid - it is not their turn.
      hand = [
        %Card{suit: :flowers, number: :six}
      ]

      result =
        Server.handle_hand(started_game, hand)

      assert match?({:error, _}, result)
    end

    test "does not accept an invalid hand from the correct player" do
    end
  end
end
