defmodule Kadi.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards) do
      add :suit, :string, null: false
      add :rank, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cards, [:suit, :rank])
  end
end
