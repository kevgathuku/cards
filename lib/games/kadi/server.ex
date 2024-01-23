defmodule Games.Kadi.Server do
  @moduledoc """
  Card dealer module
  """
  require Logger

  @default_config %{
    start_cards_blocklist: [?K, ?Q, ?J, ?A, 2, 3, 8],
    num_players: 2
  }

  @default_state %{
    players: [],
    deck: [],
    played: []
  }

  ## Client API
  @doc """
  Starts the game.
  """
  def start_game(%{players: players} = state) do
    # TODO: Do any initial setup here
    # Deal x cards to the players
    # Play the starting card
    Enum.reduce(players, state, fn x, acc -> deal(acc, x, 4) end)
    |> assign_start_card()
  end

  @doc """
  Looks up the player with `name` stored in `server`.

  Returns `{:ok, player}` if the player exists, `:error` otherwise.
  """
  def get_player(state, name) do
    # GenServer.call(server, {:lookup, name})
  end

  @doc """
  Shuffle the cards
  """
  def shuffle(state) do
    # GenServer.call(server, :shuffle)
  end

  @doc """
  Add a player associated with the given `name` in `server`.
  """
  def add_player(%{players: players} = state, name) do
    case Enum.any?(players, fn player -> player.name == name end) do
      false ->
        # Player does not exist
        player = %Games.Kadi.Player{name: name, cards: []}

        new_state = %{state | players: [player | players]}

        {:ok, new_state}

      _ ->
        Logger.info("Player #{name} already exists")
        {:ok, state}
    end
  end

  def handle_hand(%{players: players} = state, player, cards) do
    player = Enum.find(players, fn x -> x.name == player end)
    # Is it the player's turn?
    # Is the hand valid?
    is_valid = is_valid_hand?(cards)
    # Compute the next state based on the new hand
  end

  def init(options) do
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
  Determine if the provided combination of cards is valid in this game
  """
  def is_valid_hand?(cards) do
    # TODO
  end

  defp check_cards(last_played, cards) do
  end

  defp deal(%{deck: deck, players: players} = state, player, num_cards) do
    {player_cards, remaining_deck} = Enum.split(deck, num_cards)
    {_, remaining} = Enum.split_with(players, fn x -> x.name == player.name end)

    updated_player = %{player | cards: player_cards ++ player.cards}
    %{state | deck: remaining_deck, players: [updated_player | remaining]}
  end

  defp allow_start_card?({num, _}) do
    num not in @default_config[:start_cards_blocklist]
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
