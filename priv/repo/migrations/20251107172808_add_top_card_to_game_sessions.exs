defmodule Kadi.Repo.Migrations.AddTopCardToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :top_card_id, references(:cards, on_delete: :nilify_all)
    end

    create index(:game_sessions, [:top_card_id])
  end
end
