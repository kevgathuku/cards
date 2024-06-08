defmodule Kadi.Repo.Migrations.CreateGameSession do
  use Ecto.Migration

  def change do
    create table(:game_sessions) do
      add :short_code, :string
      add :created_by, :string

      timestamps(type: :utc_datetime)
    end
  end
end
