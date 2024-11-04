defmodule Kadi.Games.Poker.ServerTest do
  use ExUnit.Case, async: true
  alias Kadi.Games.Poker.Server
  alias Kadi.Games.Poker.Card
  alias Kadi.Games.Poker.Player
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
      {state, data} = :sys.get_state(game)

      assert Map.take(data, [:players, :deck, :played]) == %{players: [], deck: [], played: []}
      assert data.rules == Server.default_rules()
    end
  end

  describe "add_players" do
    test "add player by name", %{game: game} do
      name = "iniesta"

      Server.add_player(game, name)
      {state, %{players: players}} = :sys.get_state(game)
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

      {state, %{players: players}} = :sys.get_state(game)

      assert length(players) == 1
    end
  end

  describe "deal_start_cards_to_players" do
    test "assigns the right number of cards to each player" do
      state = %{
        deck: [1, 2, 3, 4, 5, 6, 7, 8],
        players: [
          %Player{name: "1", cards: []},
          %Player{name: "2", cards: []}
        ],
        rules: Server.default_rules()
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

      {:ok, %{played: played, rules: rules, deck: deck}} = Server.start_game(with_player_2)

      card = hd(played)

      assert length(played) == 1
      assert card not in deck
      refute card.number in rules.start_cards_blocklist
    end

    test "deals 4 cards to each player by default on start game" do
      {:ok, %{rules: %{cards_to_deal: cards_to_deal}} = state} = Server.init()
      {:ok, with_player_1} = Server.add_player(state, "Kevin")
      {:ok, with_player_2} = Server.add_player(with_player_1, "King")
      {:ok, %{players: players, deck: deck}} = Server.start_game(with_player_2)

      # cards assigned to each player + starting card
      assigned_cards = length(players) * cards_to_deal + 1

      assert Enum.all?(players, fn player -> length(player.cards) == 4 end) == true

      assert length(deck) == 52 - assigned_cards
    end

    test "deals configured number of cards to each player on start game" do
      cards_to_deal = 5

      {:ok, state} =
        Server.init(%{
          cards_to_deal: cards_to_deal
        })

      {:ok, with_player_1} = Server.add_player(state, "Kevin")
      {:ok, with_player_2} = Server.add_player(with_player_1, "King")
      {:ok, %{players: players, deck: deck}} = Server.start_game(with_player_2)

      assigned_cards = length(players) * cards_to_deal + 1

      assert Enum.all?(players, fn player -> length(player.cards) == 5 end) == true
      assert length(deck) == 52 - assigned_cards
    end

    test "does not start game without minimum players" do
      {:ok, state} = Server.init()
      {:ok, with_player_1} = Server.add_player(state, "Kevin")

      {:error, errors} = Server.start_game(with_player_1)
      errors_map = errors |> Enum.into(%{})
      assert errors_map.players == "Not enough players"
    end

    test "does not allow adding players after game starts" do
      {:ok, state} = Server.init()
      {:ok, with_player_1} = Server.add_player(state, "Kevin")
      {:ok, with_player_2} = Server.add_player(with_player_1, "King")

      {:ok, game_state} = Server.start_game(with_player_2)

      # Try to add a player after game is in progress
      result = Server.add_player(game_state, "Kevin")

      assert match?({:error, _}, result)
    end

    test "can accept a custom deck" do
      {:ok, state} = Server.init(%{cards_to_deal: 2})
      {:ok, with_player_1} = Server.add_player(state, "Kevin")
      {:ok, with_player_2} = Server.add_player(with_player_1, "King")

      deck = [
        %Card{suit: :hearts, number: :two},
        %Card{suit: :hearts, number: :eight},
        %Card{suit: :flowers, number: :eight},
        %Card{suit: :flowers, number: :seven},
        %Card{suit: :diamonds, number: :eight},
        %Card{suit: :diamonds, number: :six}
      ]

      {:ok, %{players: players, deck: game_deck, played: played}} =
        Server.start_game(with_player_2, deck)

      player_cards = Enum.flat_map(players, fn player -> player.cards end)

      assert Enum.count(player_cards ++ game_deck ++ played) == Enum.count(deck)
    end
  end

  describe "handle_hand" do
    test "accepts a play from the next player" do
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

      hand = [
        %Card{suit: :hearts, number: :six}
      ]

      result =
        Server.handle_hand(started_game, hand)

      assert match?({:ok, _}, result)
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

    # test "does not accept an invalid hand from the correct player" do
    #   {:ok, state} = Server.init()
    #   {:ok, state_1} = Server.add_player(state, "Boo")
    #   {:ok, state_2} = Server.add_player(state_1, "Doo")
    # end
  end
end
