defmodule Kadi.Games.Poker.Server do
  @moduledoc """
  Kadi Game Server
  """
  require Logger
  alias Kadi.Games.Poker.Player
  alias Kadi.Utils

  @type stage :: :lobby | :playing | :finish

  @initial_state %{
    players: [],
    deck: [],
    played: [],
    player_turn: 0,
    stage: :lobby
  }

  @doc """
  Initiate the server.
  Accept any custom rules you want to apply

  ## Examples

      iex> init()
      {:ok, %{
        players: [],
        deck: [],
        played: [],
        stage: :lobby,
        player_turn: 0,
        rules: %{
          start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
          finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
          min_players: 2,
          cards_to_deal: 4
        }
      }}

      iex> init(%{cards_to_deal: 5})
      {:ok, %{
        players: [],
        deck: [],
        played: [],
        stage: :lobby,
        player_turn: 0,
        rules: %{
          start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
          finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
          min_players: 2,
          cards_to_deal: 5
        }
      }}
  """
  def init(options \\ %{}) do
    # Merge default and provided rules options
    valid_rules =
      default_rules()
      |> Map.merge(Enum.into(options, %{}))
      # Take only the valid keys
      |> Map.take(Map.keys(default_rules()))

    {:ok, Map.put(@initial_state, :rules, valid_rules)}
  end

  def default_rules() do
    %{
      start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
      # TODO: this should be a blocklist too
      finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
      min_players: 2,
      cards_to_deal: 4
    }
  end

  @doc """
  Add a player associated with the given `name` to the game

  ## Examples

      iex> add_player(%{players: []}, "lucho")
      {:ok, %{players: [%Kadi.Games.Poker.Player{name: "lucho", cards: []}]}}

      iex> add_player(%{players: [%Kadi.Games.Poker.Player{name: "lucho", cards: []}]}, "lucho")
      {:ok, %{players: [%Kadi.Games.Poker.Player{name: "lucho", cards: []}]}}
  """
  def add_player(%{stage: current_stage}, _name) when current_stage != :lobby,
    do: {:error, stage: "Invalid game state: #{current_stage}"}

  def add_player(%{players: players} = state, name) do
    if Enum.any?(players, fn player -> player.name == name end) do
      Logger.info("Player #{name} already exists")
      {:ok, state}
    else
      Logger.info("Adding Player: #{name}")
      player = %Player{name: name, cards: []}

      {:ok, %{state | players: Enum.reverse([player | players])}}
    end
  end

  @doc """
  Starts the game.

  Generate a deck
  Assign the right number of cards to the players
  Play the start card
  """
  def start_game(%{players: players, rules: rules}) when length(players) < rules.min_players,
    do: {:error, players: "Not enough players"}

  def start_game(state, deck \\ []) do
    start_deck =
      if Enum.empty?(deck) do
        # If deck is not provided, create a new one and shuffle it
        Utils.create_deck() |> Enum.shuffle()
      else
        deck
      end

    new_state =
      state
      |> Map.put(:deck, start_deck)
      |> Map.put(:stage, :playing)
      |> deal_start_cards_to_players()
      |> assign_start_card()

    {:ok, new_state}
  end

  def handle_hand(
        %{players: players, played: played, player_turn: player_turn} = state,
        hand
      ) do
    # Get the player who should be playing the current turn
    current_player = Enum.at(players, player_turn)

    cond do
      Enum.member?(current_player.cards, hd(hand)) ->
        # Last played card before the current turn
        last_card = hd(played)

        if Utils.is_valid_hand?(last_card, hand) do
          process_played_hand(state, current_player, hand)
        else
          {:error, message: "Invalid cards played"}
        end

      true ->
        # Played card includes cards not in the player's set of cards
        {:error, message: "Wrong player. Cannot parse cards"}
    end
  end

  defp process_played_hand(
         %{
           players: players,
           played: played,
           player_turn: player_turn
         } = state,
         current_player,
         hand
       ) do
    # Compute the next state based on the new hand:
    # Update the player's cards
    remaining_player_cards = current_player.cards -- hand
    updated_player = %{current_player | cards: remaining_player_cards}

    # Update the player in the players array
    players
    |> Enum.with_index()
    |> Enum.map(fn
      {_player, index} when index == player_turn -> updated_player
      {value, _index} -> value
    end)

    # TODO: Verify the stack of played cards is updated correctly
    # player cards -> [2H, 2F, 5H, 8H]
    # hand -> [8H, 5H]
    # e.g. in this case the 5H should be the one on the top of the deck
    # Add the played cards to the played deck
    new_played = Enum.reverse(hand) ++ played

    # Update the player turn to the next player
    next_player_turn = rem(player_turn + 1, Enum.count(players))

    {:ok, %{state | played: new_played, player_turn: next_player_turn}}
  end

  # Deal the required number of cards to each player
  # Pass in the initial state, and returns the state with the right values
  def deal_start_cards_to_players(%{players: players, rules: rules} = init_state) do
    # The acc is the state itself
    {updated_players, final_state} =
      Enum.map_reduce(players, init_state, fn player, state ->
        {player_cards, remaining_deck} = Enum.split(state.deck, rules.cards_to_deal)
        # Update the player, and the deck
        Logger.info("Assigning cards: #{inspect(player_cards)} Player: #{player.name}")
        updated_player = %{player | cards: player_cards}
        updated_state = %{state | deck: remaining_deck}
        # {result, accumulator}
        {updated_player, updated_state}
      end)

    %{final_state | players: updated_players}
  end

  defp assign_start_card(%{deck: deck, rules: rules} = state) do
    first_card =
      Enum.find(deck, fn card -> card.number not in rules[:start_cards_blocklist] end)

    remaining = Enum.filter(deck, fn card -> card != first_card end)

    %{state | deck: remaining, played: [first_card]}
  end
end
