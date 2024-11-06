defmodule Kadi.Games.Poker.ServerTest do
  use ExUnit.Case, async: true

  alias Kadi.Games.Poker.Server
  alias Kadi.Games.Poker.Card
  # alias Kadi.Games.Poker.Player
  doctest Server, import: true

  setup do
    registry = start_supervised!(Kadi.Registry)
    %{registry: registry}
  end

  test "are temporary workers" do
    assert Supervisor.child_spec(Server, %{}).restart == :temporary
  end

  describe "init" do
    test "starts server on init with no options", %{registry: registry} do
      Kadi.Registry.create(registry, "init")
      {:ok, game} = Kadi.Registry.lookup(registry, "init")

      {state, data} = Server.get_state(game)

      assert state == :lobby

      assert data == %{
               players: [],
               deck: [],
               played: [],
               player_turn: 0,
               rules: Server.default_rules()
             }
    end

    test "starts server on init with valid options", %{registry: registry} do
      Kadi.Registry.create(registry, "init_options", %{cards_to_deal: 5})
      {:ok, game} = Kadi.Registry.lookup(registry, "init_options")

      {state, data} = Server.get_state(game)

      assert state == :lobby

      assert Map.take(data, [:players, :deck, :played]) == %{players: [], deck: [], played: []}

      assert data.rules.cards_to_deal == 5
    end

    test "discards invalid rules and starts server on init", %{registry: registry} do
      Kadi.Registry.create(registry, "init", %{obviously_this_is_invalid: ~c"wowww"})
      {:ok, game} = Kadi.Registry.lookup(registry, "init")

      {_, data} = Server.get_state(game)

      assert Map.take(data, [:players, :deck, :played]) == %{players: [], deck: [], played: []}
      assert data.rules == Server.default_rules()
    end
  end

  describe "add_players" do
    test "add player by name", %{registry: registry} do
      name = "iniesta"
      Kadi.Registry.create(registry, "init")
      {:ok, game} = Kadi.Registry.lookup(registry, "init")

      Server.add_player(game, name)

      {_, %{players: players}} = Server.get_state(game)
      player = Enum.find(players, fn player -> player.name == name end)

      assert player in players
      # No cards assigned at this point yet
      assert length(player.cards) == 0
      assert length(players) == 1
    end

    test "does not add duplicate players", %{registry: registry} do
      name = "iniesta"

      Kadi.Registry.create(registry, "init")
      {:ok, game} = Kadi.Registry.lookup(registry, "init")

      Server.add_player(game, name)
      Server.add_player(game, name)

      {_, %{players: players}} = Server.get_state(game)

      assert length(players) == 1
    end
  end

  describe "start_game" do
    test "assigns the right number of cards to each player", %{registry: registry} do
      init_deck = [1, 2, 3, 4, 5, 6, 7, 8]

      Kadi.Registry.create(registry, "game")
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

      Server.add_player(game, "player 1")
      Server.add_player(game, "player 2")
      Server.start_game(game, init_deck)

      {state, %{players: players, deck: deck}} = Server.get_state(game)

      assert state == :live
      assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true
      assert length(deck) == 0
    end

    test "assigns correct first card on start game", %{registry: registry} do
      Kadi.Registry.create(registry, "game")
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

      Server.add_player(game, "Kevin")
      Server.add_player(game, "King")
      Server.start_game(game)

      {state, %{played: played, rules: rules, deck: deck}} = Server.get_state(game)

      card = hd(played)

      assert state == :live
      assert length(played) == 1
      assert card not in deck
      refute card.number in rules.start_cards_blocklist
    end

    test "deals 4 cards to each player by default on start game", %{registry: registry} do
      Kadi.Registry.create(registry, "game")
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

      Server.add_player(game, "Kevin")
      Server.add_player(game, "King")
      Server.start_game(game)

      {state, %{players: players, deck: deck, rules: %{cards_to_deal: cards_to_deal}}} =
        Server.get_state(game)

      # cards assigned to each player + starting card
      assigned_cards = length(players) * cards_to_deal + 1

      assert state == :live
      assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true
      assert length(deck) == 52 - assigned_cards
    end

    test "deals configured number of cards to each player on start game", %{registry: registry} do
      Kadi.Registry.create(registry, "game", %{cards_to_deal: 5})
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

      Server.add_player(game, "Kevin")
      Server.add_player(game, "King")
      Server.start_game(game)

      {state, %{players: players, deck: deck, rules: %{cards_to_deal: cards_to_deal}}} =
        Server.get_state(game)

      assigned_cards = length(players) * cards_to_deal + 1

      assert state == :live
      assert cards_to_deal == 5
      assert Enum.all?(players, fn player -> length(player.cards) == 5 end) == true
      assert length(deck) == 52 - assigned_cards
    end

    test "does not start game without minimum players", %{registry: registry} do
      Kadi.Registry.create(registry, "game")
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

      Server.add_player(game, "Kevin")
      Server.start_game(game)

      {state, _} = Server.get_state(game)

      # Does not progress to the next state
      assert state == :lobby
    end

    test "does not allow adding players after game starts", %{registry: registry} do
      Kadi.Registry.create(registry, "game")
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

      Server.add_player(game, "Kevin")
      Server.add_player(game, "King")
      Server.start_game(game)

      {state, %{players: players}} = Server.get_state(game)

      # Try to add a player after game is in progress
      Server.add_player(game, "Peppa")

      # Game is still live
      assert state == :live
      # No new players added
      assert length(players) == 2
    end
  end

  describe "play_hand" do
    test "accepts a play from the next player", %{registry: registry} do
      Kadi.Registry.create(registry, "game",  %{cards_to_deal: 3})
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

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
        Server.get_state(game)

      assert state == :live
      # Updated to the next player
      assert player_turn == 1
      assert hd(played) == hd(hand)

      player_one = Enum.find(players, fn player -> player.name == "Boo" end)
      assert length(player_one.cards) == 2
    end

    test "does not accept a play from other players", %{registry: registry} do
      Kadi.Registry.create(registry, "game", %{cards_to_deal: 3})
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

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

      # Card from player 2. Invalid - it is not their turn.
      hand = [
        %Card{suit: :flowers, number: :six}
      ]

      {_, %{played: initial_played, player_turn: initial_player_turn}} =
        Server.get_state(game)

      Server.play_hand(game, hand)

      {state, %{players: players, played: played, player_turn: player_turn}} =
        Server.get_state(game)

      # No state changes
      player_cards = Enum.reduce(players, 0, fn player, acc -> length(player.cards) + acc end)
      assert player_cards == 6

      assert state == :live
      assert player_turn == initial_player_turn
      assert initial_played == played
    end

    test "does not accept an invalid hand from the correct player", %{registry: registry} do
    end
  end

  describe "pick card" do
    test "assigns card to the next player", %{registry: registry} do
      init_deck = [
        # P1
        %Card{suit: :hearts, number: :two},
        %Card{suit: :hearts, number: :eight},
        %Card{suit: :flowers, number: :eight},
        %Card{suit: :flowers, number: :six},
        # P2
        %Card{suit: :diamonds, number: :eight},
        %Card{suit: :diamonds, number: :six},
        %Card{suit: :diamonds, number: :five},
        %Card{suit: :flowers, number: :five},
        # Start
        %Card{suit: :spades, number: :eight},
        %Card{suit: :spades, number: :four}
      ]

      Kadi.Registry.create(registry, "game")
      {:ok, game} = Kadi.Registry.lookup(registry, "game")

      Server.add_player(game, "Boo")
      Server.add_player(game, "Doo")

      Server.start_game(game, init_deck)

      {_,
       %{
         played: initial_played,
         player_turn: initial_player_turn,
         deck: initial_deck,
         players: initial_players
       }} =
        Server.get_state(game)

      initial_player = Enum.at(initial_players, initial_player_turn)
      initial_player_cards = initial_player.cards

      # Pick -> Assign 1 card (default) to the next player
      Server.deal_card(game)

      {state, %{players: players, played: played, player_turn: player_turn}} =
        Server.get_state(game)

      updated_player = Enum.at(players, initial_player_turn)

      # The topmost card is assigned to the next player
      assert hd(initial_deck) in updated_player.cards
      assert length(updated_player.cards) == length(initial_player_cards) + 1

      assert state == :live
      # Advances to the next player
      refute player_turn == initial_player_turn
      # No change in played cards
      assert initial_played == played
    end
  end
end
