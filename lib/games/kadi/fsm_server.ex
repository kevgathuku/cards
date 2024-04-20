defmodule FsmServer do
  @fsm """
  start --> |init| lobby
  lobby --> |add_player| lobby
  lobby --> |start_game| lobby
  lobby --> |start_game| live
  """
  use Finitomata, fsm: @fsm, syntax: :flowchart

  alias Games.Kadi.Player

  @initial_state %{
    players: [],
    deck: [],
    played: [],
    player_turn: 0
  }

  @default_rules %{
    start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
    # TODO: this should be a blocklist too
    finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
    min_players: 2,
    cards_to_deal: 4
  }

  @impl Finitomata
  def on_transition(:start, :init, event_payload, _state) do
    valid_rules =
      @default_rules
      |> Map.merge(Enum.into(event_payload, %{}))
      # Take only the valid keys
      |> Map.take(Map.keys(@default_rules))

    {:ok, :lobby, Map.put(@initial_state, :rules, valid_rules)}
  end

  def on_transition(:lobby, :add_player, player_name, %{players: players} = state) do
    if Enum.any?(players, fn player -> player.name == player_name end) do
      Logger.info("Player #{player_name} already exists")
      # Back to the lobby
      {:ok, :lobby, state}
    else
      Logger.info("Adding Player: #{player_name}")
      player = %Player{name: player_name, cards: []}

      {:ok, :lobby, %{state | players: Enum.reverse([player | players])}}
    end
  end

  def on_transition(
        :lobby,
        :start_game,
        _event_payload,
        %{players: players, rules: rules} = state
      )
      when length(players) < rules.min_players,
      do: {:ok, :lobby, state}

  def on_transition(
        :lobby,
        :start_game,
        _event_payload,
        %{players: players, rules: rules} = state
      )
      when length(players) >= rules.min_players,
      do: {:ok, :live, state}
end
