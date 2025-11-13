# Research: Two Card Draw Penalty (Feature 009)
## Version Details & Compatibility

- **Elixir**: ~> 1.17 (from mix.exs)
- **Phoenix**: ~> 1.7.21
- **Phoenix LiveView**: ~> 1.1
- **Ecto SQL**: ~> 3.10
- **bcrypt_elixir**: ~> 3.0
- **postgrex**: >= 0.0.0
- **phoenix_ecto**: ~> 4.5
- **esbuild**: ~> 0.8
- **tailwind**: ~> 0.2.0

## Additional Research Areas
- Ecto struct state management for real-time games ([Ecto.Schema docs](https://hexdocs.pm/ecto/Ecto.Schema.html), [ElixirForum](https://elixirforum.com/))
- LiveView notification/indicator UI patterns ([LiveView docs](https://hexdocs.pm/phoenix_live_view), [Tailwind docs](https://tailwindcss.com/docs), [ElixirForum](https://elixirforum.com/))
- ExUnit async/Ecto Sandbox configuration for optimal test isolation ([ExUnit docs](https://hexdocs.pm/ex_unit), [ElixirForum](https://elixirforum.com/))
- Upgrade paths and compatibility notes for all dependencies ([Elixir blog](https://elixir-lang.org/blog/2025/10/16/elixir-v1-19-0-released/), [PostgreSQL release notes](https://www.postgresql.org/docs/release/))
## Decision: Penalty Mechanism
- The '2' card creates a draw penalty for the next player (draw 2 cards).
- Penalty can be blocked by Ace (clears penalty, sets suit) or another '2' (transfers penalty).
- If '2' is played as last card, penalty still applies to next player.
- '2' cannot be starting card.

## Rationale
- Consistent with Ace/Jack/King special card features.
- Ensures fair gameplay and clear rules for penalty transfer/blocking.
- UI feedback (notification + visual indicator) improves user experience.

## Alternatives Considered
- Allowing '2' as starting/finishing card (rejected for clarity and fairness).
- Cumulative penalties for multiple '2's (rejected, not additive).
- Allowing suit selection after Ace blocks '2' (rejected, suit of '2' applies).

## Data Model Review
- GameSession: tracks current turn, penalties, requested suit.
- Player: hand, status.
- Card: suit, rank.
- DrawPenalty: tracked as part of GameSession state (no new table needed).

## Integration Patterns
- Reuse context logic from Ace/Jack/King features.
- Penalty state managed in GameSession struct.
- UI updates via LiveView events and PubSub.

## Best Practices
- Use tagged tuples for error handling.
- All changes must be backward compatible.
- No duplicate logic or tests.
- Schema changes must be verified against code/migrations.
- Feature must integrate with existing game flow.

## References
- Feature 006 (King), 007 (Jack), 008 (Ace)
- docs/database-relationships.md
- .specify/memory/constitution.md
