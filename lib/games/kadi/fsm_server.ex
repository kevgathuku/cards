defmodule FsmServer do
  @fsm """
  start --> |init| lobby
  lobby --> |add_player| lobby
  lobby --> |add_player| awaiting_deck
  awaiting_deck --> |add_deck| awaiting_player_cards
  awaiting_player_cards --> |deal_player_cards| awaiting_start_card
  awaiting_start_card --> |deal_start_card| live
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

  def on_transition(:lobby, :add_player, player_name, %{players: players, rules: rules} = state) do
    if Enum.any?(players, fn player -> player.name == player_name end) do
      Logger.info("Player #{player_name} already exists")
      {:ok, :lobby, state}
    else
      Logger.info("Adding Player: #{player_name}")
      player = %Player{name: player_name, cards: []}
      updated_state = %{state | players: Enum.reverse([player | players])}

      next_event =
        if Enum.count(updated_state.players) >= rules.min_players do
          # TODO: Better handle adding more than minimum players
          # Or enforce a defined number of players in the rules
          Logger.info("Enough Players: #{Enum.count(updated_state.players)}")
          :awaiting_deck
        else
          :lobby
        end

      {:ok, next_event, updated_state}
    end
  end

  def on_transition(
        :awaiting_deck,
        :add_deck,
        %{deck: init_deck} = _event_payload,
        state
      ) do
    {:ok, :awaiting_player_cards, %{state | deck: init_deck}}
  end

  def on_transition(
        :awaiting_player_cards,
        :deal_player_cards,
        _event_payload,
        %{players: players, rules: rules, deck: deck} = init_state
      ) do
    # Enough players to start. Deal the cards
    {updated_players, final_state} =
      Enum.map_reduce(players, init_state, fn player, state ->
        {player_cards, remaining_deck} = Enum.split(deck, rules.cards_to_deal)
        # Update the player, and the deck
        Logger.info("Assigning cards: #{inspect(player_cards)} to Player: #{player.name}")
        updated_player = %{player | cards: player_cards}
        updated_state = %{state | deck: remaining_deck}
        # {result, accumulator}
        # TODO: Check if updated state is enough here
        {updated_player, updated_state}
      end)

    {:ok, :awaiting_start_card, %{final_state | players: updated_players}}
  end

  def on_transition(
        :awaiting_start_card,
        :deal_start_card,
        _event_payload,
        %{deck: deck, rules: rules} = state
      ) do
    # TODO: Prevent double iteration over the deck here
    first_card =
      Enum.find(deck, fn card -> card.number not in rules[:start_cards_blocklist] end)

    remaining = Enum.filter(deck, fn card -> card != first_card end)

    {:ok, :live, %{state | deck: remaining, played: [first_card]}}
  end
end
