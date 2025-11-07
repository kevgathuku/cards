defmodule Kadi.Games.PlayValidator do
  @moduledoc """
  Pure validation functions for card play validation.

  Validates whether a card play is valid according to game rules:
  - Single card: Must match suit OR rank of top card
  - Multiple cards (combo): All same rank AND at least one matches top card
  """

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
    validate_single_card(single_card, top_card)
  end

  def valid_play?(cards, top_card) when is_list(cards) do
    validate_combo(cards, top_card)
  end

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
