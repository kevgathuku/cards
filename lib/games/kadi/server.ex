defmodule Games.Kadi.Server do
  @moduledoc """
  Kadi Game Server
  """
  require Logger
  alias Games.Kadi.Player

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
      finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
      min_players: 2,
      cards_to_deal: 4
    }
  end

  @doc """
  Add a player associated with the given `name` to the game

  ## Examples

      iex> add_player(%{players: []}, "lucho")
      {:ok, %{players: [%Games.Kadi.Player{name: "lucho", cards: []}]}}

      iex> add_player(%{players: [%Games.Kadi.Player{name: "lucho", cards: []}]}, "lucho")
      {:ok, %{players: [%Games.Kadi.Player{name: "lucho", cards: []}]}}
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

      {:ok, %{state | players: [player | players]}}
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

  def start_game(state) do
    deck = Utils.create_deck() |> Enum.shuffle()

    new_state =
      state
      |> Map.put(:deck, deck)
      |> Map.put(:stage, :playing)
      |> deal_start_cards_to_players()
      |> assign_start_card()

    {:ok, new_state}
  end

  def handle_hand(%{players: players, played: played} = state, player_name, cards) do
    # TODO: Just get the player at the head
    next_player = hd(players)
    starting_card = hd(played)

    if next_player.name != player_name do
      Logger.info("Invalid player passed to handle_hand")
      {:ok, state}
    else
      Logger.info("Evaluating cards: #{} from player: #{player_name}")

      if is_valid_hand?(starting_card, cards) do
        # Compute the next state based on the new hand
        # Remove the played cards from the player's cards
        # Add the played cards to the played deck
        new_played = played ++ cards

        # Move the player to the back of the queue
        updated_players = tl(players) ++ [next_player]

        {:ok, %{state | players: updated_players, played: new_played}}
      end
    end
  end

  @doc """
  Determine if the provided combination of cards is valid in this game

  ## Examples

      iex> is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [Games.Kadi.Card.new(:nine, :diamonds)])
      true

      iex> is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [Games.Kadi.Card.new(:nine, :hearts)])
      false

      iex> is_valid_hand?(
      ...> Games.Kadi.Card.new(:ten, :diamonds),
      ...> [Games.Kadi.Card.new(:five, :diamonds), Games.Kadi.Card.new(:five, :spades)])
      true

  """
  def is_valid_hand?(_, cards) when hd(cards).number == :a, do: true
  def is_valid_hand?(_, cards) when hd(cards).number == :eight and length(cards) == 1, do: false
  def is_valid_hand?(_, cards) when hd(cards).number == :q and length(cards) == 1, do: false

  def is_valid_hand?(last_card, cards) do
    cond do
      Utils.is_same_suit_or_number?(last_card, hd(cards)) and length(cards) == 1 ->
        # Validate single card of the same suit or number
        true

      Utils.is_same_suit_or_number?(last_card, hd(cards)) and Utils.is_same_number?(cards) ->
        # Is valid multi-card combo (same numbers)
        true

      true ->
        # TODO: Is valid Q and A combo
        # Do some pattern matching to check if it starts with '8' or 'Q'
        false
    end
  end

  # Deal the required number of cards to each player
  # Pass in the initial state, and returns the state with the right values
  def deal_start_cards_to_players(%{players: players, rules: rules} = init_state) do
    # The acc is the state itself
    {updated_players, final_state} =
      Enum.map_reduce(players, init_state, fn player, state ->
        {player_cards, remaining_deck} = Enum.split(state.deck, rules.cards_to_deal)
        # Update the player, and the deck
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
