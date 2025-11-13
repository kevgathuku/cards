# Tasks: Two Card Draw Penalty (Feature 009)

Checklist of implementation tasks, mapped to user stories, requirements, and contracts. Each task is independently testable and references exact file locations.

---

## User Story 1: Player plays a '2' card to force next player to draw (P1)
- [ ] Update data model: Add `draw_penalty` field to `GameSession` schema and struct (`lib/kadi/games/game_session.ex`)
	- Est: 1h; Purpose: persist penalty state so game logic and UI can read/write penalty details atomically.
- [ ] Implement penalty activation logic in `play_card/3` (`lib/kadi/card_games.ex`)
	- Est: 6h; Purpose: core behavior to set `draw_penalty` when a valid '2' is played and advance game turn appropriately.
- [ ] Enforce validation: '2' must match suit/rank, cannot be starting/finishing card (`lib/kadi/games/play_validator.ex`)
	- Est: 2h; Purpose: prevent invalid plays and enforce spec rules at the validation layer.
- [ ] Update penalty state transitions per contract (`lib/kadi/card_games.ex`)
	- Est: 2h; Purpose: ensure state changes (activate/clear/transfer) follow contracts and are safe for concurrent players.
- [ ] Add/extend tests for penalty activation (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 3h; Purpose: unit tests to assert correct `draw_penalty` behavior and basic activation scenarios.
 - [ ] Ensure starting-card selection excludes rank '2' during game initialization (`lib/kadi/card_games.ex` or `lib/kadi/games/deck.ex`)
	- Est: 1h; Purpose: enforce spec that '2' cannot be a starting card at game setup.
 - [ ] Use `Ecto.Multi` to perform penalty activation and related updates atomically (`lib/kadi/card_games.ex`)
	- Est: 2h; Purpose: prevent partial updates and race conditions when updating multiple DB rows (deck, hands, session state).
 - [ ] Broadcast penalty activation events via PubSub so LiveView updates reliably (`lib/kadi/card_games.ex`, `lib/kadi_web/live/game_live.ex`)
	- Est: 2h; Purpose: notify connected clients of state changes reliably; enables UI synchronization across players.

## User Story 2: Next player blocks '2' penalty with an Ace (P2)
- Purpose: Allow players to block a '2' penalty with an Ace, clearing the penalty and setting the requested suit. Ensures UI and state transitions match the contract, and edge cases are covered.
- Est: ~13h (T009-009 to T009-013)
- [ ] Implement block logic: Ace clears penalty, sets requested_suit to suit of '2' (`lib/kadi/card_games.ex`)
	- Est: 4h; Purpose: implement Ace semantics for blocking without prompting for suit selection and clearing penalty.
- [ ] Prevent suit selection when blocking with Ace (`lib/kadi_web/live/game_live.ex`)
	- Est: 2h; Purpose: UI change to stop suit-prompt flow when Ace used as a block.
- [ ] Update state transitions for Ace block (`lib/kadi/card_games.ex`)
	- Est: 1h; Purpose: reflect the contract that Ace clears penalty and sets `requested_suit` to the '2' suit.
- [ ] Add/extend tests for Ace block (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 2h; Purpose: ensure Ace blocking behavior works and `requested_suit` semantics are correct.
 - [ ] Add tests that verify `requested_suit` is set to the '2' suit and persists/clears according to rules (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 2h; Purpose: capture edge cases where requested suit persists or is cleared by subsequent plays.

## User Story 3: Next player blocks '2' penalty with another '2' (P2)
- Purpose: Enable penalty transfer by playing another '2', supporting chain reactions and tactical counterplay. Includes contract-aligned transitions and multi-player test coverage.
- Est: ~10h (T009-014 to T009-017)
- [ ] Implement block logic: '2' transfers penalty to next player (`lib/kadi/card_games.ex`)
	- Est: 3h; Purpose: implement transfer semantics so penalty moves to the subsequent player without accumulating.
- [ ] Update state transitions for '2' block (`lib/kadi/card_games.ex`)
	- Est: 1h; Purpose: keep contract-aligned transitions (target_player_id moves forward, `count` remains 2).
- [ ] Add/extend tests for '2' block/transfer (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 3h; Purpose: verify simple transfer scenarios and edge cases where rank/suit matching matters.
 - [ ] Add tests for chain scenarios (A plays '2', B plays '2', C has no blocker) and ensure penalty transfers correctly (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 3h; Purpose: ensure multi-player chain transfers produce correct target and final draw.

## User Story 4: Multiple '2' cards in one play have the same effect (P3)
- Purpose: Enforce non-additive penalty for combo plays, ensuring fairness and preventing overpowered moves. Includes explicit tests for guardrails and edge cases.
- Est: ~5h (T009-018 to T009-020)
- [ ] Enforce non-additive penalty: multiple '2's = draw 2, not cumulative (`lib/kadi/card_games.ex`, `lib/kadi/games/play_validator.ex`)
	- Est: 2h; Purpose: ensure combo plays do not multiply penalty count.
- [ ] Add/extend tests for combo play (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 2h; Purpose: unit tests for several combo permutations (2x '2', 3x '2', mixed suits).
 - [ ] Add explicit unit test that playing multiple '2's from the same turn does not increase `draw_penalty.count` beyond 2 (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 1h; Purpose: explicit guardrail test to prevent regressions for non-additive rule.

## User Story 5: Player has no blocking cards and must draw 2 cards (P2)
- Purpose: Implement auto-draw and deck recycling logic for penalty resolution, enforcing turn-ending and non-playable drawn cards. Robustly handles edge cases and ensures deterministic behavior.
- Est: ~12h (T009-021 to T009-024)
- [ ] Implement auto-draw logic for penalty (`lib/kadi/card_games.ex`)
	- Est: 4h; Purpose: core logic to force drawing 2 cards at turn start and end the player's turn.
- [ ] Handle deck recycling if <2 cards (`lib/kadi/card_games.ex`)
	- Est: 3h; Purpose: robust handling of small-deck edge cases per spec (recycle play pile, preserve top card).
- [ ] Add/extend tests for auto-draw, deck recycling, edge cases (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 3h; Purpose: ensure drawing behavior is deterministic and handles recycling correctly.
 - [ ] Add test to ensure players who draw due to penalty cannot play any drawn cards in the same turn (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 2h; Purpose: enforce rule that drawn cards are not playable until next turn.

## UI Feedback & Edge Cases
- Purpose: Provide clear UI feedback and persistent indicators for penalty state, enforce exclusion rules, and ensure robust event handling and integration test coverage for all connected players.
- Est: ~15h (T009-025 to T009-031)
- [ ] Show penalty notification in LiveView UI (`lib/kadi_web/live/game_live.ex`)
	- Est: 3h; Purpose: notify the affected player(s) with a clear message explaining why cards were drawn.
- [ ] Add persistent visual indicator for penalty (`lib/kadi_web/live/game_live.ex`, `assets/css/app.css`)
	- Est: 2h; Purpose: keep a visible badge/icon showing "Draw 2 penalty active" for all players.
- [ ] Add/extend UI tests for notification/indicator (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 3h; Purpose: verify UI elements appear for all connected players after penalty events.
- [ ] Enforce exclusion of '2' as starting/finishing card (`lib/kadi/games/play_validator.ex`)
	- Est: 1h; Purpose: ensure finishing/starting rules are consistently enforced by validation.
- [ ] Log anomaly if draw deck is empty and cannot recycle (`lib/kadi/card_games.ex`)
	- Est: 1h; Purpose: surface runtime anomalies for debugging/observability (non-blocking behavior).
 - [ ] Ensure LiveView event handlers wait for PubSub broadcast (no optimistic local-only updates) to avoid state races (`lib/kadi_web/live/game_live.ex`)
	- Est: 1h; Purpose: prevent UI inconsistencies by relying on canonical broadcasted state.
 - [ ] Add integration test that verifies the notification + visual indicator appear for all connected players after penalty activation (`test/kadi/card_games/special_cards_two_test.exs`)
	- Est: 4h; Purpose: end-to-end verification across pubsub + LiveView flows.

## Validation & Best Practices
- Purpose: Validate feature correctness, code style, documentation, and contract updates. Ensure backward compatibility and maintainability for future contributors.
- Est: ~6h (T009-032 to T009-037)
- [ ] Run `mix test` and ensure all tests pass
	- Est: 1h; Purpose: verify behavior and guard regressions locally.
- [ ] Run `mix format` for code style
	- Est: 0.5h; Purpose: maintain code style and satisfy pre-commit checks.
- [ ] Validate backward compatibility and DRY principle
	- Est: 2h; Purpose: ensure changes do not break existing game flows or duplicate logic.
- [ ] Update documentation as needed (`specs/009-two-card/quickstart.md`, `README.md`)
	- Est: 1h; Purpose: keep spec and quickstart up to date for reviewers and future contributors.
 - [ ] Review and update `contracts/*` docs if behaviour/signatures changed (`specs/009-two-card/contracts/*.md`)
	- Est: 1h; Purpose: reflect any API/contract changes so integration points remain documented.
 - [ ] Add a short code comment where `Ecto.Multi` is used to explain atomicity reasoning
	- Est: 0.5h; Purpose: help future maintainers understand transactional choices.
