defmodule Kadi.Games.Poker.Server do
  @moduledoc """
  Kadi Game Server
  """
  use GenStateMachine, restart: :temporary

  require Logger
  alias Kadi.Games.Poker.Player
  alias Kadi.Utils

  @type state :: :lobby | :awaiting_start | :playing | :finish

  @initial_state %{
    players: [],
    deck: [],
    played: [],
    player_turn: 0
  }

  @init_rules %{
    start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
    # TODO: this should be a blocklist too
    finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
    min_players: 2,
    cards_to_deal: 4
  }

  def default_rules, do: @init_rules

  @doc """
  Start the server.
  Accepts any custom rules you want to apply

  ## Examples

      iex> init()
      {:ok, :lobby, %{
        players: [],
        deck: [],
        played: [],
        player_turn: 0,
        rules: %{
          start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
          finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
          min_players: 2,
          cards_to_deal: 4
        }
      }}

      iex> init(%{cards_to_deal: 5})
      {:ok, :lobby, %{
        players: [],
        deck: [],
        played: [],
        player_turn: 0,
        rules: %{
          start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
          finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
          min_players: 2,
          cards_to_deal: 5
        }
      }}
  """
  def init(rules \\ %{}) do
    # Merge default and provided rules options
    valid_rules =
      @init_rules
      |> Map.merge(Enum.into(rules, %{}))
      # Take only the valid keys
      |> Map.take(Map.keys(@init_rules))

    # Return {:ok, state, data}
    {:ok, :lobby, Map.put(@initial_state, :rules, valid_rules)}
  end

  def start_link(payload) do
    GenStateMachine.start_link(__MODULE__, payload)
  end

  @doc """
  Add a player associated with the given `name` to the game
  """
  def add_player(pid, player_name) do
    GenStateMachine.cast(pid, {:add_player, player_name})
  end

  @doc """
  Get the player associated with the given `name`
  """
  def get_player(pid, player_name) do
    GenStateMachine.call(pid, {:get_player, player_name})
  end

  @doc """
  Get the current state of the game
  """
  def get_state(pid) do
    :sys.get_state(pid)
  end

  @doc """
  Starts the game.

  Generate a deck, or use one if provided
  Assign the right number of cards to the players
  Play the start card
  """
  def start_game(pid, deck \\ %{}) do
    GenStateMachine.cast(pid, {:start_game, deck})
  end

  @doc """
  Process a hand played by one of the players
  Advance the turn
  """
  def play_hand(pid, hand) do
    GenStateMachine.cast(pid, {:play_hand, hand})
  end

  @doc """
  Deal card(s) to the next player.
  Default no. of cards to deal is 1, unless different value is specified
  Advance the turn
  """
  def deal_card(pid, num_cards \\ 1) do
    GenStateMachine.cast(pid, {:deal_cards, num_cards})
  end

  def stop(pid) do
    GenStateMachine.stop(pid)
  end

  # Server (callbacks)
  def handle_event(:cast, {:add_player, name}, :lobby, %{players: players} = data) do
    if Enum.any?(players, fn player -> player.name == name end) do
      Logger.info("Player #{name} already exists")
      {:next_state, :lobby, data}
    else
      Logger.info("Adding Player: #{name}")
      player = %Player{name: name, cards: []}

      {:next_state, :lobby, %{data | players: Enum.reverse([player | players])}}
    end
  end

  def handle_event(:cast, {:add_player, _}, :live, data) do
    Logger.warning("Cannot add more players. Game already started!")

    {:next_state, :live, data}
  end

  def handle_event(:cast, {:start_game, _}, state, %{players: players, rules: rules} = data)
      when length(players) < rules.min_players do
    Logger.warning(
      "Not enough players, Current: #{length(players)} Expected: #{rules.min_players}"
    )

    {:next_state, state, data}
  end

  def handle_event(:cast, {:start_game, _}, state, data)
      when state != :lobby do
    Logger.warning(
      "Invalid state for start game. Expected: #{inspect(:lobby)} \tActual:#{inspect(state)}"
    )

    {:next_state, state, data}
  end

  def handle_event(:cast, {:start_game, deck}, :lobby, data) do
    # If deck is not provided, create a new one and shuffle it
    start_deck =
      if Enum.empty?(deck) do
        Utils.create_deck() |> Enum.shuffle()
      else
        deck
      end

    new_data =
      data
      |> Map.put(:deck, start_deck)
      |> Map.put(:stage, :playing)
      |> deal_start_cards_to_players()
      |> assign_start_card()

    {:next_state, :live, new_data}
  end

  def handle_event(
        :cast,
        {:play_hand, hand},
        :live,
        %{players: players, played: played, player_turn: player_turn} = data
      ) do
    # Get the player who should be playing the current turn
    current_player = Enum.at(players, player_turn)

    cond do
      Enum.member?(current_player.cards, hd(hand)) ->
        # Last played card
        last_card = hd(played)

        if Utils.is_valid_hand?(last_card, hand) do
          new_state = process_played_hand(data, current_player, hand)
          {:next_state, :live, new_state}
        else
          {:error, message: "Invalid cards played"}
        end

      true ->
        # Played card includes cards not in the player's set of cards
        Logger.warning("How'd you play cards you don't have? Now that's a new trick")

        {:next_state, :live, data}
    end
  end

  def handle_event(
        :cast,
        {:deal_cards, num_cards},
        :live,
        %{deck: deck, player_turn: player_turn, players: players} = data
      ) do
    # Get the current player
    current_player = Enum.at(players, player_turn)

    # Get the top card from the deck
    {picked, remaining_deck} = Enum.split(deck, num_cards)

    # Update the player in the players array
    updated_players =
      players
      |> Enum.map(fn
        player when player.name == current_player.name ->
          %{player | cards: player.cards ++ picked}

        player ->
          player
      end)

    # Update the player turn to the next player
    next_player_turn = rem(player_turn + 1, length(players))

    {:next_state, :live,
     %{data | deck: remaining_deck, player_turn: next_player_turn, players: updated_players}}
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

    Logger.warning("process_played_hand: player_turn: #{player_turn}")

    # Update the player in the players array
    updated_players =
      players
      |> Enum.map(fn
        player when player.name == updated_player.name -> updated_player
        value -> value
      end)

    # TODO: Verify the stack of played cards is updated correctly
    # player cards -> [2H, 2F, 5H, 8H]
    # hand -> [8H, 5H]
    # e.g. in this case the 5H should be the one on the top of the deck
    # Add the played cards to the played deck
    new_played = Enum.reverse(hand) ++ played

    # Update the player turn to the next player
    next_player_turn = rem(player_turn + 1, Enum.count(players))

    %{state | played: new_played, player_turn: next_player_turn, players: updated_players}
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
