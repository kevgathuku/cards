defmodule Kadi.Repo.Migrations.CreateGameSessionPlayers do
  use Ecto.Migration

  def change do
    create table(:game_session_players) do
      add :game_session_id, references(:game_sessions, on_delete: :delete_all), null: false
      add :player_id, references(:players, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_session_players, [:game_session_id, :player_id])
    create index(:game_session_players, [:player_id])
  end
end
