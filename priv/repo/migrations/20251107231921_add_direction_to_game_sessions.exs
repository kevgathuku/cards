defmodule Kadi.Repo.Migrations.AddDirectionToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :direction, :string, default: "clockwise", null: false
    end

    create constraint(:game_sessions, :direction_must_be_valid,
             check: "direction IN ('clockwise', 'counter_clockwise')"
           )
  end
end
