defmodule Kadi.CardGames do
  @moduledoc """
  CardGames keeps the contexts common to all the card games

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  import Ecto.Query, warn: false
  alias Kadi.{Repo}
  alias Kadi.Accounts.Player
  alias Kadi.Games.{Card, Deck, DeckCard, GameSession, GameSessionPlayer, PlayValidator}

  @suits ~w(hearts diamonds clubs spades)
  @ranks Enum.map(2..10, &to_string/1) ++ ~w(jack queen king ace)

  @doc """
  Returns the state of a specific game, with the game creator preloaded

  Takes the Game ID as a parameter to find the Game
  """
  def get_game_session(game_id) do
    case Repo.get(GameSession, game_id) do
      game_session when not is_nil(game_session) ->
        {:ok, game_session |> Repo.preload(:created_by)}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns all the Game Sessions that the player is a part of
  """
  def list_user_games(player_id) do
    # Get game_session_ids where player is a participant
    participant_query =
      from gsp in GameSessionPlayer,
        where: gsp.player_id == ^player_id,
        select: gsp.game_session_id

    query =
      from gs in GameSession,
        where: gs.id in subquery(participant_query),
        preload: [:created_by],
        order_by: [desc: gs.inserted_at]

    games = Repo.all(query)

    # Get the number of players in the Player's Game Sessions
    Enum.map(games, fn game ->
      player_count =
        Repo.aggregate(
          from(gsp in GameSessionPlayer, where: gsp.game_session_id == ^game.id),
          :count,
          :id
        )

      Map.put(game, :player_count, player_count)
    end)
  end

  @doc """
  Creates a new game session, with the player creating the game passed in
  """
  def create_game_session(player, attrs \\ %{}) do
    Repo.transaction(fn ->
      {:ok, game_session} =
        %GameSession{}
        |> GameSession.changeset(Map.merge(attrs, %{created_by_id: player.id, status: "lobby"}))
        |> Repo.insert()

      # Add creator as participant
      {:ok, _} =
        %GameSessionPlayer{}
        |> GameSessionPlayer.changeset(%{game_session_id: game_session.id, player_id: player.id})
        |> Repo.insert()

      # Create deck for the session
      {:ok, _deck} = create_deck_for_session(game_session)

      game_session |> Repo.preload(:created_by)
    end)
  end

  @doc """
  Add a player to an existing Game Session
  """
  def join_game_session(player, game_session_id) do
    case Repo.get(GameSession, game_session_id) do
      nil ->
        {:error, :not_found}

      game_session ->
        %GameSessionPlayer{}
        |> GameSessionPlayer.changeset(%{game_session_id: game_session.id, player_id: player.id})
        |> Repo.insert()
    end
  end

  ## Takes a GameSession and adds a deck and DeckCards to the session
  defp create_deck_for_session(game_session) do
    {:ok, deck} = Repo.insert(Deck.changeset(%Deck{}, %{game_session_id: game_session.id}))

    order_indices = Enum.shuffle(1..52)
    cards = generate_cards_attrs()

    Repo.transaction(fn ->
      Enum.zip([cards, order_indices])
      |> Enum.each(fn {card_attrs, order_index} ->
        {:ok, card} =
          case Repo.get_by(Card, card_attrs) do
            nil -> Repo.insert(Card.changeset(%Card{}, card_attrs))
            existing -> {:ok, existing}
          end

        # Create deck_cards entries, assigning an initial order
        deck_card_attrs = %{
          deck_id: deck.id,
          card_id: card.id,
          location_type: "deck",
          order_index: order_index
        }

        {:ok, _deck_card} = Repo.insert(DeckCard.changeset(%DeckCard{}, deck_card_attrs))
      end)
    end)

    # Optionally shuffle and record event
    {:ok, deck}
  end

  defp generate_cards_attrs() do
    for suit <- @suits, rank <- @ranks, do: %{suit: suit, rank: rank}
  end

  @doc """
  Starts a game session, deals cards to players and changes the status to "live"
  """
  def start_game(game_session) do
    players = get_game_session_players(game_session.id)

    if Enum.count(players) < 2 do
      {:error, :not_enough_players}
    else
      do_start_game(game_session, players)
    end
  end

  defp do_start_game(game_session, players) do
    game_session = game_session |> Repo.preload(deck: [deck_cards: :card])
    deck_cards = game_session.deck.deck_cards

    # Select a random player to start the turn
    random_player = Enum.random(players)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :game_session,
        GameSession.changeset(game_session, %{
          status: "live",
          current_turn_player_id: random_player.id
        })
      )

    with {:ok, dealt_card_changesets, remaining_cards} <- deal_cards(players, deck_cards),
         {:ok, start_card_changeset, _final_cards} <- select_start_card(remaining_cards) do
      all_card_changesets = dealt_card_changesets ++ [start_card_changeset]

      multi_with_cards =
        Enum.reduce(all_card_changesets, multi, fn changeset, acc_multi ->
          Ecto.Multi.update(acc_multi, "card_#{changeset.data.id}", changeset)
        end)

      case Repo.transaction(multi_with_cards) do
        {:ok, %{game_session: updated_game_session}} ->
          # Reload to get fresh deck_cards with updated locations
          reloaded_game_session =
            GameSession
            |> Repo.get!(updated_game_session.id)
            |> Repo.preload(:created_by)

          broadcast_game_update(reloaded_game_session)

          {:ok, reloaded_game_session}

        {:error, _failed_op, failed_value, _changes_so_far} ->
          {:error, failed_value}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Draws a card from the deck for the specified player.

  Validates that it's the player's turn, moves one card from deck to player's hand,
  advances turn to next player (by join order), and broadcasts update.

  Returns `{:ok, updated_game_session}` or `{:error, reason}`.

  ## Examples

      iex> draw_card_from_deck(game_session, player.id)
      {:ok, %GameSession{}}

      iex> draw_card_from_deck(game_session, wrong_player.id)
      {:error, :not_your_turn}

      iex> draw_card_from_deck(empty_deck_game, player.id)
      {:error, :deck_empty}
  """
  def draw_card_from_deck(game_session, player_id) do
    # 1. Preload necessary associations
    game_session =
      game_session
      |> Repo.preload([:created_by, deck: [deck_cards: :card]])

    # 2. Validate player's turn
    if game_session.current_turn_player_id != player_id do
      {:error, :not_your_turn}
    else
      # 3. Get deck cards and validate not empty
      deck_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "deck"))
        |> Enum.sort_by(& &1.order_index)

      case deck_cards do
        [] ->
          # Try recycling before returning error
          case recycle_played_stack(game_session) do
            {:ok, recycled_game_session} ->
              # Guard: verify deck has cards after recycle
              recycled_game_session =
                Repo.preload(recycled_game_session, [deck: [deck_cards: :card]], force: true)

              recycled_deck_cards =
                recycled_game_session.deck.deck_cards
                |> Enum.filter(&(&1.location_type == "deck"))
                |> Enum.sort_by(& &1.order_index)

              if Enum.empty?(recycled_deck_cards) do
                {:error, :deck_empty_after_recycle}
              else
                # Retry draw (will broadcast after success)
                draw_card_from_deck(recycled_game_session, player_id)
              end

            {:error, reason} ->
              # Cannot recycle - return error
              {:error, reason}
          end

        [card_to_draw | _] ->
          # 4. Get all players in order and calculate next player
          players = get_game_session_players(game_session.id)
          next_player = get_next_player(players, player_id)

          # 5. Build transaction
          multi =
            Ecto.Multi.new()
            |> Ecto.Multi.update(
              :deck_card,
              DeckCard.changeset(card_to_draw, %{
                location_type: "player_hand",
                player_id: player_id,
                order_index: nil
              })
            )
            |> Ecto.Multi.update(
              :game_session,
              GameSession.changeset(game_session, %{
                current_turn_player_id: next_player.id
              })
            )

          # 6. Execute transaction
          case Repo.transaction(multi) do
            {:ok, %{game_session: updated_game_session}} ->
              # 7. Reload with all associations
              reloaded_game_session =
                GameSession
                |> Repo.get!(updated_game_session.id)
                |> Repo.preload(:created_by)

              # 8. Broadcast update
              broadcast_game_update(reloaded_game_session)

              {:ok, reloaded_game_session}

            {:error, _failed_op, failed_value, _changes} ->
              {:error, failed_value}
          end
      end
    end
  end

  @doc """
  Recycles cards from the played stack back into the deck.

  Takes all cards from played_stack except the topmost card, shuffles them,
  assigns new order_index values (1..N), and moves them to deck location.

  Minimum 2 cards required in played stack (1 to recycle + 1 topmost to keep).

  Returns `{:ok, updated_game_session}` or `{:error, reason}`.

  ## Examples

      iex> recycle_played_stack(game_session)
      {:ok, %GameSession{}}

      iex> recycle_played_stack(one_card_game)
      {:error, :insufficient_cards_to_recycle}
  """
  def recycle_played_stack(game_session) do
    # 1. Preload associations
    game_session = Repo.preload(game_session, deck: [deck_cards: :card])

    # 2. Get played cards
    played_cards =
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "played_stack"))

    # 3. Validate minimum cards
    case length(played_cards) do
      0 -> {:error, :no_cards_in_played_stack}
      1 -> {:error, :insufficient_cards_to_recycle}
      _ -> do_recycle(game_session, played_cards)
    end
  end

  defp do_recycle(game_session, played_cards) do
    # 1. Identify topmost card (keep visible)
    topmost_card = Enum.max_by(played_cards, & &1.order_index)

    # 2. Get recyclable cards (all except topmost)
    recyclable_cards = Enum.reject(played_cards, &(&1.id == topmost_card.id))

    # 3. Shuffle and assign indices
    num_cards = length(recyclable_cards)
    shuffled_indices = Enum.shuffle(1..num_cards)

    # 4. Create changesets
    changesets =
      Enum.zip(recyclable_cards, shuffled_indices)
      |> Enum.map(fn {card, index} ->
        DeckCard.changeset(card, %{
          location_type: "deck",
          order_index: index,
          player_id: nil
        })
      end)

    # 5. Build and execute transaction
    multi =
      changesets
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {changeset, idx}, multi ->
        Ecto.Multi.update(multi, String.to_atom("recycle_card_#{idx}"), changeset)
      end)

    case Repo.transaction(multi) do
      {:ok, _results} ->
        # 6. Reload and return (NO BROADCAST - parent will handle)
        reloaded = Repo.get!(GameSession, game_session.id)
        {:ok, reloaded}

      {:error, _op, failed_value, _changes} ->
        {:error, failed_value}
    end
  end

  @doc """
  Plays one or more cards for the current player.

  Validates turn, card ownership, and play rules, then atomically updates game state.

  Returns `{:ok, updated_game_session}` or `{:error, reason}`.

  ## Examples

      iex> play_cards(game_session, player.id, [card_id])
      {:ok, %GameSession{}}

      iex> play_cards(game_session, wrong_player.id, [card_id])
      {:error, :not_your_turn}

      iex> play_cards(game_session, player.id, [invalid_card_id])
      {:error, :invalid_play}
  """
  def play_cards(game_session, player_id, card_ids) when is_list(card_ids) do
    with {:ok, game_session} <- get_game_session_preloaded(game_session),
         :ok <- validate_current_turn(game_session, player_id),
         {:ok, player} <- get_player_in_session(game_session, player_id),
         {:ok, cards_to_play} <- validate_player_has_cards(game_session, player, card_ids),
         {:ok, top_card} <- get_top_card(game_session),
         :ok <- validate_can_play(cards_to_play, top_card),
         {:ok, updated_game} <- execute_play(game_session, player, cards_to_play) do
      broadcast_game_update(updated_game)
      {:ok, updated_game}
    end
  end

  # Helper functions for play_cards/3

  defp get_game_session_preloaded(%GameSession{} = game_session) do
    preloaded =
      game_session
      |> Repo.preload([
        :top_card,
        :current_turn_player,
        :created_by,
        game_session_players: :player,
        deck: [deck_cards: :card]
      ])

    {:ok, preloaded}
  end

  defp get_game_session_preloaded(game_session_id) when is_integer(game_session_id) do
    case Repo.get(GameSession, game_session_id) do
      nil -> {:error, :game_not_found}
      game_session -> get_game_session_preloaded(game_session)
    end
  end

  defp get_player_in_session(game_session, player_id) do
    player =
      game_session.game_session_players
      |> Enum.find(&(&1.player_id == player_id))
      |> case do
        nil -> nil
        gsp -> gsp.player
      end

    case player do
      nil -> {:error, :player_not_in_game}
      player -> {:ok, player}
    end
  end

  defp validate_player_has_cards(game_session, player, card_ids) do
    # Get player's hand from deck_cards
    player_hand =
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player.id))
      |> Enum.map(& &1.card)

    # Find the requested cards
    cards_to_play =
      card_ids
      |> Enum.map(fn card_id ->
        Enum.find(player_hand, &(&1.id == card_id))
      end)

    # Check if all cards were found
    if Enum.any?(cards_to_play, &is_nil/1) do
      {:error, :cards_not_in_hand}
    else
      if PlayValidator.player_has_cards?(player_hand, cards_to_play) do
        {:ok, cards_to_play}
      else
        {:error, :cards_not_in_hand}
      end
    end
  end

  defp get_top_card(game_session) do
    case game_session.top_card do
      nil ->
        # Fallback: get from played_stack if top_card_id not set
        played_cards =
          game_session.deck.deck_cards
          |> Enum.filter(&(&1.location_type == "played_stack"))

        case Enum.max_by(played_cards, & &1.order_index, fn -> nil end) do
          nil -> {:error, :no_top_card}
          deck_card -> {:ok, deck_card.card}
        end

      top_card ->
        {:ok, top_card}
    end
  end

  defp validate_can_play(cards_to_play, top_card) do
    if PlayValidator.valid_play?(cards_to_play, top_card) do
      :ok
    else
      {:error, :invalid_play}
    end
  end

  defp execute_play(game_session, player, cards_to_play) do
    # Get current max order_index in played_stack
    max_order = get_max_played_stack_order(game_session)

    # Get next player
    players = get_game_session_players(game_session.id)
    next_player = get_next_player(players, player.id)

    # Build transaction
    multi = Ecto.Multi.new()

    # Move each card to played_stack
    multi_with_cards =
      cards_to_play
      |> Enum.with_index(1)
      |> Enum.reduce(multi, fn {card, idx}, acc_multi ->
        deck_card = find_player_deck_card(game_session, player.id, card.id)
        new_order = max_order + idx

        changeset =
          DeckCard.changeset(deck_card, %{
            location_type: "played_stack",
            order_index: new_order,
            player_id: nil
          })

        Ecto.Multi.update(acc_multi, {:move_card, idx}, changeset)
      end)

    # Update game_session with new top_card and turn
    last_card = List.last(cards_to_play)

    multi_with_game =
      Ecto.Multi.update(
        multi_with_cards,
        :game_session,
        GameSession.changeset(game_session, %{
          top_card_id: last_card.id,
          current_turn_player_id: next_player.id
        })
      )

    # Execute transaction
    case Repo.transaction(multi_with_game) do
      {:ok, %{game_session: updated_game}} ->
        # Reload with fresh associations
        reloaded =
          GameSession
          |> Repo.get!(updated_game.id)
          |> Repo.preload(:created_by)

        {:ok, reloaded}

      {:error, _op, failed_value, _changes} ->
        {:error, failed_value}
    end
  end

  defp get_max_played_stack_order(game_session) do
    game_session.deck.deck_cards
    |> Enum.filter(&(&1.location_type == "played_stack"))
    |> Enum.map(& &1.order_index)
    |> Enum.max(fn -> 0 end)
  end

  defp find_player_deck_card(game_session, player_id, card_id) do
    game_session.deck.deck_cards
    |> Enum.find(&(&1.player_id == player_id and &1.card_id == card_id))
  end

  defp broadcast_game_update(game_session) do
    KadiWeb.Endpoint.broadcast(
      "game:" <> to_string(game_session.id),
      "game_updated",
      %{game_session: game_session}
    )
  end

  defp deal_cards(players, deck_cards) do
    # Sort by randomized order_index to ensure non-sequential distribution
    cards_in_deck =
      deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.sort_by(& &1.order_index)

    cards_to_deal_count = Enum.count(players) * 4

    if Enum.count(cards_in_deck) < cards_to_deal_count do
      {:error, :not_enough_cards_in_deck}
    else
      {cards_to_deal, remaining_cards} = Enum.split(cards_in_deck, cards_to_deal_count)

      changesets =
        Enum.with_index(players)
        |> Enum.flat_map(fn {player, i} ->
          start_index = i * 4
          end_index = start_index + 3
          player_cards = Enum.slice(cards_to_deal, start_index..end_index)

          Enum.map(player_cards, fn card ->
            DeckCard.changeset(card, %{
              location_type: "player_hand",
              player_id: player.id,
              order_index: nil
            })
          end)
        end)

      {:ok, changesets, remaining_cards}
    end
  end

  defp select_start_card(deck_cards) do
    special_ranks = ["2", "3", "jack", "queen", "king", "ace"]
    shuffled_cards = Enum.shuffle(deck_cards)

    start_card =
      Enum.find(shuffled_cards, fn deck_card ->
        deck_card.card.rank not in special_ranks
      end)

    if start_card do
      changeset = DeckCard.changeset(start_card, %{location_type: "played_stack", order_index: 1})
      remaining_cards = List.delete(deck_cards, start_card)
      {:ok, changeset, remaining_cards}
    else
      {:error, :no_valid_start_card_found}
    end
  end

  defp get_game_session_players(game_session_id) do
    query =
      from gsp in GameSessionPlayer,
        where: gsp.game_session_id == ^game_session_id,
        order_by: [asc: gsp.inserted_at],
        select: gsp.player_id

    Repo.all(from p in Player, where: p.id in subquery(query))
  end

  # Returns the next player in turn order after the current player.
  #
  # Players are ordered by join time (inserted_at), and the order wraps around
  # (last player → first player).
  #
  # ## Examples
  #
  #     iex> players = [player1, player2, player3]
  #     iex> get_next_player(players, player2.id)
  #     player3
  #
  #     iex> get_next_player(players, player3.id)
  #     player1  # wraps around
  defp get_next_player(players, current_player_id) do
    current_index = Enum.find_index(players, &(&1.id == current_player_id))
    next_index = rem(current_index + 1, length(players))
    Enum.at(players, next_index)
  end

  # Validates if the given player is the current turn player.
  #
  # ## Parameters
  # - game_session: GameSession struct with current_turn_player_id
  # - player_id: ID of the player attempting the action
  #
  # ## Returns
  # - `:ok` if it's the player's turn
  # - `{:error, :not_your_turn}` otherwise
  #
  # ## Examples
  #
  #     iex> validate_current_turn(game_session, current_player.id)
  #     :ok
  #
  #     iex> validate_current_turn(game_session, other_player.id)
  #     {:error, :not_your_turn}
  defp validate_current_turn(game_session, player_id) do
    if game_session.current_turn_player_id == player_id do
      :ok
    else
      {:error, :not_your_turn}
    end
  end
end
