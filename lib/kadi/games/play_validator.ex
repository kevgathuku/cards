defmodule Kadi.Games.PlayValidator do
  @moduledoc """
  Pure validation logic for card plays.

  Responsibilities:

    * Enforce matching rules for the "regular" ranks (4, 5, 6, 7, 9, 10) where combos
      require identical ranks and the lead card must match the top card by suit or rank.
    * Guard the King special-case: exactly one king per play and it must match suit or rank.
    * Guard the Jack special-case introduced in Feature 007: every card in the play must be
      a jack and the first jack has to match the top card by suit or rank.

  The validator remains intentionally side-effect free so it can be exercised directly in
  unit tests and re-used by both the LiveView and OTP server gameplay flows.
  """

  # Regular cards allowed in current phase (005-basic-gameplay)
  @regular_ranks ["4", "5", "6", "7", "9", "10"]

  @doc """
  Validates if a card play is valid.

  ## Parameters
  - cards: List of Card structs to play
  - top_card: The current top card on the played stack
  - opts: Optional keyword list. Supported keys:
    * `:action_suit` - suit that must be matched unless the play itself is an Ace action

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
  def valid_play?(_, nil, _), do: false
  def valid_play?([], _, _), do: false

  def valid_play?([single_card], top_card, opts) do
    action_suit = Keyword.get(opts, :action_suit)
    penalty_active? = Keyword.get(opts, :penalty_active?, false)

    # If penalty is active, only Ace or '2' are valid plays
    if penalty_active? do
      case single_card.rank do
        "ace" -> valid_ace_play?([single_card], top_card, action_suit)
        "2" -> validate_single_card(single_card, top_card, action_suit)
        _ -> false
      end
    else
      # Regular validation when no penalty is active
      {valid?, _type} =
        cond do
          single_card.rank == "ace" ->
            {valid_ace_play?([single_card], top_card, action_suit), :ace}

          single_card.rank == "king" ->
            {valid_king_play?([single_card], top_card, action_suit), :king}

          single_card.rank == "jack" ->
            {valid_jack_play?([single_card], top_card, action_suit), :jack}

          # NEW: Handle '2' card specifically
          single_card.rank == "2" ->
            # Reuse validate_single_card
            {validate_single_card(single_card, top_card, action_suit), :two}

          valid_regular_card?(single_card) ->
            {validate_single_card(single_card, top_card, action_suit), :regular}

          true ->
            {false, :unknown}
        end

      valid?
    end
  end

  def valid_play?(cards, top_card, opts) when is_list(cards) do
    action_suit = Keyword.get(opts, :action_suit)

    {valid?, _type} =
      cond do
        all_aces?(cards) ->
          {valid_ace_play?(cards, top_card, action_suit), :ace}

        Enum.any?(cards, &(&1.rank == "king")) ->
          {valid_king_play?(cards, top_card, action_suit), :king}

        Enum.any?(cards, &(&1.rank == "jack")) ->
          {valid_jack_play?(cards, top_card, action_suit), :jack}

        # NEW: Handle combo '2's specifically (T021)
        # Note: Multiple '2' cards are allowed in a combo, but the penalty effect
        # is NOT additive (handled in CardGames.play_cards/3 where penalty count is fixed at 2)
        all_twos?(cards) ->
          # Reuse validate_combo
          {validate_combo(cards, top_card, action_suit), :two}

        all_regular_cards?(cards) ->
          {validate_combo(cards, top_card, action_suit), :regular}

        true ->
          {false, :unknown}
      end

    valid?
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
  - action_suit: Optional suit that must be matched (from previous Ace play)

  ## Returns
  - `true` if the King play is valid
  - `false` if the King play is invalid
  """
  def valid_king_play?(cards, top_card), do: valid_king_play?(cards, top_card, nil)

  def valid_king_play?([], _top_card, _action_suit), do: false
  def valid_king_play?(_cards, nil, _action_suit), do: false

  def valid_king_play?([%{rank: "king"} = king_card], top_card, action_suit) do
    base_valid = matches_suit_or_rank?(king_card, top_card)

    if action_suit do
      king_card.suit == action_suit
    else
      base_valid
    end
  end

  def valid_king_play?([%{rank: "king"} | _rest], _top_card, _action_suit) do
    # Multiple Kings or King in combo - reject per FR-005
    false
  end

  def valid_king_play?(_cards, _top_card, _action_suit), do: false

  @doc """
  Validates if a Jack card play is valid.

  Rules:
  - Single Jack: Must match suit OR rank of top card
  - Multiple Jacks: All cards must be Jacks, first must match top card
  - Jack combos are allowed (unlike King - FR-003)

  ## Parameters
  - cards: List of Card structs (must contain Jack(s))
  - top_card: The current top card on the played stack
  - action_suit: Optional suit that must be matched (from previous Ace play)

  ## Returns
  - `true` if the Jack play is valid
  - `false` if the Jack play is invalid

  ## Examples

      iex> top_card = %Kadi.Games.Card{suit: "hearts", rank: "5"}
      iex> jack = %Kadi.Games.Card{suit: "hearts", rank: "jack"}
      iex> Kadi.Games.PlayValidator.valid_jack_play?([jack], top_card)
      true

      iex> top_card = %Kadi.Games.Card{suit: "diamonds", rank: "jack"}
      iex> jack = %Kadi.Games.Card{suit: "clubs", rank: "jack"}
      iex> Kadi.Games.PlayValidator.valid_jack_play?([jack], top_card)
      true
  """
  def valid_jack_play?(cards, top_card), do: valid_jack_play?(cards, top_card, nil)

  def valid_jack_play?([], _top_card, _action_suit), do: false
  def valid_jack_play?(_cards, nil, _action_suit), do: false

  def valid_jack_play?(cards, top_card, action_suit) when is_list(cards) do
    all_jacks?(cards) and first_card_matches?(cards, top_card, action_suit)
  end

  @doc """
  Validates if an Ace card play is valid.

  Rules:
  - One or more cards may be played, but every card must be an Ace (FR-008)
  - Aces ignore the suit or rank of the top card (FR-001)
  - Aces ignore any action_suit from a previous Ace play (they can be played freely)

  ## Parameters
  - cards: List of Card structs (must all be Aces)
  - top_card: The current top card on the played stack
  - action_suit: Optional suit that must be matched (ignored for Aces)

  ## Returns
  - `true` if the Ace play is valid
  - `false` if the Ace play is invalid
  """
  def valid_ace_play?(cards, top_card), do: valid_ace_play?(cards, top_card, nil)

  def valid_ace_play?([], _top_card, _action_suit), do: false
  def valid_ace_play?(_cards, nil, _action_suit), do: false

  def valid_ace_play?(cards, _top_card, _action_suit) when is_list(cards) do
    all_aces?(cards)
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

  defp all_jacks?(cards) do
    Enum.all?(cards, &(&1.rank == "jack"))
  end

  defp all_aces?(cards) do
    Enum.all?(cards, &(&1.rank == "ace"))
  end

  defp all_twos?(cards) do
    Enum.all?(cards, &(&1.rank == "2"))
  end

  defp valid_regular_card?(%{rank: rank}) do
    rank in @regular_ranks
  end

  defp all_regular_cards?(cards) do
    Enum.all?(cards, &valid_regular_card?/1)
  end

  defp validate_single_card(card, top_card, action_suit) do
    if action_suit do
      card.suit == action_suit
    else
      matches_suit_or_rank?(card, top_card)
    end
  end

  defp validate_combo(cards, top_card, action_suit) do
    same_rank?(cards) and first_card_matches?(cards, top_card, action_suit)
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

  defp first_card_matches?([first_card | _rest], top_card, action_suit) do
    if action_suit do
      first_card.suit == action_suit
    else
      matches_suit_or_rank?(first_card, top_card)
    end
  end

  defp first_card_matches?([], _top_card, _action_suit), do: false
end
