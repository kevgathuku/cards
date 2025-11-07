# LiveView & Telemetry Events: King Card Feature (Internal Contract)

## LiveView Events (Client → Server)
| Event | Payload | Description | Error Modes |
|-------|---------|-------------|-------------|
| `play_card` | `%{card_id: binary()}` | Request to play a single card (King or normal) on player's turn | `:not_your_turn`, `:invalid_play` |
| `draw_card` | `%{}` | Request (or auto trigger) to draw a card; rejected if not needed or auto-handled | `:not_your_turn`, `:not_allowed` |

### Turn Gating
Server verifies `socket.assigns.current_player_id == player_id`; otherwise replies with error payload:
```json
{"status":"error","reason":"not_your_turn"}
```

## LiveView Broadcast Assign Updates (Server → Clients)
| Assign | Type | Trigger | Notes |
|--------|------|---------|-------|
| `direction` | "clockwise" | "counter_clockwise" | After valid King play | Persistent indicator update |
| `toast` | map or nil | King reversal / coalesced burst | Contains i18n key + interpolations |
| `banner` | map or nil | Anomaly skip scenario | i18n key `game.anomaly.deck_exhausted` + player ref |
| `player_statuses` | map `%{player_id => "normal"|"cardless"}` | After King last-card / auto-draw | Drives UI for forced draw state |

## Telemetry Events (Server Emission)
| Event Name | Measurements | Metadata |
|------------|--------------|----------|
| `[:kadi,:king,:direction_change]` | `%{}` | `game_id, player_id, previous_direction, new_direction, card_id, timestamp` |
| `[:kadi,:king,:cardless_entered]` | `%{}` | `game_id, player_id, card_id, timestamp` |
| `[:kadi,:king,:anomaly_skip]` | `%{}` | `game_id, player_id, deck_state, timestamp` |

### Example Handler Attachment
```elixir
:telemetry.attach(
  "king-direction-logger",
  [:kadi, :king, :direction_change],
  fn _event, _measurements, meta, _config ->
    Logger.info("direction_change #{inspect(meta)}")
  end,
  nil
)
```

## Error Payloads (LiveView replies/pushes)
| Reason Atom | Description | Suggested Message Key |
|-------------|-------------|-----------------------|
| `:not_your_turn` | Player tried action out of turn | `game.error.not_your_turn` |
| `:invalid_play` | Card does not match suit/rank or multi-K attempt | `game.error.invalid_play` |
| `:cardless_wait` | Cardless player attempted play before forced draw | `game.error.cardless_wait` |

## Rate Limiting Contract
- Coalescing window: 2s.
- `toast.updated_at` timestamp updates; LiveView merges new direction into existing toast without spawning a second.

## Accessibility
- Toast rendered in container `role="status" aria-live="polite"`.
- Persistent indicator: text + icon; assigns updated atomically.

## Privacy
- No PII in telemetry metadata; only IDs.

## Localization Keys
| Key | Example Text |
|-----|--------------|
| `game.direction.reversed` | "Direction reversed: now %{direction}" |
| `game.anomaly.deck_exhausted` | "Deck exhausted. Skipping %{player}" |
| `game.direction.clockwise` | "Clockwise" |
| `game.direction.counter_clockwise` | "Counter-clockwise" |
| `game.error.not_your_turn` | "It's not your turn." |
| `game.error.invalid_play` | "You can't play that card." |
| `game.error.cardless_wait` | "You must draw before playing." |

## Future Extensions
- Additional status values (e.g., "stunned") add to `player_statuses` map and i18n keys.
- Persistent audit events table if fairness metrics required.
