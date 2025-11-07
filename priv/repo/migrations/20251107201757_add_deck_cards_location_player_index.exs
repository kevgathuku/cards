defmodule Kadi.Repo.Migrations.AddDeckCardsLocationPlayerIndex do
  use Ecto.Migration

  def change do
    # Optimize queries that filter by deck_id, location_type, and player_id
    # Common pattern: finding player hands in a specific deck
    create index(:deck_cards, [:deck_id, :location_type, :player_id])
  end
end
