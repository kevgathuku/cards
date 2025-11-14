defmodule Kadi.Games.GameSession do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["lobby", "live"]
  @directions ["clockwise", "counter_clockwise"]
  @action_types ["select_suit"]
  @suits ["hearts", "diamonds", "clubs", "spades"]

  schema "game_sessions" do
    field :short_code, :string
    field :status, :string, default: "lobby"
    field :direction, :string, default: "clockwise"
    field :action_type, :string
    field :action_suit, :string
    field :draw_penalty, :map, default: %{active: false, count: 0, target_player_id: nil}
    belongs_to :created_by, Kadi.Accounts.Player
    belongs_to :current_turn_player, Kadi.Accounts.Player
    belongs_to :top_card, Kadi.Games.Card
    has_one :deck, Kadi.Games.Deck
    has_many :game_session_players, Kadi.Games.GameSessionPlayer
    many_to_many :players, Kadi.Accounts.Player, join_through: "game_session_players"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_session, attrs) do
    game_session
    |> cast(attrs, [
      :short_code,
      :created_by_id,
      :status,
      :direction,
      :current_turn_player_id,
      :top_card_id,
      :action_type,
      :action_suit
    ])
    |> validate_required([:short_code, :created_by_id, :status, :direction])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:direction, @directions)
    |> validate_inclusion(:action_type, @action_types, allow_nil: true)
    |> validate_inclusion(:action_suit, @suits, allow_nil: true)
    |> assoc_constraint(:created_by)
    |> assoc_constraint(:current_turn_player)
    |> assoc_constraint(:top_card)
    |> unique_constraint(:short_code)
  end
end
