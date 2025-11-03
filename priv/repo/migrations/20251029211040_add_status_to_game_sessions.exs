defmodule Kadi.Repo.Migrations.AddStatusToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :status, :string, null: false, default: "lobby"
    end
  end
end
