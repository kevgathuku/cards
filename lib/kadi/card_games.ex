defmodule Kadi.CardGames do
  @moduledoc """
  CardGames keeps the contexts common to all the card games

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  import Ecto.Query, warn: false
  alias Kadi.{Repo}
  alias Kadi.Games.{Card, Deck, DeckCard, GameSession, GameSessionPlayer}

  @doc """
  Returns the state of a specific game, with the game creator preloaded
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

      Map.merge(game, %{player_count: player_count})
    end)
  end

  @doc """
  Creates a new game session, with the player creating the game passed in
  """
  def create_game_session(player, attrs \\ %{}) do
    Repo.transaction(fn ->
      {:ok, game_session} =
        %GameSession{}
        |> GameSession.changeset(Map.merge(attrs, %{created_by_id: player.id}))
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

  @doc """
  Creates deck for a newly created game session, with the game session being passed in
  """
  def create_deck_for_session(game_session) do
    {:ok, deck} = Repo.insert(Deck.changeset(%Deck{}, %{game_session_id: game_session.id}))

    suits = ~w(hearts diamonds clubs spades)
    ranks = Enum.map(2..10, &to_string/1) ++ ~w(jack queen king ace)
    order_indices = Enum.shuffle(1..52)

    all_cards = for suit <- suits, rank <- ranks, do: %{suit: suit, rank: rank}

    Repo.transaction(fn ->
      Enum.zip([all_cards, order_indices])
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
end
