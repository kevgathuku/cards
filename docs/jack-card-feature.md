# Jack Card Feature (Feature 007)

**Status**: ✅ Production Ready  
**Version**: 1.0.0  
**Specification**: `/specs/007-jack-card/`

---

## Overview

The Jack card introduces skip mechanics to the Kadi card game. Playing one or more Jacks advances
the turn by the number of Jacks played while respecting the current table direction. When a Jack (or
Jack combo) empties a player's hand, the player enters the existing "cardless" state instead of
winning the round.

---

## Core Mechanics

### Skip Logic
- Single Jack skips exactly one opponent and passes the turn to the next eligible player.
- Jack combos skip `N` players where `N` equals the number of Jacks played in that turn.
- Skip calculation honours current direction, including counter-clockwise flows after a King.
- Cardless players are excluded from skip counting to prevent soft-locks.

### Jack + King Interaction
- If a King was played previously, the Jack skip proceeds counter-clockwise.
- Playing a Jack after a King does not reset direction; the turn simply jumps backward.
- Playing a King after a Jack keeps the skip distance while toggling direction.

### Starting Card Behaviour
- Jacks are excluded from the starting card pool during dealing.
- If a Jack is manually set as the top card (e.g. via admin tooling) no automatic skip occurs.

### Cardless Continuation
- Playing a Jack (or combo) as the final card transitions the player to `"cardless"`.
- Cardless players auto-draw one card when their turn returns, then revert to `"normal"`.

---

## Visual & UX Indicators

- Toast notifications already introduced in Feature 006 surface anomalies triggered during Jack
  play (e.g. deck exhaustion).
- The existing direction indicator mirrors King behaviour; no new UI assets were required.
- Cardless badges reuse the same styling as the King workflow.

---

## Database Touchpoints

| Table                 | Fields Impacted                          | Notes                                                |
|-----------------------|------------------------------------------|------------------------------------------------------|
| `game_sessions`       | `direction`, `current_turn_player_id`     | Turn advancement uses skip-aware helper              |
| `game_session_players`| `status`                                  | Jack last card sets status to `"cardless"`           |
| `deck_cards`          | `location_type`, `player_id`, `order_index`| Tracks Jacks moving from deck → hand → played stack  |

No schema changes or new migrations were required.

---

## Telemetry & Observability

### Events

#### Skip Executed
```elixir
[:kadi, :jack, :skip_executed]

# Measurements
%{skip_count: non_neg_integer}

# Metadata
%{
  game_session_id: integer,
  player_id: integer,
  from_player_id: integer,
  to_player_id: integer,
  jack_count: non_neg_integer,
  card_ids: [integer]
}
```

#### Cardless Entered
```elixir
[:kadi, :jack, :cardless_entered]

# Metadata
%{
  game_session_id: integer,
  player_id: integer,
  card_id: integer,
  reason: "jack_last_card"
}
```

Both events follow the existing King telemetry pattern and contain no PII.

---

## Validation Rules

- Every card in a Jack play must be rank `"jack"`.
- The first Jack must match the top card's suit or rank.
- Jacks can be played in combos (unlike Kings).
- Mixed-rank combos containing Jacks are rejected.
- Validation is enforced via `Kadi.Games.PlayValidator.valid_jack_play?/2` and covered by ExUnit.

---

## Edge Cases Covered

| Scenario                                 | Behaviour                                                     |
|------------------------------------------|----------------------------------------------------------------|
| 2-player game                            | Jack skips the opponent and returns turn to same player        |
| Wrap-around (4 Jacks, 3 players)         | Skip calculation uses modulo arithmetic to land correctly      |
| Jack after King                          | Skip moves counter-clockwise without flipping direction       |
| King after Jack                          | Direction flips while respecting the pre-computed skip target |
| Cardless players in skip path            | Cardless players are skipped over automatically                |
| Deck exhaustion during auto-draw         | Reuses anomaly handling introduced in Feature 006              |

---

## Testing

### Automated Coverage
- `mix test` (315 tests, 24 doctests) ✅
- `mix test test/kadi/card_games_test.exs` (Phase 8 focus) ✅
- Targeted coverage: `Kadi.CardGames` 90.88%, `Kadi.Games.PlayValidator` 92.31%

### Key Test Suites
- `test/kadi/card_games_test.exs`: end-to-end skip behaviour, direction interplay, cardless flow.
- `test/kadi/games/play_validator_test.exs`: Jack validation rules and rejection cases.
- `test/kadi_web/live/game_live_test.exs`: LiveView turn protection and selection resets.

### Manual QA Checklist
- Start 3-player game, play single Jack → verify one skip.
- Play double Jack combo → verify two skips with wrap-around.
- Play King then Jack → verify counter-clockwise skip.
- Empty hand with Jack combo → ensure cardless badge and auto-draw.

---

## Performance Notes

- Skip calculation is O(1) using indexed list lookups and modulo arithmetic.
- All operations execute inside an `Ecto.Multi` to keep database writes atomic.
- Telemetry emission adds negligible overhead (< 1 ms in benchmarks).

---

## Known Limitations

- Manual UI testing is required to observe skip animations; no Cypress coverage yet.
- Overall project test coverage remains below the 90% global threshold because of legacy modules
  outside the Jack feature scope.

---

## Related Documentation

- Feature Spec: `/specs/007-jack-card/spec.md`
- Implementation Plan: `/specs/007-jack-card/plan.md`
- Task Breakdown: `/specs/007-jack-card/tasks.md`
- Data Model Notes: `/specs/007-jack-card/data-model.md`
- Research Decisions: `/specs/007-jack-card/research.md`
- King Feature Reference: `/docs/king-card-feature.md`

---

**Last Updated**: 2025-11-10  
**Maintainer**: Kadi Development Team
