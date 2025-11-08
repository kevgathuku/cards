defmodule Kadi.Games.PlayValidator do
  @moduledoc """
  Pure validation functions for card play validation.

  Validates whether a card play is valid according to game rules:
  - Single card: Must match suit OR rank of top card
  - Multiple cards (combo): All same rank AND at least one matches top card

  ## Phase 1 - Regular Cards Only
  Currently only regular cards (4,5,6,7,9,10) can be played.
  Special cards (2,3,8,Jack,Queen,King,Ace) will be implemented in later phases.
  """

  # Regular cards allowed in current phase (005-basic-gameplay)
  @regular_ranks ["4", "5", "6", "7", "9", "10"]

  @doc """
  Validates if a card play is valid.

  ## Parameters
  - cards: List of Card structs to play
  - top_card: The current top card on the played stack

  ## Returns
  - `true` if the play is valid
  - `false` if the play is invalid

  ## Examples

      iex> top_card = %Card{suit: "hearts", rank: "5"}
      iex> cards = [%Card{suit: "hearts", rank: "4"}]
      iex> PlayValidator.valid_play?(cards, top_card)
      true

      iex> top_card = %Card{suit: "hearts", rank: "5"}
      iex> cards = [%Card{suit: "clubs", rank: "7"}]
      iex> PlayValidator.valid_play?(cards, top_card)
      false
  """
  def valid_play?([], _top_card), do: false
  def valid_play?(_cards, nil), do: false

  def valid_play?([single_card], top_card) do
    cond do
      single_card.rank == "king" ->
        valid_king_play?([single_card], top_card)

      valid_regular_card?(single_card) ->
        validate_single_card(single_card, top_card)

      true ->
        false
    end
  end

  def valid_play?(cards, top_card) when is_list(cards) do
    cond do
      Enum.any?(cards, &(&1.rank == "king")) ->
        valid_king_play?(cards, top_card)

      all_regular_cards?(cards) ->
        validate_combo(cards, top_card)

      true ->
        false
    end
  end

  @doc """
  Validates if a King card play is valid.

  Rules:
  - Single King: Must match suit OR rank of top card
  - Multiple Kings: Rejected (only one King per turn - FR-005)
  - King in combo with other cards: Rejected (Phase 1 limitation)

  ## Parameters
  - cards: List of Card structs (must contain King(s))
  - top_card: The current top card on the played stack

  ## Returns
  - `true` if the King play is valid
  - `false` if the King play is invalid
  """
  def valid_king_play?([], _top_card), do: false
  def valid_king_play?(_cards, nil), do: false

  def valid_king_play?([%{rank: "king"} = king_card], top_card) do
    matches_suit_or_rank?(king_card, top_card)
  end

  def valid_king_play?([%{rank: "king"} | _rest], _top_card) do
    # Multiple Kings or King in combo - reject per FR-005
    false
  end

  def valid_king_play?(_cards, _top_card), do: false

  @doc """
  Validates if player has all the specified cards in their hand.

  ## Parameters
  - player_cards: List of Card structs in player's hand
  - cards_to_play: List of Card structs player wants to play

  ## Returns
  - `true` if player has all cards
  - `false` if player is missing any cards
  """
  def player_has_cards?(player_cards, cards_to_play) do
    player_card_ids = MapSet.new(player_cards, & &1.id)
    cards_to_play_ids = MapSet.new(cards_to_play, & &1.id)

    MapSet.subset?(cards_to_play_ids, player_card_ids)
  end

  # Private Functions

  defp valid_regular_card?(%{rank: rank}) do
    rank in @regular_ranks
  end

  defp all_regular_cards?(cards) do
    Enum.all?(cards, &valid_regular_card?/1)
  end

  defp validate_single_card(card, top_card) do
    matches_suit_or_rank?(card, top_card)
  end

  defp validate_combo(cards, top_card) do
    same_rank?(cards) and first_card_matches?(cards, top_card)
  end

  defp matches_suit_or_rank?(card, top_card) do
    card.suit == top_card.suit or card.rank == top_card.rank
  end

  defp same_rank?(cards) do
    cards
    |> Enum.map(& &1.rank)
    |> Enum.uniq()
    |> length() == 1
  end

  defp first_card_matches?([first_card | _rest], top_card) do
    matches_suit_or_rank?(first_card, top_card)
  end

  defp first_card_matches?([], _top_card), do: false
end
