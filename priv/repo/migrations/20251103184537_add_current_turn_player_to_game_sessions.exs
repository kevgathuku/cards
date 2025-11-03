defmodule Kadi.Repo.Migrations.AddCurrentTurnPlayerToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :current_turn_player_id, references(:players, on_delete: :nilify_all)
    end

    create index(:game_sessions, [:current_turn_player_id])
  end
end
