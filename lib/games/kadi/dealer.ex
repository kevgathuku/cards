defmodule Games.Kadi.Dealer do
  @moduledoc """
  Card dealer module
  """
  use GenServer

  ## Client API

  @doc """
  Starts the registry.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
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

    Enum.flat_map(numbers, fn number ->
      for suit <- suits, do: {number, suit}
    end)
  end

  # GenServer Callbacks
  @impl true
  def init(:ok) do
    {:ok,
     %{
       remaining: create_deck() |> Enum.shuffle(),
       players: []
     }}
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
    new_state = Map.put(
      state, "remaining", Enum.shuffle(state.remaining)
    )
    {:noreply, new_state, new_state}
  end

  @impl true
  def handle_cast({:add_player, name}, %{remaining: deck, players: players} = state) do
    player = Enum.find(players, fn player -> player.name == name end)
    if player do
      {:noreply, state}
    else
    # {:ok, player} = Cards.Player.start_link([])
    # Deal 4 cards to the player
    {player_cards, remaining_deck} = Enum.split(deck, 4)

    player = %Player{name: name, cards: player_cards}

    {:noreply, %{state | players: [player | players], remaining: remaining_deck}}
  end
  end
end
