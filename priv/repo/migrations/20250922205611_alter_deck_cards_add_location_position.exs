defmodule Kadi.Repo.Migrations.AlterDeckCardsAddLocationPosition do
  use Ecto.Migration

  def change do
    alter table(:deck_cards) do
      # New: "deck", "played_stack", "player_hand"
      add :location_type, :string, null: false
      # Nullable, used for "deck" and "played_stack"
      add :order_index, :integer
    end

    # Update indexes if needed
    create index(:deck_cards, [:location_type])
    create unique_index(:deck_cards, [:deck_id, :location_type, :order_index])
  end
end
