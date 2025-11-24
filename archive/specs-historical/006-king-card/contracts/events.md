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
**Implementation**: See quickstart.md §6 for LiveView update code.

| Assign | Type | Trigger | Notes |
|--------|------|---------|-------|
| `direction` | "clockwise" \| "counter_clockwise" | After valid King play | Persistent indicator update (see §6.2) |
| `toast` | map or nil | King reversal / coalesced burst | Contains i18n key + interpolations; auto-dismiss after 2s (FR-025) |
| `banner` | map or nil | Anomaly skip scenario | i18n key `game.anomaly.deck_exhausted` + player ref |
| `player_statuses` | map `%{player_id => status}` | After King last-card / auto-draw | Drives UI for forced draw state; status values: "normal" \| "cardless" |

### Assign Examples

#### direction
```elixir
# Simple string value
socket.assigns.direction  # => "clockwise" or "counter_clockwise"

# Updated atomically when King played
# Used by direction indicator component (§6.2)
```

#### toast
```elixir
# Structure when present
%{
  message: "Direction reversed: now Counter-clockwise",  # Localized string
  updated_at: 123456789  # System.monotonic_time() for coalescing
}

# nil when no toast active
nil

# Toast timer ref also stored in assigns for cleanup
socket.assigns.toast_timer  # => #Reference<...> or nil
```

#### player_statuses
```elixir
# Map of player_id to status string
%{
  101 => "normal",
  102 => "cardless",  # This player must draw next turn
  103 => "normal",
  104 => "cardless"   # Multiple cardless players allowed (FR-014)
}

# Used to show badges/indicators in player UI
# Updated after King play and after auto-draw
```

#### banner
```elixir
# Anomaly notification structure
%{
  type: "anomaly_skip",
  player_id: 102,
  message: "Deck exhausted. Skipping Player 2 this turn."
}

# Or nil when no anomaly
nil
```

## Telemetry Events (Server Emission)
**Implementation**: See quickstart.md §5 for helper functions and attachment code.  
**Testing**: See quickstart.md §7.4 for telemetry test patterns.

| Event Name | Measurements | Metadata |
|------------|--------------|----------|
| `[:kadi,:king,:direction_change]` | `%{}` | `game_id, player_id, previous_direction, new_direction, card_id, neutral, timestamp` |
| `[:kadi,:king,:cardless_entered]` | `%{}` | `game_id, player_id, reason, card_id, timestamp` |
| `[:kadi,:king,:anomaly_skip]` | `%{}` | `game_id, player_id, deck_state, timestamp` |

### Metadata Details

#### direction_change
```elixir
%{
  game_id: 123,                          # Integer/UUID
  player_id: 456,                        # Integer
  previous_direction: "clockwise",       # String
  new_direction: "counter_clockwise",    # String
  card_id: 789,                          # Integer (the King card played)
  neutral: false,                        # Boolean - true for 2-player games (FR-009)
  timestamp: ~U[2025-11-07 12:34:56Z]   # DateTime
}

# Example: 2-player game (neutral = true)
%{
  game_id: 100,
  player_id: 50,
  previous_direction: "clockwise",
  new_direction: "counter_clockwise",  # Direction changes...
  card_id: 25,
  neutral: true,                       # ...but has no turn order effect
  timestamp: ~U[2025-11-07 12:35:00Z]
}
```

#### cardless_entered
```elixir
%{
  game_id: 123,
  player_id: 456,
  reason: "king_last_card",            # Currently only one reason
  card_id: 789,                        # The King card that was last card
  timestamp: ~U[2025-11-07 12:34:56Z]
}

# Multiple players can be cardless simultaneously (FR-014)
# Each player's cardless entry emits separate event
```

#### anomaly_skip
```elixir
%{
  game_id: 123,
  player_id: 456,                      # Player whose turn was skipped
  deck_state: "no_cards_after_recycle", # String describing anomaly
  timestamp: ~U[2025-11-07 12:34:56Z]
}

# This should be extremely rare in normal gameplay
```

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
**Implementation**: Returned by CardGames context functions; handled in GameLive (see quickstart.md §3).

| Reason Atom | Description | Suggested Message Key | Spec Reference |
|-------------|-------------|----------------------|----------------|
| `:not_your_turn` | Player tried action out of turn | `game.error.not_your_turn` | FR-027 |
| `:invalid_play` | Card does not match suit/rank or multi-K attempt | `game.error.invalid_play` | FR-004, FR-005 |
| `:cardless_wait` | Cardless player attempted play before forced draw | `game.error.cardless_wait` | FR-012, FR-013 |

### Error Response Examples

```elixir
# Returned from CardGames.play_cards/3
{:error, :not_your_turn}
{:error, :invalid_play}
{:error, :cardless_wait}

# Converted to LiveView push/reply
%{
  status: "error",
  reason: "not_your_turn",
  message: "It's not your turn."  # Localized
}
```

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
