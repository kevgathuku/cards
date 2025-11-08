defmodule Kadi.Repo.Migrations.AddStatusToGameSessionPlayers do
  use Ecto.Migration

  def change do
    alter table(:game_session_players) do
      add :status, :string, default: "normal", null: false
    end

    create constraint(:game_session_players, :status_must_be_valid,
             check: "status IN ('normal', 'cardless')"
           )
  end
end
