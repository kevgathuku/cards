# Backfill script to add top_card_id to existing game sessions
# Run with: mix run priv/repo/backfill_top_card.exs

require Logger

alias Kadi.Repo
alias Kadi.Games.GameSession

import Ecto.Query

# Find all live game sessions without a top_card_id
query =
  from g in GameSession,
    where: g.status == "live" and is_nil(g.top_card_id),
    preload: [deck: [deck_cards: :card]]

game_sessions = Repo.all(query)

IO.puts("Found #{length(game_sessions)} game sessions without top_card_id")

Enum.each(game_sessions, fn game_session ->
  IO.puts("\nProcessing game session ##{game_session.id}...")

  # Find the card with the highest order_index in played_stack
  top_card =
    game_session.deck.deck_cards
    |> Enum.filter(&(&1.location_type == "played_stack"))
    |> Enum.max_by(& &1.order_index, fn -> nil end)

  case top_card do
    nil ->
      IO.puts("  ⚠️  No cards in played_stack - skipping (game may not have started properly)")

    deck_card ->
      # Update the game_session with the top_card_id
      case game_session
           |> Ecto.Changeset.change(%{top_card_id: deck_card.card_id})
           |> Repo.update() do
        {:ok, _updated} ->
          IO.puts(
            "  ✅ Set top_card_id to #{deck_card.card_id} (#{deck_card.card.rank} of #{deck_card.card.suit})"
          )

        {:error, changeset} ->
          IO.puts("  ❌ Failed to update: #{inspect(changeset.errors)}")
      end
  end
end)

IO.puts("\n✅ Backfill complete!")
