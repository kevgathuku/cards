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
      game_session when not is_nil(game_session) -> {:ok, game_session}
      _ -> {:error, :not_found}
    end
  end

  def fetch_games() do
    # TODO: Fetch by player when auth is added
    GameSession |> Repo.all
  end

  def create_deck_for_session(game_session) do
    {:ok, deck} = Repo.insert(Deck.changeset(%Deck{}, %{game_session_id: game_session.id}))

    suits = ~w(hearts diamonds clubs spades)
    ranks = Enum.map(2..10, &to_string/1) ++ ~w(jack queen king ace)

    Enum.each(suits, fn suit ->
      Enum.each(ranks, fn rank ->
        # Find or create card
        card_attrs = %{suit: suit, rank: rank}
        {:ok, card} =
          case Repo.get_by(Card, card_attrs) do
            nil -> Repo.insert(Card.changeset(%Card{}, card_attrs))
            existing -> {:ok, existing}
          end

        # Create deck_cards entry
        deck_card_attrs = %{deck_id: deck.id, card_id: card.id, location_type: "deck"}
        {:ok, _deck_card} = Repo.insert(DeckCard.changeset(%DeckCard{}, deck_card_attrs))
      end)
    end)

    # Optionally shuffle and record event
    deck
  end
end
