defmodule Games.Kadi.FsmServer do
  @fsm """
  idle --> |start| lobby
  lobby --> |add_player| lobby
  lobby --> |add_player| awaiting_deck
  awaiting_deck --> |add_deck| awaiting_player_cards
  awaiting_player_cards --> |deal_player_cards| awaiting_start_card
  awaiting_start_card --> |deal_start_card| live
  live --> |play_hand| live
  live --> |play_hand| kadi
  kadi --> |play_finish_card| end_game
  """
  @listener (if Mix.env() == :test do
               Mox.defmock(Games.Kadi.FsmServer.Mox, for: Finitomata.Listener)
               Games.Kadi.FsmServer.Mox
             else
               nil
             end)

  use Finitomata, fsm: @fsm, syntax: :flowchart, listener: @listener

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
  def on_transition(:idle, :start, event_payload, _state) do
    valid_rules =
      @default_rules
      |> Map.merge(Enum.into(event_payload, %{}))
      # Take only the valid keys
      |> Map.take(Map.keys(@default_rules))

    {:ok, :lobby, Map.put(@initial_state, :rules, valid_rules)}
  end

  @impl Finitomata
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

  @impl Finitomata
  def on_transition(
        :awaiting_deck,
        :add_deck,
        %{deck: init_deck} = _event_payload,
        state
      ) do
    {:ok, :awaiting_player_cards, %{state | deck: init_deck}}
  end

  @impl Finitomata
  def on_transition(
        :awaiting_player_cards,
        :deal_player_cards,
        _event_payload,
        %{players: players, rules: rules} = init_state
      ) do
    {updated_players, final_state} =
      Enum.map_reduce(players, init_state, fn player, acc_state ->
        {player_cards, remaining_deck} = Enum.split(acc_state.deck, rules.cards_to_deal)
        Logger.info("Assigning cards: #{inspect(player_cards)} to Player: #{player.name}")
        # Return the updated player, and update the deck in the state
        updated_player = %{player | cards: player_cards}
        updated_state = %{acc_state | deck: remaining_deck}

        # {result, accumulator}
        {updated_player, updated_state}
      end)

    {:ok, :awaiting_start_card, %{final_state | players: updated_players}}
  end

  @impl Finitomata
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

  @impl Finitomata
  def on_transition(
        :live,
        :play_hand,
        played_hand,
        %{player_turn: player_turn, players: players, played: played} =
          state
      ) do
    current_player = Enum.at(players, player_turn)

    unless Utils.intersection(current_player.cards, played_hand) == played_hand do
      # TODO: Confirm this works - add tests
      # Invalid cards played. Played hand should come from the player's cards
      # Go back to live. Same player should play again

      {:ok, :live, state}
    end

    unless Utils.is_valid_hand?(hd(played), played_hand) do
      # Invalid hand. Go back to live
      # TODO: Introduce the concept of a 'fine'
      # Skip the current player. Go to the next player
      next_player_turn = rem(player_turn + 1, Enum.count(players))
      {:ok, :live, %{state | player_turn: next_player_turn}}
    end

    # process_played_hand(state, current_player, played_hand)
    # Compute the next state based on the new hand:
    # Update the player's cards
    remaining_player_cards = current_player.cards -- played_hand
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
    new_played = Enum.reverse(played_hand) ++ played

    # Update the player turn to the next player
    next_player_turn = rem(player_turn + 1, Enum.count(players))

    {:ok, %{state | played: new_played, player_turn: next_player_turn}}
  end
end
