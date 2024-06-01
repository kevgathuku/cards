defmodule Kadi.Games.Poker.FsmServer do
  @fsm """
  idle --> |start| lobby
  lobby --> |add_player| lobby
  lobby --> |add_player| awaiting_deck
  awaiting_deck --> |add_deck| awaiting_deal_cards
  awaiting_deal_cards --> |deal_player_cards| awaiting_start_card
  awaiting_start_card --> |deal_start_card| live
  live --> |play_hand| live
  live --> |pick| live
  live --> |play_hand| kadi
  kadi --> |play_finish_card| end_game
  """
  @listener (if Mix.env() == :test do
               Mox.defmock(Kadi.Games.Poker.FsmServer.Mox, for: Finitomata.Listener)
               Kadi.Games.Poker.FsmServer.Mox
             else
               nil
             end)

  use Finitomata, fsm: @fsm, syntax: :flowchart, listener: @listener

  alias Kadi.Games.Poker.Player

  @rules %{
    start_cards_blocklist: [:k, :q, :j, :a, :two, :three, :eight],
    # TODO: this should be a blocklist too
    finishing_cards: [:a, :two, :three, :four, :five, :six, :seven, :nine, :ten],
    min_players: 2,
    cards_to_deal: 4
  }

  @impl Finitomata
  def on_start(arg) do
    Logger.info("start_link: Kadi.Games.Poker.FsmServer. State: #{inspect(arg)}")
    :ignore
  end

  @impl Finitomata
  def on_transition(:idle, :start, _event_payload, state) do
    initial_state = %{
      players: [],
      deck: [],
      played: [],
      player_turn: 0
    }

    {:ok, :lobby, Map.merge(state, initial_state)}
  end

  @impl Finitomata
  def on_transition(:lobby, :add_player, player_name, %{players: players} = state) do
    if Enum.any?(players, fn player -> player.name == player_name end) do
      Logger.info("Player #{player_name} already exists")
      {:ok, :lobby, state}
    else
      Logger.info("Adding Player: #{player_name}")
      player = %Player{name: player_name, cards: []}
      updated_state = %{state | players: Enum.reverse([player | players])}

      next_event =
        if Enum.count(updated_state.players) >= @rules.min_players do
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
    {:ok, :awaiting_deal_cards, %{state | deck: init_deck}}
  end

  @impl Finitomata
  def on_transition(
        :awaiting_deal_cards,
        :deal_player_cards,
        _event_payload,
        %{players: players} = init_state
      ) do
    {updated_players, final_state} =
      Enum.map_reduce(players, init_state, fn player, acc_state ->
        {player_cards, remaining_deck} = Enum.split(acc_state.deck, @rules.cards_to_deal)
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
        %{deck: deck} = state
      ) do
    first_card =
      Enum.find(deck, fn card -> card.number not in @rules[:start_cards_blocklist] end)

    remaining = deck -- [first_card]

    {:ok, :live, %{state | deck: remaining, played: [first_card]}}
  end

  @impl Finitomata
  def on_transition(
        :live,
        :pick,
        _event_payload,
        %{player_turn: player_turn, players: players, deck: deck} =
          state
      ) do
    # Split the top card from the deck
    {picked, remaining_deck} = Enum.split(deck, 1)

    updated_players =
      players
      |> Enum.with_index()
      |> Enum.map(fn
        {player, index} when index == player_turn ->
          %{player | cards: player.cards ++ picked}

        {player, _index} ->
          player
      end)

    # Update the player turn to the next player
    next_player_turn = rem(player_turn + 1, length(players))

    {:ok, :live,
     %{state | deck: remaining_deck, player_turn: next_player_turn, players: updated_players}}
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

    cond do
      # played card is in the current player's cards
      Kadi.Utils.intersection(current_player.cards, played_hand) == played_hand ->
        # continue processing
        # process_played_hand(state, current_player, played_hand)
        unless Kadi.Utils.is_valid_hand?(hd(played), played_hand) do
          # Invalid hand. Go back to live
          # TODO: Introduce the concept of a 'fine'
          # Skip the current player. Go to the next player
          next_player_turn = rem(player_turn + 1, Enum.count(players))
          {:ok, :live, %{state | player_turn: next_player_turn}}
        end

        # Update the right player in the players array
        updated_players =
          players
          |> Enum.with_index()
          |> Enum.map(fn
            {player, index} when index == player_turn ->
              %{player | cards: player.cards -- played_hand}

            {value, _index} ->
              value
          end)

        # TODO: Verify the stack of played cards is updated correctly
        # player cards -> [2H, 2F, 5H, 8H]
        # hand -> [8H, 5H]
        # e.g. in this case the 5H should be the one on the top of the deck
        # Add the played cards to the played deck
        new_played = Enum.reverse(played_hand) ++ played

        # Update the player turn to the next player
        next_player_turn = rem(player_turn + 1, Enum.count(players))

        {:ok, :live,
         %{state | played: new_played, player_turn: next_player_turn, players: updated_players}}

      true ->
        # Invalid cards played. Probably a bug in the logic...
        # Go back to live. Same player should play again
        Logger.debug("Back to live. Invalid card")

        {:ok, :live, state}
    end
  end
end
