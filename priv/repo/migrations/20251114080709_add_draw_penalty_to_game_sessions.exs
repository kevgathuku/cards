defmodule Kadi.Repo.Migrations.AddDrawPenaltyToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :draw_penalty, :map, default: %{}
    end
  end
end
