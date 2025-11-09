defmodule Kadi.Games.DeckCard do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Kadi.Games.DeckCard

  schema "deck_cards" do
    belongs_to :deck, Kadi.Games.Deck
    belongs_to :card, Kadi.Games.Card
    belongs_to :player, Kadi.Accounts.Player
    # "deck", "played_stack", "player_hand"
    field :location_type, :string
    # Order for deck/played_stack, null for player_hand
    field :order_index, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck_card, attrs) do
    deck_card
    |> cast(attrs, [:deck_id, :card_id, :location_type, :player_id, :order_index])
    |> validate_required([:deck_id, :card_id, :location_type])
    |> validate_location_and_order()
    |> assoc_constraint(:deck)
    |> assoc_constraint(:card)
    |> assoc_constraint(:player)
    |> unique_constraint([:deck_id, :card_id])
    |> unique_constraint([:deck_id, :location_type, :order_index])
  end

  defp validate_location_and_order(changeset) do
    location_type = get_field(changeset, :location_type)

    case location_type do
      "player_hand" ->
        changeset
        |> validate_required(:player_id)
        |> validate_is_nil(:order_index, "must be nil for player_hand")

      loc when loc == "deck" or loc == "played_stack" ->
        changeset
        |> validate_is_nil(:player_id, "must be nil for #{location_type}")
        |> validate_required(:order_index)
        |> validate_number(:order_index, greater_than: 0)

      _ ->
        add_error(changeset, :location_type, "must be 'deck', 'played_stack', or 'player_hand'")
    end
  end

  defp validate_is_nil(changeset, field, message) do
    if get_field(changeset, field) == nil do
      changeset
    else
      add_error(changeset, field, message)
    end
  end

  # ============================================================================
  # Query Functions (Rails-style scopes)
  # ============================================================================

  @doc """
  Filter cards in player hands.

  ## Examples

      DeckCard
      |> DeckCard.in_hand()
      |> Repo.all()
  """
  def in_hand(query \\ DeckCard) do
    from dc in query, where: dc.location_type == "player_hand"
  end

  @doc """
  Filter cards in deck pile.

  ## Examples

      DeckCard
      |> DeckCard.in_deck()
      |> Repo.all()
  """
  def in_deck(query \\ DeckCard) do
    from dc in query, where: dc.location_type == "deck"
  end

  @doc """
  Filter cards in played stack.

  ## Examples

      DeckCard
      |> DeckCard.played()
      |> Repo.all()
  """
  def played(query \\ DeckCard) do
    from dc in query, where: dc.location_type == "played_stack"
  end

  @doc """
  Filter cards for a specific player.

  ## Examples

      DeckCard
      |> DeckCard.in_hand()
      |> DeckCard.for_player(player_id)
      |> Repo.all()
  """
  def for_player(query \\ DeckCard, player_id) do
    from dc in query, where: dc.player_id == ^player_id
  end

  @doc """
  Filter cards by rank.

  ## Examples

      DeckCard
      |> DeckCard.of_rank("jack")
      |> Repo.all()
  """
  def of_rank(query \\ DeckCard, rank) do
    from dc in query,
      join: c in assoc(dc, :card),
      where: c.rank == ^rank
  end

  @doc """
  Filter cards by suit.

  ## Examples

      DeckCard
      |> DeckCard.of_suit("hearts")
      |> Repo.all()
  """
  def of_suit(query \\ DeckCard, suit) do
    from dc in query,
      join: c in assoc(dc, :card),
      where: c.suit == ^suit
  end

  @doc """
  Preload card details.

  ## Examples

      DeckCard
      |> DeckCard.in_hand()
      |> DeckCard.with_card()
      |> Repo.all()
  """
  def with_card(query \\ DeckCard) do
    from dc in query, preload: [:card]
  end

  @doc """
  Order by index (for deck/played stack). Lower index = top of deck, higher index = top of played stack.

  ## Examples

      DeckCard
      |> DeckCard.in_deck()
      |> DeckCard.ordered()
      |> Repo.all()
  """
  def ordered(query \\ DeckCard) do
    from dc in query, order_by: [asc: dc.order_index]
  end

  @doc """
  Order by index descending (for played stack - highest index = top/visible card).

  ## Examples

      DeckCard
      |> DeckCard.played()
      |> DeckCard.ordered_desc()
      |> Repo.all()
  """
  def ordered_desc(query \\ DeckCard) do
    from dc in query, order_by: [desc: dc.order_index]
  end
end
