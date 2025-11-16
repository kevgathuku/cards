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
    * `:action_suit` - Suit requested by a previous Ace play (regular gameplay)
    * `:penalty_blocked_suit` - Suit of penalty card that was blocked by an Ace
    * `:penalty_active?` - Whether a draw penalty is currently active
    * `:penalty_type` - Type of penalty ("two" or "three")

  ## Action Suit vs Penalty Blocked Suit

  These two options represent different game scenarios:

  - **`:action_suit`** - Used when an Ace was played in regular gameplay to request
    a specific suit. ALL cards (including penalty cards 2s and 3s) MUST match that
    suit. No bypass allowed. Only another Ace can override this requirement.

  - **`:penalty_blocked_suit`** - Used when an Ace blocked a penalty (2 or 3 card).
    The suit of the blocked penalty card becomes active. Regular cards must match
    the suit, but penalty cards (2s and 3s) CAN bypass by matching rank instead
    (this enables chaining penalty blocks).

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
    penalty_blocked_suit = Keyword.get(opts, :penalty_blocked_suit)
    penalty_active? = Keyword.get(opts, :penalty_active?, false)
    penalty_type = Keyword.get(opts, :penalty_type)

    # Determine which suit constraint applies (if any)
    # Priority: penalty_blocked_suit > action_suit
    required_suit = penalty_blocked_suit || action_suit

    # If penalty is active, only Ace or matching penalty card are valid plays
    if penalty_active? do
      case {single_card.rank, penalty_type} do
        {"ace", _} ->
          # Aces can always be played, even during penalties
          valid_ace_play?([single_card], top_card, required_suit)

        {"2", "two"} ->
          # When blocking a '2' penalty with another '2'
          validate_penalty_card(single_card, top_card, penalty_blocked_suit)

        {"3", "three"} ->
          # When blocking a '3' penalty with another '3'
          validate_penalty_card(single_card, top_card, penalty_blocked_suit)

        # Backward compatibility: if penalty_type is nil, allow 2 cards (old behavior)
        {"2", nil} ->
          validate_penalty_card(single_card, top_card, penalty_blocked_suit)

        _ ->
          false
      end
    else
      # Regular validation when no penalty is active
      {valid?, _type} =
        cond do
          single_card.rank == "ace" ->
            {valid_ace_play?([single_card], top_card, required_suit), :ace}

          single_card.rank == "king" ->
            {valid_king_play?([single_card], top_card, action_suit), :king}

          single_card.rank == "jack" ->
            {valid_jack_play?([single_card], top_card, action_suit), :jack}

          # Handle '2' card - can initiate penalty or be played normally
          single_card.rank == "2" ->
            {validate_regular_or_penalty_card(
               single_card,
               top_card,
               action_suit,
               penalty_blocked_suit
             ), :two}

          # Handle '3' card - can initiate penalty or be played normally
          single_card.rank == "3" ->
            {validate_regular_or_penalty_card(
               single_card,
               top_card,
               action_suit,
               penalty_blocked_suit
             ), :three}

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
    penalty_blocked_suit = Keyword.get(opts, :penalty_blocked_suit)
    penalty_active? = Keyword.get(opts, :penalty_active?, false)
    penalty_type = Keyword.get(opts, :penalty_type)

    # Determine which suit constraint applies (if any)
    # Priority: penalty_blocked_suit > action_suit
    required_suit = penalty_blocked_suit || action_suit

    # If penalty is active, only Ace combos or matching penalty card combos are valid
    if penalty_active? do
      cond do
        all_aces?(cards) ->
          # Aces can always be played, even during penalties
          valid_ace_play?(cards, top_card, required_suit)

        all_twos?(cards) and (penalty_type == "two" or penalty_type == nil) ->
          # Backward compatibility: if penalty_type is nil, allow 2 cards (old behavior)
          # When blocking a '2' penalty with multiple '2's
          validate_penalty_combo(cards, top_card, penalty_blocked_suit)

        all_threes?(cards) and penalty_type == "three" ->
          # When blocking a '3' penalty with multiple '3's
          validate_penalty_combo(cards, top_card, penalty_blocked_suit)

        true ->
          false
      end
    else
      {valid?, _type} =
        cond do
          all_aces?(cards) ->
            {valid_ace_play?(cards, top_card, required_suit), :ace}

          Enum.any?(cards, &(&1.rank == "king")) ->
            {valid_king_play?(cards, top_card, action_suit), :king}

          Enum.any?(cards, &(&1.rank == "jack")) ->
            {valid_jack_play?(cards, top_card, action_suit), :jack}

          # Handle combo '2's - can initiate penalty or be played normally
          # Note: Multiple '2' cards are allowed in a combo, but the penalty effect
          # is NOT additive (handled in CardGames.play_cards/3 where penalty count is fixed at 2)
          all_twos?(cards) ->
            {validate_combo_with_penalty_bypass(
               cards,
               top_card,
               action_suit,
               penalty_blocked_suit
             ), :two}

          # Handle combo '3's - can initiate penalty or be played normally
          # Note: Multiple '3' cards are allowed in a combo, but the penalty effect
          # is NOT additive (handled in CardGames.play_cards/3 where penalty count is fixed at 3)
          all_threes?(cards) ->
            {validate_combo_with_penalty_bypass(
               cards,
               top_card,
               action_suit,
               penalty_blocked_suit
             ), :three}

          all_regular_cards?(cards) ->
            {validate_combo(cards, top_card, action_suit), :regular}

          true ->
            {false, :unknown}
        end

      valid?
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

  # ============================================================================
  # Card Type Checkers
  # ============================================================================

  defp all_jacks?(cards) do
    Enum.all?(cards, &(&1.rank == "jack"))
  end

  defp all_aces?(cards) do
    Enum.all?(cards, &(&1.rank == "ace"))
  end

  defp all_twos?(cards) do
    Enum.all?(cards, &(&1.rank == "2"))
  end

  defp all_threes?(cards) do
    Enum.all?(cards, &(&1.rank == "3"))
  end

  defp valid_regular_card?(%{rank: rank}) do
    rank in @regular_ranks
  end

  defp all_regular_cards?(cards) do
    Enum.all?(cards, &valid_regular_card?/1)
  end

  # ============================================================================
  # Single Card Validation
  # ============================================================================
  # These functions handle validation for single cards in different scenarios:
  # - Regular cards with action_suit (strict suit matching)
  # - Penalty cards with penalty_blocked_suit (can match by rank to chain blocks)
  # - Penalty cards in regular gameplay (follow same rules as regular cards)
  # ============================================================================

  # Validates a regular card when action_suit is set (from Ace in regular gameplay)
  defp validate_single_card(card, top_card, action_suit) do
    if action_suit do
      # When action_suit is set from a regular Ace play, card must match the requested suit
      card.suit == action_suit
    else
      # Normal matching: suit or rank
      matches_suit_or_rank?(card, top_card)
    end
  end

  # Validates a penalty card (2 or 3) when penalty_blocked_suit is set
  # Penalty cards can bypass penalty_blocked_suit by matching rank (enables chaining)
  defp validate_penalty_card(card, top_card, penalty_blocked_suit) do
    if penalty_blocked_suit do
      # When penalty_blocked_suit is set (from Ace blocking a penalty), allow either:
      # 1. Matching the penalty_blocked_suit, OR
      # 2. Playing another penalty card of the same rank (2 blocks 2, 3 blocks 3)
      card.suit == penalty_blocked_suit or card.rank == top_card.rank
    else
      # Normal matching: suit or rank
      matches_suit_or_rank?(card, top_card)
    end
  end

  # Validates a penalty card (2 or 3) in regular gameplay
  # When action_suit is set: penalty cards MUST match the suit (no bypass)
  # When penalty_blocked_suit is set: penalty cards CAN match by rank (bypass enabled)
  defp validate_regular_or_penalty_card(card, top_card, action_suit, penalty_blocked_suit) do
    cond do
      penalty_blocked_suit ->
        # When penalty was blocked by Ace, penalty cards can match by rank
        validate_penalty_card(card, top_card, penalty_blocked_suit)

      action_suit ->
        # BACKWARD COMPATIBILITY: If action_suit is set but penalty_blocked_suit is not,
        # and the top card is an Ace (indicating it just blocked a penalty), treat this
        # as a penalty block scenario where penalty cards can match by rank
        if top_card.rank == "ace" and (card.rank == "2" or card.rank == "3") do
          # Allow penalty cards to match by rank (legacy behavior for penalty blocking)
          card.suit == action_suit or card.rank == "2" or card.rank == "3"
        else
          # When action_suit is set from regular Ace, ALL cards (including penalty cards)
          # must match the requested suit - no bypass allowed
          card.suit == action_suit
        end

      true ->
        # Normal matching: suit or rank
        matches_suit_or_rank?(card, top_card)
    end
  end

  # ============================================================================
  # Combo Validation
  # ============================================================================
  # These functions handle validation for card combos in different scenarios:
  # - Regular combos with action_suit (strict suit matching)
  # - Penalty card combos with penalty_blocked_suit (can match by rank)
  # - Penalty card combos in regular gameplay (follow same rules as regular combos)
  # ============================================================================

  # Validates a regular combo when action_suit is set
  defp validate_combo(cards, top_card, action_suit) do
    same_rank?(cards) and first_card_matches?(cards, top_card, action_suit)
  end

  # Validates a penalty card combo when blocking another penalty
  defp validate_penalty_combo(cards, top_card, penalty_blocked_suit) do
    same_rank?(cards) and first_penalty_card_matches?(cards, top_card, penalty_blocked_suit)
  end

  # Validates a penalty card combo (2s or 3s) in regular gameplay
  # When action_suit is set: penalty cards MUST match the suit (no bypass)
  # When penalty_blocked_suit is set: penalty cards CAN match by rank (bypass enabled)
  defp validate_combo_with_penalty_bypass(cards, top_card, action_suit, penalty_blocked_suit) do
    cond do
      penalty_blocked_suit ->
        # When penalty was blocked by Ace, validate as penalty combo
        validate_penalty_combo(cards, top_card, penalty_blocked_suit)

      action_suit ->
        # BACKWARD COMPATIBILITY: If action_suit is set but penalty_blocked_suit is not,
        # and the top card is an Ace (indicating it just blocked a penalty), treat this
        # as a penalty block scenario where penalty cards can match by rank
        if top_card.rank == "ace" and (all_twos?(cards) or all_threes?(cards)) do
          # Allow penalty card combos to match by rank (legacy behavior for penalty blocking)
          validate_penalty_combo(cards, top_card, action_suit)
        else
          # When action_suit is set from regular Ace, ALL cards (including penalty cards)
          # must match the requested suit - no bypass allowed
          same_rank?(cards) and first_card_matches?(cards, top_card, action_suit)
        end

      true ->
        # Normal combo validation
        validate_combo(cards, top_card, nil)
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp matches_suit_or_rank?(card, top_card) do
    card.suit == top_card.suit or card.rank == top_card.rank
  end

  defp same_rank?(cards) do
    cards
    |> Enum.map(& &1.rank)
    |> Enum.uniq()
    |> length() == 1
  end

  # ============================================================================
  # First Card Matching (for combos)
  # ============================================================================
  # These functions check if the first card in a combo meets the requirements:
  # - first_card_matches?: Regular combos with action_suit (strict matching)
  # - first_penalty_card_matches?: Penalty combos with penalty_blocked_suit (can match by rank)
  # ============================================================================

  # Checks if first card matches when action_suit is set (regular Ace play)
  defp first_card_matches?([first_card | _rest], top_card, action_suit) do
    if action_suit do
      # When action_suit is set from a regular Ace play, first card must match the requested suit
      first_card.suit == action_suit
    else
      # Normal matching: suit or rank
      matches_suit_or_rank?(first_card, top_card)
    end
  end

  defp first_card_matches?([], _top_card, _action_suit), do: false

  # Checks if first penalty card matches when penalty_blocked_suit is set (Ace blocked penalty)
  defp first_penalty_card_matches?([first_card | _rest], top_card, penalty_blocked_suit) do
    if penalty_blocked_suit do
      # When penalty_blocked_suit is set, allow matching the suit OR matching rank
      first_card.suit == penalty_blocked_suit or first_card.rank == top_card.rank
    else
      # Normal matching: suit or rank
      matches_suit_or_rank?(first_card, top_card)
    end
  end

  defp first_penalty_card_matches?([], _top_card, _penalty_blocked_suit), do: false
end
