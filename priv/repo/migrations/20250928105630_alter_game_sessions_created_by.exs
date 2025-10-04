defmodule Kadi.Repo.Migrations.AlterGameSessionsCreatedBy do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      # Remove the string field
      remove :created_by
      add :created_by_id, references(:players, on_delete: :restrict), null: false
    end

    create index(:game_sessions, [:created_by_id])
  end
end
