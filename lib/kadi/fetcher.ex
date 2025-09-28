defmodule Kadi.Fetcher do
  @moduledoc """
  Fetcher keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  import Ecto.Query, warn: false
  alias Kadi.{Repo}
  alias Kadi.Games.{Card, Deck, DeckCard, GameSession}

  @doc """
  Returns the state of a specific game, constructed from the events
  """
  def get_game_state(game_id) do
    case Repo.get(GameSession, game_id) do
      game_session when not is_nil(game_session) -> {:ok, game_session |> Repo.preload(:created_by)}
      _ -> {:error, :not_found}
    end
  end

  def list_user_games(player_id) do
    query =
      from gs in GameSession,
        where: gs.created_by_id == ^player_id,
        preload: [:created_by],
        order_by: [desc: gs.inserted_at]

    games = Repo.all(query)

    # Temporarily set player_count to 1 (creator only) until participant tracking is implemented
    Enum.map(games, fn game ->
      Map.merge(game, %{player_count: 1})
    end)
  end

  def create_game_session(player, attrs \\ %{}) do
   %GameSession{}
    |> GameSession.changeset(Map.merge(attrs, %{created_by_id: player.id}))
    |> Repo.insert()
    |> case do
      {:ok, game_session} ->
        {:ok, deck} = create_deck_for_session(game_session)
        {:ok, game_session |> Repo.preload(:created_by) }

      error -> error
    end
  end

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

        # Create deck_cards entry
        deck_card_attrs = %{deck_id: deck.id, card_id: card.id, location_type: "deck", order_index: order_index}
        {:ok, _deck_card} = Repo.insert(DeckCard.changeset(%DeckCard{}, deck_card_attrs))
      end)
    end)

    # Optionally shuffle and record event
    {:ok, deck}
  end
end
