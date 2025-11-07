# Benchmark script for play_cards/3 performance validation
# Target: <100ms (100,000 microseconds) per operation
#
# Run with: mix run priv/repo/benchmark_play_validation.exs

alias Kadi.{Repo, CardGames, Accounts}
alias Kadi.Games.GameSession

# Setup: Create a game with 2 players
IO.puts("\n=== Setting up benchmark game ===")

timestamp = System.system_time(:second)

{:ok, player1} =
  Accounts.register_player(%{
    email: "benchmark1_#{timestamp}@example.com",
    password: "secure_password_123"
  })

{:ok, player2} =
  Accounts.register_player(%{
    email: "benchmark2_#{timestamp}@example.com",
    password: "secure_password_123"
  })

{:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "bench"})
{:ok, _} = CardGames.join_game_session(player2, game_session.id)
{:ok, game_session} = CardGames.start_game(game_session)

# Ensure it's player1's turn
game_session = Repo.get!(GameSession, game_session.id)
game_session = Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]])

game_session =
  if game_session.current_turn_player_id != player1.id do
    GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
    |> Repo.update!()
    |> Repo.preload([:top_card, deck: [deck_cards: :card]], force: true)
  else
    game_session
  end

# Get player1's cards
player1_cards =
  game_session.deck.deck_cards
  |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player1.id))
  |> Enum.map(& &1.card)

# Find a regular card player1 has
regular_card_in_hand =
  player1_cards
  |> Enum.find(fn card ->
    card.rank in ["4", "5", "6", "7", "9", "10"]
  end)

if is_nil(regular_card_in_hand) do
  IO.puts("ERROR: Player1 has no regular cards (4,5,6,7,9,10) in hand")
  System.halt(1)
end

# Set that card as the top card so we can play another matching card
game_session =
  GameSession.changeset(game_session, %{top_card_id: regular_card_in_hand.id})
  |> Repo.update!()
  |> Repo.preload([:top_card, deck: [deck_cards: :card]], force: true)

# Now find another valid card to play (matching suit or rank)
top_card = game_session.top_card

player1_cards =
  game_session.deck.deck_cards
  |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player1.id))
  |> Enum.map(& &1.card)

valid_card =
  player1_cards
  |> Enum.find(fn card ->
    # Must be a regular card (Phase 1 restriction)
    is_regular = card.rank in ["4", "5", "6", "7", "9", "10"]
    # Must match top card suit or rank
    matches = card.suit == top_card.suit or card.rank == top_card.rank
    # Can't be the same card as top card
    different = card.id != top_card.id
    is_regular and matches and different
  end)

if is_nil(valid_card) do
  IO.puts("ERROR: No valid card found for benchmark")
  System.halt(1)
end

IO.puts("Game setup complete. Player1 will play #{valid_card.rank} of #{valid_card.suit}")
IO.puts("Top card is #{top_card.rank} of #{top_card.suit}")

# Run benchmark
IO.puts("\n=== Running benchmark (10 iterations) ===")

iterations = 10
durations = []

durations =
  Enum.reduce(1..iterations, [], fn i, acc ->
    # Reset game state for each iteration
    game_session = Repo.get!(GameSession, game_session.id)
    game_session = Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

    # Ensure it's player1's turn
    game_session =
      if game_session.current_turn_player_id != player1.id do
        GameSession.changeset(game_session, %{current_turn_player_id: player1.id})
        |> Repo.update!()
        |> Repo.preload([:top_card, deck: [deck_cards: :card]], force: true)
      else
        game_session
      end

    # Find a valid card for this iteration
    player1_cards =
      game_session.deck.deck_cards
      |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player1.id))
      |> Enum.map(& &1.card)

    valid_card =
      player1_cards
      |> Enum.find(fn card ->
        # Must be a regular card (Phase 1 restriction)
        is_regular = card.rank in ["4", "5", "6", "7", "9", "10"]
        # Must match top card suit or rank
        matches =
          card.suit == game_session.top_card.suit or card.rank == game_session.top_card.rank

        is_regular and matches
      end)

    if is_nil(valid_card) do
      IO.puts("  Iteration #{i}: Skipped (no valid card)")
      acc
    else
      # Measure play_cards duration
      start_time = System.monotonic_time(:microsecond)
      {:ok, _} = CardGames.play_cards(game_session, player1.id, [valid_card.id])
      duration = System.monotonic_time(:microsecond) - start_time

      IO.puts("  Iteration #{i}: #{duration} μs")
      [duration | acc]
    end
  end)

# Calculate statistics
durations = Enum.reverse(durations)
count = length(durations)
avg_duration = Enum.sum(durations) / count
min_duration = Enum.min(durations)
max_duration = Enum.max(durations)
# 100ms in microseconds
target = 100_000

IO.puts("\n=== Results ===")
IO.puts("Iterations: #{count}")
IO.puts("Average: #{Float.round(avg_duration, 2)} μs (#{Float.round(avg_duration / 1000, 2)} ms)")
IO.puts("Min: #{min_duration} μs (#{Float.round(min_duration / 1000, 2)} ms)")
IO.puts("Max: #{max_duration} μs (#{Float.round(max_duration / 1000, 2)} ms)")
IO.puts("Target: #{target} μs (100 ms)")

if avg_duration < target do
  IO.puts(
    "\n✅ PASS: Average duration (#{Float.round(avg_duration / 1000, 2)} ms) is below 100ms target"
  )
else
  IO.puts(
    "\n❌ FAIL: Average duration (#{Float.round(avg_duration / 1000, 2)} ms) exceeds 100ms target"
  )
end

# Cleanup
IO.puts("\n=== Cleaning up ===")
Repo.delete!(player1)
Repo.delete!(player2)
IO.puts("Benchmark complete")
