defmodule Kadi.CardGames do
  @moduledoc """
  Server-side gameplay engine for Kadi sessions.

  This context owns the full lifecycle for multiplayer games:

    * creates and joins game sessions backed by PostgreSQL records
    * deals cards, manages the deck, and tracks the played stack via `DeckCard`
    * advances turns while respecting table direction (clockwise / counter-clockwise)
    * applies special-card effects such as King direction reversal and Jack skip logic
    * transitions players into the `"cardless"` state when they play out with a Jack or King
    * emits telemetry events for analytics (e.g. `[:kadi, :jack, :skip_executed]`)

  Jack behaviour added in Feature 007 uses the existing King patterns: jack plays skip
  `N` players where `N` equals the number of jacks played, reuse the cardless workflow
  when a jack combo empties a hand, and never trigger a skip when a jack is selected as
  the starting card.

  ## Ace Card Special Action (Feature 008)

  Ace cards introduce suit selection mechanics:

    * Playing an Ace pauses the game and prompts the player to select a suit
    * The selected suit becomes mandatory for the next player's turn
    * Players must play a card matching the requested suit or draw from the deck
    * The suit requirement persists across draws and multiple turns until satisfied
    * Another Ace can override the current suit requirement
    * Aces can be played regardless of the current top card or active suit requirement
    * Multiple Aces played together only trigger one suit selection prompt

  Key functions: `select_suit/3` for suit selection after Ace play.
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
  Returns all players in a game session, ordered by join time.

  Players are ordered by the time they joined the game session (inserted_at),
  which determines turn order.

  ## Parameters
  - game_session_id: ID of the game session

  ## Returns
  - List of Player structs, ordered by join time

  ## Examples

      iex> get_game_session_players(game_session.id)
      [%Player{id: 1, email: "player1@example.com"}, %Player{id: 2, email: "player2@example.com"}]
  """
  def get_game_session_players(game_session_id) do
    query =
      from gsp in GameSessionPlayer,
        where: gsp.game_session_id == ^game_session_id,
        order_by: [asc: gsp.inserted_at],
        select: gsp.player_id

    Repo.all(from p in Player, where: p.id in subquery(query))
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
  def start_game(game_session, opts \\ []) do
    players = get_game_session_players(game_session.id)

    if Enum.count(players) < 2 do
      {:error, :not_enough_players}
    else
      do_start_game(game_session, players, opts)
    end
  end

  defp do_start_game(game_session, players, opts) do
    game_session = game_session |> Repo.preload(deck: [deck_cards: :card])
    deck_cards = game_session.deck.deck_cards

    # Select a random player to start the turn
    random_player = Enum.random(players)

    exclude_ranks = Keyword.get(opts, :exclude_ranks, [])

    with {:ok, dealt_card_changesets, remaining_cards} <-
           deal_cards(players, deck_cards, exclude_ranks),
         {:ok, start_card_changeset, _final_cards} <- select_start_card(remaining_cards) do
      # Get the start card's card_id for top_card_id
      start_card_id = start_card_changeset.data.card_id

      # Update game session with status, turn player, and top card
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :game_session,
          GameSession.changeset(game_session, %{
            status: "live",
            current_turn_player_id: random_player.id,
            top_card_id: start_card_id,
            direction: "clockwise"
          })
        )

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
                # Anomaly: No drawable cards after recycle (FR-018)
                # Skip player and advance turn
                players = get_game_session_players(recycled_game_session.id)

                next_player =
                  get_next_player_with_direction(
                    players,
                    player_id,
                    recycled_game_session.direction
                  )

                # Emit anomaly event
                emit_anomaly_skip_event(
                  recycled_game_session.id,
                  player_id,
                  "no_cards_after_recycle"
                )

                # Update game session with next player
                updated_game =
                  GameSession.changeset(recycled_game_session, %{
                    current_turn_player_id: next_player.id
                  })
                  |> Repo.update!()

                # Get player name for banner message
                player = Repo.get!(Kadi.Accounts.Player, player_id)

                # Broadcast anomaly banner (FR-019)
                broadcast_anomaly_banner(
                  updated_game,
                  "Deck exhausted. Skipping #{player.email} this turn."
                )

                # Broadcast game update
                broadcast_game_update(updated_game)

                {:ok, updated_game}
              else
                # Retry draw (will broadcast after success)
                draw_card_from_deck(recycled_game_session, player_id)
              end

            {:error, :insufficient_cards_to_recycle} ->
              # Anomaly: Cannot recycle (FR-018)
              # Skip player and advance turn
              players = get_game_session_players(game_session.id)

              next_player =
                get_next_player_with_direction(
                  players,
                  player_id,
                  game_session.direction
                )

              # Emit anomaly event
              emit_anomaly_skip_event(
                game_session.id,
                player_id,
                "insufficient_cards_to_recycle"
              )

              # Update game session with next player
              updated_game =
                GameSession.changeset(game_session, %{
                  current_turn_player_id: next_player.id
                })
                |> Repo.update!()

              # Get player name for banner message
              player = Repo.get!(Kadi.Accounts.Player, player_id)

              # Broadcast anomaly banner (FR-019)
              broadcast_anomaly_banner(
                updated_game,
                "Deck exhausted. Skipping #{player.email} this turn."
              )

              # Broadcast game update
              broadcast_game_update(updated_game)

              {:ok, updated_game}

            {:error, reason} ->
              # Other errors - return error
              {:error, reason}
          end

        [card_to_draw | _] ->
          # 4. Get all players in order and calculate next player
          players = get_game_session_players(game_session.id)
          next_player = get_next_player(players, player_id)

          # Check if player is cardless and handle auto-draw (FR-012)
          player_session =
            Repo.get_by!(GameSessionPlayer,
              game_session_id: game_session.id,
              player_id: player_id
            )

          is_cardless = player_session.status == "cardless"

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

          # If player was cardless, reset status (FR-013)
          multi_with_status =
            if is_cardless do
              Ecto.Multi.update(
                multi,
                :player_status,
                GameSessionPlayer.changeset(player_session, %{status: "normal"})
              )
            else
              multi
            end

          multi_with_game =
            Ecto.Multi.update(
              multi_with_status,
              :game_session,
              GameSession.changeset(game_session, %{
                current_turn_player_id: next_player.id
              })
            )

          # 6. Execute transaction
          case Repo.transaction(multi_with_game) do
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

  ## Error Codes

  - `:game_not_found` - Game session does not exist
  - `:not_your_turn` - Player attempted action out of turn
  - `:player_not_in_game` - Player is not a participant in this game session
  - `:cards_not_in_hand` - Player doesn't have all specified cards in hand
  - `:no_top_card` - No card on played stack (should not happen in normal gameplay)
  - `:invalid_play` - Play violates game rules:
    - Empty card list
    - Single card doesn't match suit or rank
    - Combo has different ranks
    - Combo's first card doesn't match top card

  ## Examples

      iex> play_cards(game_session, player.id, [card_id])
      {:ok, %GameSession{}}

      iex> play_cards(game_session, wrong_player.id, [card_id])
      {:error, :not_your_turn}

      iex> play_cards(game_session, player.id, [invalid_card_id])
      {:error, :cards_not_in_hand}

      iex> play_cards(game_session, player.id, [non_matching_card_id])
      {:error, :invalid_play}
  """
  def play_cards(game_session, player_id, card_ids) when is_list(card_ids) do
    require Logger

    Logger.info(
      "play_cards called: game_session_id=#{inspect(game_session.id)}, player_id=#{player_id}, card_ids=#{inspect(card_ids)}"
    )

    start_time = System.monotonic_time()

    result =
      with {:ok, game_session} <- get_game_session_preloaded(game_session),
           :ok <- validate_current_turn(game_session, player_id),
           {:ok, player} <- get_player_in_session(game_session, player_id),
           {:ok, cards_to_play} <- validate_player_has_cards(game_session, player, card_ids),
           {:ok, top_card} <- get_top_card(game_session),
           :ok <- validate_can_play(cards_to_play, top_card, game_session.action_suit),
           {:ok, updated_game} <- execute_play(game_session, player, cards_to_play) do
        broadcast_game_update(updated_game)
        {:ok, updated_game}
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:kadi, :card_games, :play_cards],
      %{duration: duration},
      %{
        game_session_id: game_session.id,
        player_id: player_id,
        card_count: length(card_ids),
        result: elem(result, 0)
      }
    )

    case result do
      {:ok, updated_game} ->
        Logger.info(
          "play_cards success: game_session_id=#{updated_game.id}, player_id=#{player_id}, duration_us=#{System.convert_time_unit(duration, :native, :microsecond)}"
        )

        result

      {:error, reason} ->
        Logger.warning(
          "play_cards failed: game_session_id=#{inspect(game_session.id)}, player_id=#{player_id}, reason=#{inspect(reason)}, duration_us=#{System.convert_time_unit(duration, :native, :microsecond)}"
        )

        result
    end
  end

  # ============================================================================
  # Query Helper Functions
  # ============================================================================

  @doc """
  Get all cards in a player's hand for a game session.

  Returns a list of `DeckCard` structs with card details preloaded.

  ## Examples

      iex> get_player_hand(game_session, player.id)
      [%DeckCard{card: %Card{rank: "5", suit: "hearts"}, ...}, ...]

      iex> get_player_hand(game_session, player.id)
      []
  """
  def get_player_hand(%GameSession{} = game_session, player_id) do
    from(dc in DeckCard,
      join: d in Deck,
      on: dc.deck_id == d.id,
      where: d.game_session_id == ^game_session.id
    )
    |> DeckCard.in_hand()
    |> DeckCard.for_player(player_id)
    |> DeckCard.with_card()
    |> Repo.all()
  end

  @doc """
  Get count of cards in a player's hand.

  ## Examples

      iex> count_player_cards(game_session, player.id)
      5

      iex> count_player_cards(game_session, player.id)
      0
  """
  def count_player_cards(%GameSession{} = game_session, player_id) do
    from(dc in DeckCard,
      join: d in Deck,
      on: dc.deck_id == d.id,
      where: d.game_session_id == ^game_session.id
    )
    |> DeckCard.in_hand()
    |> DeckCard.for_player(player_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Get cards of a specific rank in a player's hand.

  ## Examples

      iex> get_player_cards_by_rank(game_session, player.id, "jack")
      [%DeckCard{card: %Card{rank: "jack", suit: "hearts"}, ...}, ...]
  """
  def get_player_cards_by_rank(%GameSession{} = game_session, player_id, rank) do
    from(dc in DeckCard,
      join: d in Deck,
      on: dc.deck_id == d.id,
      where: d.game_session_id == ^game_session.id
    )
    |> DeckCard.in_hand()
    |> DeckCard.for_player(player_id)
    |> DeckCard.of_rank(rank)
    |> DeckCard.with_card()
    |> Repo.all()
  end

  @doc """
  Get count of cards remaining in the deck pile.

  ## Examples

      iex> count_deck_cards(game_session)
      42
  """
  def count_deck_cards(%GameSession{} = game_session) do
    from(dc in DeckCard,
      join: d in Deck,
      on: dc.deck_id == d.id,
      where: d.game_session_id == ^game_session.id
    )
    |> DeckCard.in_deck()
    |> Repo.aggregate(:count)
  end

  @doc """
  Get count of cards in the played stack.

  ## Examples

      iex> count_played_cards(game_session)
      10
  """
  def count_played_cards(%GameSession{} = game_session) do
    from(dc in DeckCard,
      join: d in Deck,
      on: dc.deck_id == d.id,
      where: d.game_session_id == ^game_session.id
    )
    |> DeckCard.played()
    |> Repo.aggregate(:count)
  end

  @doc """
  Get the top card from the played stack.

  Uses the game session's `top_card_id` to efficiently retrieve the DeckCard.

  ## Examples

      iex> get_top_played_card(game_session)
      {:ok, %DeckCard{card: %Card{rank: "5", suit: "hearts"}, ...}}

      iex> get_top_played_card(game_session)
      {:error, :no_cards_played}
  """
  def get_top_played_card(%GameSession{top_card_id: nil}), do: {:error, :no_cards_played}

  def get_top_played_card(%GameSession{} = game_session) do
    card =
      from(dc in DeckCard,
        join: d in Deck,
        on: dc.deck_id == d.id,
        where: d.game_session_id == ^game_session.id and dc.card_id == ^game_session.top_card_id
      )
      |> DeckCard.played()
      |> DeckCard.with_card()
      |> Repo.one()

    case card do
      nil -> {:error, :no_cards_played}
      card -> {:ok, card}
    end
  end

  # ============================================================================
  # Helper functions for play_cards/3
  # ============================================================================

  def get_game_session_preloaded(%GameSession{} = game_session) do
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

  def get_game_session_preloaded(game_session_id) when is_integer(game_session_id) do
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
      nil -> {:error, :no_top_card}
      top_card -> {:ok, top_card}
    end
  end

  defp validate_can_play(cards_to_play, top_card, action_suit) do
    opts = if action_suit, do: [action_suit: action_suit], else: []

    if PlayValidator.valid_play?(cards_to_play, top_card, opts) do
      :ok
    else
      {:error, :invalid_play}
    end
  end

  defp execute_play(game_session, player, cards_to_play) do
    require Logger

    # Get current max order_index in played_stack
    max_order = get_max_played_stack_order(game_session)

    # Detect special card plays
    ace_played? = Enum.any?(cards_to_play, &(&1.rank == "ace"))
    king_played? = Enum.any?(cards_to_play, &(&1.rank == "king"))
    jack_played? = Enum.any?(cards_to_play, &(&1.rank == "jack"))
    # Added for T004
    two_played? = Enum.any?(cards_to_play, &(&1.rank == "2"))
    jack_count = if jack_played?, do: length(cards_to_play), else: 0

    # Calculate new direction (FR-002)
    new_direction =
      if king_played? do
        reverse_direction(game_session.direction)
      else
        game_session.direction
      end

    # Calculate skip count for Jacks
    skip_count = if jack_played?, do: jack_count + 1, else: 1

    # Get players for turn calculation
    players = get_game_session_players(game_session.id)
    player_count = length(players)

    # Determine next player and action type
    {next_player, action_type} =
      if ace_played? do
        # When Ace is played, turn does not advance, awaits suit selection
        {game_session.current_turn_player, "select_suit"}
      else
        # Normal play: advance turn
        next_player =
          get_next_player_with_direction(players, player.id, new_direction, skip_count)

        {next_player, nil}
      end

    # Determine draw penalty for the next player if a '2' is played (T004)
    draw_penalty_update =
      if two_played? do
        %{active: true, count: 2, target_player_id: next_player.id}
      else
        # Keep existing penalty or clear if it was blocked by Ace (handled in later tasks)
        game_session.draw_penalty
      end

    # Check if player will be cardless after this play (FR-011, FR-012)
    player_hand = get_player_hand_count(game_session, player.id)
    cards_played_count = length(cards_to_play)
    will_be_cardless = player_hand == cards_played_count

    # Only Kings, Jacks, and '2' cards trigger cardless state
    # Note: Being cardless does NOT mean winning - the game continues
    # (Playing '2' as last card still applies penalty to next player)
    two_played? = Enum.any?(cards_to_play, fn card -> card.rank == "2" end)
    will_enter_cardless = will_be_cardless and (king_played? or jack_played? or two_played?)

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

    # Update game_session with new direction and turn (FR-002, FR-015)
    last_card = List.last(cards_to_play)

    multi_with_game =
      Ecto.Multi.update(
        multi_with_cards,
        :game_session,
        GameSession.changeset(game_session, %{
          top_card_id: last_card.id,
          current_turn_player_id: next_player.id,
          direction: new_direction,
          action_type: action_type,
          action_suit: nil,
          # Added for T004
          draw_penalty: draw_penalty_update
        })
      )

    # Update player status if cardless (FR-011, FR-026)
    multi_with_status =
      if will_enter_cardless do
        player_session =
          Repo.get_by!(GameSessionPlayer,
            game_session_id: game_session.id,
            player_id: player.id
          )

        Ecto.Multi.update(
          multi_with_game,
          :player_status,
          GameSessionPlayer.changeset(player_session, %{status: "cardless"})
        )
      else
        multi_with_game
      end

    # Execute transaction
    case Repo.transaction(multi_with_status) do
      {:ok, results} ->
        updated_game = results.game_session

        # Emit telemetry events (FR-020)
        if king_played? do
          emit_direction_change_event(
            game_session.id,
            player.id,
            game_session.direction,
            new_direction,
            last_card.id,
            # neutral flag for 2-player (FR-009)
            player_count == 2
          )
        end

        if jack_played? do
          emit_jack_skip_event(
            game_session.id,
            player.id,
            next_player.id,
            jack_count,
            Enum.map(cards_to_play, & &1.id)
          )
        end

        if will_enter_cardless do
          if jack_played? do
            emit_jack_cardless_event(game_session.id, player.id, last_card.id)
          else
            emit_cardless_event(game_session.id, player.id, last_card.id)
          end
        end

        # Reload with fresh associations
        reloaded =
          GameSession
          |> Repo.get!(updated_game.id)
          |> Repo.preload(:created_by)

        # Broadcast penalty activation if a '2' was played (T009)
        if two_played? do
          Phoenix.PubSub.broadcast(
            Kadi.PubSub,
            "game_session:#{reloaded.id}",
            {:draw_penalty_activated, %{game_session: reloaded}}
          )
        end

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

  # Helper to count player's hand.
  #
  # ## Parameters
  # - game_session: GameSession struct with preloaded deck.deck_cards
  # - player_id: ID of the player
  #
  # ## Returns
  # - Integer count of cards in player's hand
  defp get_player_hand_count(game_session, player_id) do
    game_session.deck.deck_cards
    |> Enum.count(&(&1.location_type == "player_hand" and &1.player_id == player_id))
  end

  defp broadcast_game_update(game_session) do
    KadiWeb.Endpoint.broadcast(
      "game:" <> to_string(game_session.id),
      "game_updated",
      %{game_session: game_session}
    )
  end

  defp deal_cards(players, deck_cards, exclude_ranks) do
    # Sort by randomized order_index to ensure non-sequential distribution
    cards_in_deck =
      deck_cards
      |> Enum.filter(&(&1.location_type == "deck"))
      |> Enum.filter(fn deck_card ->
        if exclude_ranks == [] do
          true
        else
          deck_card.card.rank not in exclude_ranks
        end
      end)
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
    # Per FR-003: Kings are allowed as start cards (no direction reversal occurs)
    # Aces are also allowed as start cards (player can play any suit, no suit selection required)
    # Other special cards (2, 3, 8, jack, queen) are excluded
    special_ranks = ["2", "3", "8", "jack", "queen"]
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

  # Returns the next player based on current game direction.
  #
  # In clockwise: player1 → player2 → player3 → player1
  # In counter_clockwise: player1 → player3 → player2 → player1
  #
  # For 2-player games, direction has no effect (FR-009).
  #
  # ## Parameters
  # - players: List of Player structs
  # - current_player_id: ID of the current player
  # - direction: "clockwise" or "counter_clockwise"
  #
  # ## Returns
  # - Player struct of the next player
  defp get_next_player_with_direction(players, current_player_id, direction, skip_count \\ 1) do
    player_count = length(players)
    current_index = Enum.find_index(players, &(&1.id == current_player_id))

    # Calculate offset based on direction and skip count
    offset =
      case direction do
        "clockwise" -> skip_count
        "counter_clockwise" -> -skip_count
      end

    # Handle wrap-around using modulo arithmetic. For negative offsets (counter-clockwise)
    # we need to add a positive multiple of player_count so the dividend stays ≥ 0 before
    # calling rem/2. Example: current_index = 0, offset = -2, player_count = 3 ⇒
    # rem(0 - 2 + 3 * 2, 3) = rem(4, 3) = 1 (player at index 1).
    next_index = rem(current_index + offset + player_count * abs(offset), player_count)

    Enum.at(players, next_index)
  end

  # Returns the previous player in the turn order.
  # Reverses the game direction.
  #
  # ## Parameters
  # - direction: Current direction ("clockwise" or "counter_clockwise")
  #
  # ## Returns
  # - Opposite direction string
  defp reverse_direction("clockwise"), do: "counter_clockwise"
  defp reverse_direction("counter_clockwise"), do: "clockwise"

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

  # Emits telemetry event for direction change.
  #
  # ## Parameters
  # - game_id: Game session ID
  # - player_id: Player who played the King
  # - old_dir: Previous direction
  # - new_dir: New direction after King play
  # - card_id: ID of the King card played
  # - neutral?: True for 2-player games (direction has no effect)
  defp emit_direction_change_event(game_id, player_id, old_dir, new_dir, card_id, neutral?) do
    :telemetry.execute(
      [:kadi, :king, :direction_change],
      %{},
      %{
        game_id: game_id,
        player_id: player_id,
        previous_direction: old_dir,
        new_direction: new_dir,
        card_id: card_id,
        neutral: neutral?,
        timestamp: DateTime.utc_now()
      }
    )
  end

  # Broadcasts anomaly banner notification to all players (FR-019).
  #
  # ## Parameters
  # - game_session: Current game session
  # - message: Banner message to display
  defp broadcast_anomaly_banner(game_session, message) do
    Phoenix.PubSub.broadcast(
      Kadi.PubSub,
      "game_session:#{game_session.id}",
      {:anomaly_banner, %{message: message, game_id: game_session.id}}
    )
  end

  # Emits telemetry event when player enters cardless state.
  #
  # ## Parameters
  # - game_id: Game session ID
  # - player_id: Player who became cardless
  # - card_id: ID of the King card played as last card
  defp emit_cardless_event(game_id, player_id, card_id) do
    :telemetry.execute(
      [:kadi, :king, :cardless_entered],
      %{},
      %{
        game_id: game_id,
        player_id: player_id,
        reason: "king_last_card",
        card_id: card_id,
        timestamp: DateTime.utc_now()
      }
    )
  end

  # Emits telemetry event when anomaly skip occurs.
  #
  # ## Parameters
  # - game_id: Game session ID
  # - player_id: Player who was skipped
  # - deck_state: Description of deck state causing skip
  defp emit_anomaly_skip_event(game_id, player_id, deck_state) do
    :telemetry.execute(
      [:kadi, :king, :anomaly_skip],
      %{},
      %{
        game_id: game_id,
        player_id: player_id,
        deck_state: deck_state,
        timestamp: DateTime.utc_now()
      }
    )
  end

  # Emits telemetry event when Jack skip is executed.
  #
  # ## Parameters
  # - game_id: Game session ID
  # - from_player_id: Player who played the Jack(s)
  # - to_player_id: Player who receives the turn after skip
  # - skip_count: Number of players skipped
  # - card_ids: List of Jack card IDs played
  defp emit_jack_skip_event(game_id, from_player_id, to_player_id, skip_count, card_ids) do
    :telemetry.execute(
      [:kadi, :jack, :skip_executed],
      %{skip_count: skip_count},
      %{
        game_session_id: game_id,
        player_id: from_player_id,
        from_player_id: from_player_id,
        to_player_id: to_player_id,
        jack_count: skip_count,
        card_ids: card_ids,
        timestamp: DateTime.utc_now()
      }
    )
  end

  # Emits telemetry event when player enters cardless state from Jack.
  #
  # ## Parameters
  # - game_id: Game session ID
  # - player_id: Player who became cardless
  # - card_id: ID of the Jack card played as last card
  defp emit_jack_cardless_event(game_id, player_id, card_id) do
    :telemetry.execute(
      [:kadi, :jack, :cardless_entered],
      %{},
      %{
        game_session_id: game_id,
        player_id: player_id,
        reason: "jack_last_card",
        card_id: card_id,
        timestamp: DateTime.utc_now()
      }
    )
  end

  @doc """
  Allows the current player to select a suit after playing an Ace.

  Validates that the game is in the "select_suit" state and the player is the
  current turn player. Updates the game state with the selected suit, advances
  the turn, and broadcasts the update.

  ## Parameters
  - game_session: The current game session
  - player_id: The ID of the player selecting the suit
  - suit: The suit being selected (e.g., "hearts")

  ## Returns
  - `{:ok, updated_game_session}`
  - `{:error, reason}`
  """
  def select_suit(game_session, player_id, suit) do
    with :ok <- validate_current_turn(game_session, player_id),
         :ok <- validate_action_type(game_session, "select_suit"),
         :ok <- validate_suit(suit) do
      players = get_game_session_players(game_session.id)
      next_player = get_next_player(players, player_id)

      game_session
      |> GameSession.changeset(%{
        action_type: nil,
        action_suit: suit,
        current_turn_player_id: next_player.id
      })
      |> Repo.update()
      |> case do
        {:ok, updated_game} ->
          reloaded_game = Repo.preload(updated_game, [:created_by])
          broadcast_game_update(reloaded_game)

          emit_ace_suit_selected_event(
            game_session.id,
            player_id,
            suit,
            reloaded_game.top_card_id
          )

          {:ok, reloaded_game}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp validate_action_type(game_session, expected_action) do
    if game_session.action_type == expected_action do
      :ok
    else
      {:error, :invalid_game_state}
    end
  end

  defp validate_suit(suit) do
    if suit in @suits do
      :ok
    else
      {:error, :invalid_suit}
    end
  end

  defp emit_ace_suit_selected_event(game_id, player_id, suit, top_card_id) do
    :telemetry.execute(
      [:kadi, :game, :ace_suit_selected],
      %{count: 1},
      %{
        game_id: game_id,
        player_id: player_id,
        suit: suit,
        top_card_id: top_card_id
      }
    )
  end
end
