defmodule Games.Kadi.Dealer do
  @moduledoc """
  Card dealer module
  """
  use GenServer

  @default_state %{
    players: [],
    deck: []
  }

  ## Client API
  @doc """
  Starts the registry.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, default_config(), opts)
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
  Ensures there is a player associated with the given `name` in `server`.
  """
  def add_player(server, name) do
    GenServer.cast(server, {:add_player, name})
  end

  def create_deck do
    numbers = [
      :ace,
      :two,
      :three,
      :four,
      :five,
      :six,
      :seven,
      :eight,
      :nine,
      :ten,
      :king,
      :queen,
      :j
    ]

    suits = [:flowers, :diamonds, :hearts, :spades]

    for num <- numbers, suit <- suits, do: {num, suit}
  end

  # GenServer Callbacks
  @impl true
  def init(options) do
    deck = create_deck() |> Enum.shuffle()
    init_state = %{@default_state | deck: deck}

    # Check the options if there are custom configs
    %{num_players: num_players} =
      Map.merge(options, default_config()) |> Map.take([:num_players, :direction])

    state =
      Enum.reduce(1..num_players, init_state, fn num, state ->
        add_player_and_deal(state, "P:#{num}")
      end)

    {
      :ok,
      #  %{
      #    players: [],
      #    deck: remaining_deck,
      #    direction: direction
      #  }
      state
    }
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
  def handle_cast(:shuffle, state) do
    new_state =
      Map.put(
        state,
        "remaining",
        Enum.shuffle(state.remaining)
      )

    {:noreply, new_state, new_state}
  end

  # TODO: this does not need to be async
  @impl true
  def handle_cast({:add_player, name}, %{deck: deck, players: players} = state) do
    player = Enum.find(players, fn player -> player.name == name end)

    if player do
      {:noreply, state}
    else
      # {:ok, player} = Cards.Player.start_link([])
      # Deal 4 cards to the player
      {player_cards, remaining_deck} = Enum.split(deck, 4)

      player = %Games.Kadi.Player{name: name, cards: player_cards}

      {:noreply, %{state | players: [player | players], deck: remaining_deck}}
    end
  end

  defp default_config() do
    %{num_players: 2, direction: :clockwise}
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
end
