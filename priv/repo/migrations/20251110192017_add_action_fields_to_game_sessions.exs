defmodule Kadi.Repo.Migrations.AddActionFieldsToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :action_type, :string
      add :action_suit, :string
    end
  end
end
