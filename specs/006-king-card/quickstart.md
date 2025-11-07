# Quickstart: King Card Reversal Feature

## 1. Apply Migrations
```
mix ecto.gen.migration add_direction_and_lock_version_to_game_sessions
# Migration A:
#   alter table(:game_sessions) do
#     add :direction, :string, default: "clockwise", null: false
#     add :lock_version, :integer, default: 0, null: false
#   end
#   execute "ALTER TABLE game_sessions ADD CONSTRAINT direction_valid CHECK (direction IN ('clockwise','counter_clockwise'))"

mix ecto.gen.migration add_status_to_game_session_players
# Migration B:
#   alter table(:game_session_players) do
#     add :status, :string, default: "normal", null: false
#   end
#   execute "ALTER TABLE game_session_players ADD CONSTRAINT player_status_valid CHECK (status IN ('normal','cardless'))"

mix ecto.migrate
```

## 2. Update Schemas
- `game_session.ex`: add `:direction` field and inclusion validation (no optimistic_lock wiring at this time)
- `game_session_player.ex`: add `:status` field ("normal"|"cardless") and validations

## 3. Implement King Logic
- Extend `PlayValidator` with `validate_king_play/3` (suit/rank match & single king rule)
- Flow: enforce turn gating, apply reversal, update `top_card_id`, emit telemetry, commit in a single transaction

## 4. Player Status Handling
- After King as last card: set `status="cardless"`
- On their next turn: detect `status=="cardless"`, auto draw, set `status="normal"`, end turn

## 5. Telemetry Events
```
:telemetry.execute([:kadi, :king, :direction_change], %{count: 1}, metadata)
:telemetry.execute([:kadi, :king, :cardless_entered], %{}, metadata)
:telemetry.execute([:kadi, :king, :anomaly_skip], %{}, metadata)
```
Attach handler in app start if not existing.

## 6. LiveView UI
- Persistent indicator: icon + localized text; assigns: `:direction`
- Toast: use rate-limited coalescing (assign last_change_at + timer ref)
- Banner for anomaly skip

## 7. Tests
- Unit: validator (valid/invalid king plays, direction toggles)
- Integration: cardless state transition, anomaly skip simulation
- LiveView: direction indicator + toast rate limit
- Telemetry: assert events emitted

## 8. Logging & Privacy
- Ensure emitted metadata excludes PII (only IDs)

## 9. i18n Keys
Add to Gettext domain (example):
```
"game.direction.reversed" => "Direction reversed: now %{direction}" 
"game.anomaly.deck_exhausted" => "Deck exhausted. Skipping %{player}" 
"game.direction.clockwise" => "Clockwise" 
"game.direction.counter_clockwise" => "Counter-clockwise"
```

## 10. Retry Strategy
Not required for this feature due to turn gating. Ensure all mutations for a play occur within the same Ecto.Multi for atomicity.

## 11. Deployment Considerations
- Run migrations before deploying new code
- Monitor logs for anomaly_skip frequency (should be near zero)
