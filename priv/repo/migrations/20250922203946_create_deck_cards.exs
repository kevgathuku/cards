defmodule Kadi.Repo.Migrations.CreateDeckCards do
  use Ecto.Migration

  def change do
    create table(:deck_cards) do
      add :deck_id, references(:decks, on_delete: :delete_all), null: false

      # prevents deleting a card if it’s in any deck
      add :card_id, references(:cards, on_delete: :restrict), null: false

      # Optional, for player-specific positions
      add :player_id, references(:players, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:deck_cards, [:deck_id, :card_id])  # One card per deck
    create index(:deck_cards, [:deck_id])
    create index(:deck_cards, [:card_id])
    create index(:deck_cards, [:player_id])
  end
end
