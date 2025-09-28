defmodule Kadi.Repo.Migrations.AlterGameSessionsCreatedBy do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      remove :created_by  # Remove the string field
      add :created_by_id, references(:players, on_delete: :restrict), null: false
    end

    create index(:game_sessions, [:created_by_id])
  end
end
