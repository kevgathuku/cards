# Data migration script to convert old penalty format to new format
# Run with: mix run priv/repo/migrate_penalty_data.exs
#
# This script migrates the draw_penalty field from the old format:
#   %{active: true, count: 2, target_player_id: 123}
# To the new format:
#   %{active: true, penalty_type: "two", target_player_id: 123}

alias Kadi.Repo
alias Kadi.Games.GameSession
import Ecto.Query

IO.puts("\n=== Starting Penalty Data Migration ===\n")

# Find all game sessions with old penalty format (has count field)
# Using the ?| operator to check if the jsonb object has the 'count' key
query =
  from gs in GameSession,
    where: fragment("? \\?| array['count']", gs.draw_penalty)

game_sessions = Repo.all(query)

IO.puts("Found #{length(game_sessions)} game sessions with old penalty format")

if length(game_sessions) == 0 do
  IO.puts("No game sessions to migrate. Migration complete!")
  System.halt(0)
end

IO.puts("\nMigrating game sessions...\n")

results =
  Enum.map(game_sessions, fn gs ->
    updated_penalty =
      cond do
        # Active penalty with count=2 -> set penalty_type to "two"
        gs.draw_penalty["active"] == true and gs.draw_penalty["count"] == 2 ->
          gs.draw_penalty
          |> Map.put("penalty_type", "two")
          |> Map.delete("count")

        # Inactive penalty -> just remove count field, set penalty_type to nil
        gs.draw_penalty["active"] == false ->
          %{active: false, penalty_type: nil, target_player_id: nil}

        # Other cases (shouldn't happen, but handle gracefully)
        true ->
          IO.puts(
            "  ⚠️  Game session #{gs.id} has unexpected penalty state: #{inspect(gs.draw_penalty)}"
          )

          %{active: false, penalty_type: nil, target_player_id: nil}
      end

    case gs
         |> Ecto.Changeset.change(%{draw_penalty: updated_penalty})
         |> Repo.update() do
      {:ok, _updated_gs} ->
        IO.puts("  ✓ Migrated game session #{gs.id} (#{gs.short_code})")
        :ok

      {:error, changeset} ->
        IO.puts("  ✗ Failed to migrate game session #{gs.id}: #{inspect(changeset.errors)}")
        :error
    end
  end)

migrated_count = Enum.count(results, &(&1 == :ok))
error_count = Enum.count(results, &(&1 == :error))

IO.puts("\n=== Migration Summary ===")
IO.puts("Total found: #{length(game_sessions)}")
IO.puts("Successfully migrated: #{migrated_count}")
IO.puts("Errors: #{error_count}")

if error_count > 0 do
  IO.puts("\n⚠️  Migration completed with errors. Please review the error messages above.")
  System.halt(1)
else
  IO.puts("\n✓ Migration completed successfully!")
  System.halt(0)
end
