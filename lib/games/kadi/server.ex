defmodule Games.Kadi.Server do
  @moduledoc """
  Kadi Game Server
  """
  require Logger
  alias Games.Kadi.{Card, Player}

  @default_config %{
    start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
    finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
    num_players: 2
  }

  @default_state %{
    players: [],
    deck: [],
    played: []
  }

  def init(options \\ %{}) do
    # Merge default and provided config options
    final_options = Map.merge(@default_config, Enum.into(options, %{}))

    deck = Utils.create_deck() |> Enum.shuffle()

    state =
      @default_state
      |> Map.put(:deck, deck)
      |> Map.put(:options, final_options)

    {:ok, state}
  end

  @doc """
  Add a player associated with the given `name` to the game

  ## Examples

      iex> add_player(%{players: []}, "lucho")
      {:ok, %{players: [%Games.Kadi.Player{name: "lucho", cards: []}]}}
  """
  def add_player(%{players: players} = state, name) do
    if player_exists?(state, name) do
      Logger.info("Player #{name} already exists")
      {:ok, state}
    else
      Logger.info("Adding Player: #{name}")
      player = %Player{name: name, cards: []}

      {:ok, %{state | players: [player | players]}}
    end
  end

  def player_exists?(%{players: players} = _state, name) do
    Enum.any?(players, fn player -> player.name == name end)
  end

  @doc """
  Starts the game.
  """
  def start_game(%{players: players} = state) do
    # TODO: Do any initial setup here
    # Deal x cards to the players
    # Play the starting card
    state =
      Enum.reduce(players, state, fn x, acc -> deal(acc, x, 4) end)
      |> assign_start_card()

    {:ok, state}
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

      iex> is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [Games.Kadi.Card.new(:eight, :diamonds), Games.Kadi.Card.new(:nine, :diamonds)])
      true

      iex> is_valid_hand?(Games.Kadi.Card.new(:ten, :diamonds), [Games.Kadi.Card.new(:q, :diamonds), Games.Kadi.Card.new(:nine, :diamonds)])
      true
  """
  def is_valid_hand?(starting_card, cards) do
    # First check
    Utils.is_same_suit_or_number?(starting_card, hd(cards))
    # Is valid single card
    # Is valid multi-card combo (same suit)
    # Is valid multi-card combo (same numbers)
    # Is valid Q and A combo
    # Do some pattern matching to check if it starts with '8' or 'Q'
  end

  defp deal(%{deck: deck, players: players} = state, player, num_cards) do
    {player_cards, remaining_deck} = Enum.split(deck, num_cards)
    {_, remaining} = Enum.split_with(players, fn x -> x.name == player.name end)

    updated_player = %{player | cards: player_cards ++ player.cards}
    %{state | deck: remaining_deck, players: [updated_player | remaining]}
  end

  @spec allow_start_card?(Card.t()) :: boolean()
  defp allow_start_card?(card) do
    card.number not in @default_config[:start_cards_blocklist]
  end

  defp assign_start_card(%{deck: deck} = state) do
    [first | _] = deck

    if allow_start_card?(first) do
      %{state | played: [first]}
    else
      assign_start_card(%{state | deck: Enum.shuffle(deck)})
    end
  end
end
