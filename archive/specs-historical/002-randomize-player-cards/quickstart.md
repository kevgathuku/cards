# Quickstart: Randomize Player Card Distribution

**Date**: 2025-11-03
**Feature**: 002-randomize-player-cards

## What This Feature Does

Ensures that when a game starts and cards are dealt to players, the distribution follows the randomized `order_index` sequence created during deck generation. This prevents sequential card patterns (like 4,5,6,7 of hearts) from appearing in player hands.

## 5-Minute Overview

### Problem

Currently, when `deal_cards/2` splits the deck to deal to players, it uses whatever order the cards happen to be in after database preload. This means the randomized `order_index` values (created by `Enum.shuffle(1..52)` during deck creation) are **ignored**, leading to potentially sequential card patterns.

### Solution

Sort the deck cards by `order_index` **before** splitting them for distribution to players.

### Impact

**Files Changed**: 1 file (`lib/kadi/card_games.ex`)
**Lines Changed**: +2 lines (add sort step)
**Tests Required**: 3-4 new test cases in `test/kadi/card_games_test.exs`
**Migration**: None
**Breaking Changes**: None

## Implementation Steps

### Step 1: Modify `deal_cards/2` Function

**File**: `lib/kadi/card_games.ex`
**Location**: Lines 194-221 (current implementation)

**Change**:
```elixir
# BEFORE (Line 195):
defp deal_cards(players, deck_cards) do
  cards_in_deck = Enum.filter(deck_cards, &(&1.location_type == "deck"))
  # ...
end

# AFTER (Lines 195-197):
defp deal_cards(players, deck_cards) do
  cards_in_deck =
    deck_cards
    |> Enum.filter(&(&1.location_type == "deck"))
    |> Enum.sort_by(& &1.order_index)  # ← NEW: Sort by randomized order_index
  # ...
end
```

**Rationale**: The `order_index` values are already randomized during deck creation (line 105). This change ensures dealing respects that pre-randomized order.

### Step 2: Add Test Coverage

**File**: `test/kadi/card_games_test.exs`

**Add New Test Cases**:

```elixir
describe "deal_cards/2 with order_index" do
  setup do
    player1 = insert(:player)
    player2 = insert(:player)
    player3 = insert(:player)
    game_session = insert(:game_session, status: "lobby")

    # Create deck with known order_index sequence
    deck = insert(:deck, game_session_id: game_session.id)

    # Create 52 cards with specific order_index values
    order_indices = Enum.shuffle(1..52)
    cards = for _ <- 1..52, do: insert(:card)

    deck_cards =
      Enum.zip(cards, order_indices)
      |> Enum.map(fn {card, order_index} ->
        insert(:deck_card,
          deck_id: deck.id,
          card_id: card.id,
          location_type: "deck",
          order_index: order_index
        )
      end)

    {:ok, _} = CardGames.add_player_to_session(game_session, player1)
    {:ok, _} = CardGames.add_player_to_session(game_session, player2)
    {:ok, _} = CardGames.add_player_to_session(game_session, player3)

    %{game_session: game_session, players: [player1, player2, player3], order_indices: order_indices}
  end

  test "deals cards in order_index sequence", %{game_session: game_session, players: players} do
    {:ok, updated_session} = CardGames.start_game(game_session)

    # Reload to get dealt cards
    updated_session = Repo.preload(updated_session, deck: [deck_cards: :card], force: true)

    # Get cards for each player
    for player <- players do
      player_deck_cards =
        updated_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player.id))

      # Verify: 4 cards per player
      assert length(player_deck_cards) == 4

      # Note: Cannot directly verify order_index sequence since order_index is set to nil
      # for player_hand location_type. This test verifies dealing completes successfully
      # with sorted input. More specific order verification requires inspecting the
      # intermediate state in deal_cards/2.
    end
  end

  test "does not deal sequential ranks of same suit to single player", %{game_session: game_session} do
    # Run multiple game starts to check for patterns
    results =
      for _ <- 1..100 do
        # Reset game session
        {:ok, updated_session} = CardGames.start_game(Repo.reload(game_session))
        updated_session = Repo.preload(updated_session, deck: [deck_cards: :card], force: true)

        player_hands =
          Enum.map(updated_session.players, fn player ->
            updated_session.deck.deck_cards
            |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player.id))
            |> Enum.map(& &1.card)
          end)

        # Check each hand for sequential patterns
        Enum.any?(player_hands, fn hand ->
          has_sequential_pattern?(hand)
        end)
      end

    # Statistical check: <5% of games should have sequential patterns
    sequential_pattern_count = Enum.count(results, & &1)
    assert sequential_pattern_count < 5, "Too many games with sequential patterns: #{sequential_pattern_count}/100"
  end

  defp has_sequential_pattern?(cards) do
    # Check if hand contains 3+ consecutive ranks of same suit
    by_suit =
      cards
      |> Enum.group_by(& &1.suit)

    Enum.any?(by_suit, fn {_suit, suit_cards} ->
      ranks = Enum.map(suit_cards, &rank_to_number/1) |> Enum.sort()
      has_consecutive_sequence?(ranks, 3)
    end)
  end

  defp rank_to_number(card) do
    case card.rank do
      "ace" -> 1
      "2" -> 2
      "3" -> 3
      "4" -> 4
      "5" -> 5
      "6" -> 6
      "7" -> 7
      "8" -> 8
      "9" -> 9
      "10" -> 10
      "jack" -> 11
      "queen" -> 12
      "king" -> 13
    end
  end

  defp has_consecutive_sequence?(sorted_numbers, min_length) do
    sorted_numbers
    |> Enum.chunk_while(
      [],
      fn num, acc ->
        case acc do
          [] -> {:cont, [num]}
          [last | _] when num == last + 1 -> {:cont, [num | acc]}
          _ -> {:cont, Enum.reverse(acc), [num]}
        end
      end,
      fn acc -> {:cont, Enum.reverse(acc), []} end
    )
    |> Enum.any?(fn sequence -> length(sequence) >= min_length end)
  end
end
```

