defmodule Games.Kadi.Dealer do
  @moduledoc """
  Card dealer module
  """
  use GenServer

  @default_state %{
    players: [],
    deck: [],
    direction: :clockwise,
    played: []
  }

  ## Client API
  @doc """
  Starts the registry.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Looks up the player with `name` stored in `server`.

  Returns `{:ok, player}` if the player exists, `:error` otherwise.
  """
  def lookup(server, name) do
    GenServer.call(server, {:lookup, name})
  end

  @doc """
  Report the state of the game, mainly who has which cards.
  """
  def report(server) do
    GenServer.call(server, :report)
  end

  @doc """
  Shuffle the cards
  """
  def shuffle(server) do
    GenServer.call(server, :shuffle)
  end

  @doc """
  Ensures there is a player associated with the given `name` in `server`.
  """
  def add_player(server, name) do
    GenServer.cast(server, {:add_player, name})
  end

  def create_deck do
    numbers = [
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      "K",
      "Q",
      "J",
      "A"
    ]

    suits = ~w(Hearts Flowers Diamonds Spades)

    for num <- numbers, suit <- suits, do: {num, suit}
  end

  # GenServer Callbacks
  @impl true
  def init(options) do
    # Merge default and provided config options
    %{num_players: num_players} = Map.merge(default_config(), Enum.into(options, %{}))

    deck = create_deck() |> Enum.shuffle()
    init_state = %{@default_state | deck: deck}

    state =
      Enum.reduce(1..num_players, init_state, fn num, state ->
        add_player_and_deal(state, "P:#{num}")
      end)

    # Assign start card
    state = assign_start_card(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:lookup, name}, _from, state) do
    player = Enum.find(state.players, :error, fn player -> player.name == name end)
    # should return a tuple: {:reply, response, state}
    {:reply, player, state}
  end

  @impl true
  def handle_call(:report, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:shuffle, _from, %{deck: deck} = state) do
    # {:reply, reply, state}
    new_state = %{state | deck: Enum.shuffle(deck)}
    {:reply, new_state, new_state}
  end

  # TODO: this does not need to be async
  @impl true
  def handle_cast({:add_player, name}, %{deck: deck, players: players} = state) do
    case Enum.find(players, fn player -> player.name == name end) do
      nil ->
        # Player does not exist
        {player_cards, remaining_deck} = Enum.split(deck, 4)

        # Deal 4 cards to the player
        player = %Games.Kadi.Player{name: name, cards: player_cards}

        {:noreply, %{state | players: [player | players], deck: remaining_deck}}

      _ ->
        {:noreply, state}
    end
  end

  defp default_config() do
    %{num_players: 2, start_cards_blocklist: ["A"]}
  end

  defp deal(%{deck: deck, players: players} = state, player) do
    {player_cards, remaining_deck} = Enum.split(deck, 4)

    updated_player = %{player | cards: player_cards}

    %{state | deck: remaining_deck, players: [updated_player | players]}
  end

  defp add_player_and_deal(state, name) do
    # TODO: Handle an existing player name better
    player = %Games.Kadi.Player{name: name, cards: []}
    deal(state, player)
  end

  defp allow_start_card?({num, _}) when num in [~c"A", ~c"K", ~c"J", ~c"Q"], do: false
  defp allow_start_card?(_), do: true

  defp assign_start_card(%{deck: deck} = state) do
    [first | _] = deck

    if allow_start_card?(first) do
      %{state | played: [first]}
    else
      assign_start_card(%{state | deck: Enum.shuffle(deck)})
    end
  end
end
