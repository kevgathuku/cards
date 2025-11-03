defmodule Kadi.CardGames do
  @moduledoc """
  CardGames keeps the contexts common to all the card games

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  import Ecto.Query, warn: false
  alias Kadi.{Repo}
  alias Kadi.Accounts.Player
  alias Kadi.Games.{Card, Deck, DeckCard, GameSession, GameSessionPlayer}

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

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(:game_session, GameSession.changeset(game_session, %{status: "live"}))

    with {:ok, dealt_card_changesets, remaining_cards} <- deal_cards(players, deck_cards),
         {:ok, start_card_changeset, _final_cards} <- select_start_card(remaining_cards) do
      all_card_changesets = dealt_card_changesets ++ [start_card_changeset]

      multi_with_cards =
        Enum.reduce(all_card_changesets, multi, fn changeset, acc_multi ->
          Ecto.Multi.update(acc_multi, "card_#{changeset.data.id}", changeset)
        end)

      case Repo.transaction(multi_with_cards) do
        {:ok, %{game_session: updated_game_session}} ->
          KadiWeb.Endpoint.broadcast(
            "game:" <> to_string(updated_game_session.id),
            "game_updated",
            %{game_session: updated_game_session}
          )

          {:ok, updated_game_session}

        {:error, _failed_op, failed_value, _changes_so_far} ->
          {:error, failed_value}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp deal_cards(players, deck_cards) do
    cards_in_deck = Enum.filter(deck_cards, &(&1.location_type == "deck"))
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
        select: gsp.player_id

    Repo.all(from p in Player, where: p.id in subquery(query))
  end
end
