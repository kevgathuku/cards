defmodule Kadi.Repo.Migrations.CreateDecks do
  use Ecto.Migration

  def change do
    create table(:decks) do
      add :game_session_id, references(:game_sessions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:decks, [:game_session_id])
  end
end