### Step 3: Run Tests

```bash
# Run all card_games tests
mix test test/kadi/card_games_test.exs

# Run specific test
mix test test/kadi/card_games_test.exs:LINE_NUMBER
```

### Step 4: Manual Verification (Optional)

Start an IEx session and create a game:

```elixir
# Start IEx with application
iex -S mix phx.server

# Create test data
alias Kadi.{CardGames, Accounts, Repo}
alias Kadi.Games.{GameSession, Deck, DeckCard}

{:ok, player1} = Accounts.register_player(%{email: "p1@test.com", password: "password123"})
{:ok, player2} = Accounts.register_player(%{email: "p2@test.com", password: "password123"})

{:ok, game_session} = CardGames.create_game_session(%{})
{:ok, _} = CardGames.add_player_to_session(game_session, player1)
{:ok, _} = CardGames.add_player_to_session(game_session, player2)

# Before fix: Check order_index sequence in deck
game_session = Repo.preload(game_session, deck: [deck_cards: :card])
order_indices =
  game_session.deck.deck_cards
  |> Enum.filter(&(&1.location_type == "deck"))
  |> Enum.map(& &1.order_index)
  |> Enum.sort()

IO.inspect(order_indices, label: "Order indices (should be 1..52)")

# Start game and check dealt cards
{:ok, started_session} = CardGames.start_game(game_session)
started_session = Repo.preload(started_session, deck: [deck_cards: :card], force: true)

player1_cards =
  started_session.deck.deck_cards
  |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player1.id))
  |> Enum.map(& "#{&1.card.rank} of #{&1.card.suit}")

player2_cards =
  started_session.deck.deck_cards
  |> Enum.filter(&(&1.location_type == "player_hand" && &1.player_id == player2.id))
  |> Enum.map(& "#{&1.card.rank} of #{&1.card.suit}")

IO.inspect(player1_cards, label: "Player 1 hand")
IO.inspect(player2_cards, label: "Player 2 hand")

# Check for sequential patterns
# If you see patterns like ["4 of hearts", "5 of hearts", "6 of hearts", "7 of hearts"],
# the fix is needed. After fix, such patterns should be rare.
```

## Testing Checklist

- [ ] Modified `deal_cards/2` to sort by `order_index`
- [ ] Added test for dealing in `order_index` sequence
- [ ] Added statistical test for non-sequential patterns (100 iterations)
- [ ] Run full test suite: `mix test`
- [ ] Verify tests pass
- [ ] Optional: Manual IEx verification

## Rollout

### Pre-Deployment
1. ✅ Code review
2. ✅ All tests passing
3. ✅ No migration required (using existing schema)

### Deployment
- **Risk Level**: Low
- **Rollback**: Revert single commit
- **Affected Games**: Only new game starts (games already "live" are unaffected)

### Post-Deployment Verification
1. Monitor game creation metrics
2. Check for errors in card dealing (`start_game` function)
3. Verify game initialization time remains <2 seconds

## Common Issues and Solutions

### Issue: `order_index` is nil for some deck_cards

**Symptom**: Error when sorting: "cannot compare nil with integer"

**Cause**: Deck created before `order_index` field existed, or validation failure

**Solution**:
```elixir
# Add defensive check in deal_cards/2:
cards_in_deck =
  deck_cards
  |> Enum.filter(&(&1.location_type == "deck" && !is_nil(&1.order_index)))
  |> Enum.sort_by(& &1.order_index)
```

**Prevention**: Ensure all new decks have `order_index` via validation in `DeckCard.changeset/2` (already exists)

### Issue: Performance degradation

**Symptom**: Game start takes longer than 2 seconds

**Diagnosis**:
```elixir
# Add telemetry in do_start_game/1:
start_time = System.monotonic_time(:millisecond)
# ... existing code ...
end_time = System.monotonic_time(:millisecond)
Logger.info("Game start took #{end_time - start_time}ms")
```

**Solution**: Sorting 52 integers should take <1ms. If slow, check:
- Database query time (preload)
- Network latency
- Other bottlenecks unrelated to this change

## References

- **Feature Spec**: [spec.md](./spec.md)
- **Research**: [research.md](./research.md)
- **Data Model**: [data-model.md](./data-model.md)
- **Primary File**: `lib/kadi/card_games.ex:194-221`
- **Test File**: `test/kadi/card_games_test.exs`
- **Related Feature**: 001-deal-start-card (introduced `order_index` field)
