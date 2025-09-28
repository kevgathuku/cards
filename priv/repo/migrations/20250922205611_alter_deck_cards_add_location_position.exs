defmodule Kadi.Repo.Migrations.AlterDeckCardsAddLocationPosition do
  use Ecto.Migration

  def change do
    alter table(:deck_cards) do
      add :location_type, :string, null: false  # New: "deck", "played_stack", "player_hand"
      add :order_index, :integer  # Nullable, used for "deck" and "played_stack"
    end

    # Update indexes if needed
    create index(:deck_cards, [:location_type])
    create unique_index(:deck_cards, [:deck_id, :location_type, :order_index])
  end
end
