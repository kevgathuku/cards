# Tasks: Two Card Draw Penalty (Feature 009)

**Input**: Design documents from `/specs/009-two-card/`
**Prerequisites**: plan.md, spec.md

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Core data model changes that must be complete before other tasks.

- [ ] T001 Update GameSession schema to include `draw_penalty` map in `lib/kadi/games/game_session.ex`

---

## Phase 2: User Story 1 - Player plays a '2' to create a penalty (P1) 🎯 MVP

**Goal**: A player can play a '2' card, forcing the next player to draw two cards.
**Independent Test**: Start a game, play a valid '2', and verify the next player is penalized.

- [ ] T002 [P] [US1] Create new test file for 'Two' card feature in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T003 [US1] Add test for penalty activation when a '2' is played in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T004 [US1] Implement penalty activation logic within `play_card/3` in `lib/kadi/card_games.ex`
- [ ] T005 [US1] Refactor penalty activation to use `Ecto.Multi` for atomic state updates in `lib/kadi/card_games.ex`
- [ ] T006 [US1] Update `play_validator.ex` to enforce that a '2' cannot be a starting or finishing card in `lib/kadi/games/play_validator.ex`
- [ ] T007 [US1] Add validation to ensure a played '2' matches the active `requested_suit` (FR-006) in `lib/kadi/games/play_validator.ex`
- [ ] T008 [US1] Ensure starting-card selection logic excludes rank '2' in `lib/kadi/card_games.ex`
- [ ] T009 [US1] Broadcast penalty activation events via PubSub from `lib/kadi/card_games.ex`

---

## Phase 3: User Story 2 & 3 - Player blocks a penalty (P2)

**Goal**: A player facing a penalty can block it with an Ace or another '2'.
**Independent Test**: Start a game, create a penalty, and verify the next player can successfully play a blocking card.

- [ ] T010 [P] [US2] Add test for blocking a penalty with an Ace in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T011 [P] [US3] Add test for blocking and transferring a penalty with another '2' in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T012 [P] [US3] Add test for multi-player penalty chain reactions (A->B->C) in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T013 [US2] Implement logic to block a penalty with an Ace in `lib/kadi/card_games.ex`
- [ ] T014 [US3] Implement logic to block and transfer a penalty with another '2' in `lib/kadi/card_games.ex`
- [ ] T015 [US2] Add validation to ensure a blocking card matches the active `requested_suit` (FR-007) in `lib/kadi/games/play_validator.ex`
- [ ] T016 [US2] Prevent suit selection prompt in UI when an Ace is used for blocking in `lib/kadi_web/live/game_live.ex`

---

## Phase 4: User Story 4 & 5 - Penalty Resolution (P2/P3)

**Goal**: A player who cannot block must draw, and combo plays are not additive.
**Independent Test**: Create a penalty and verify a player with no blockers auto-draws. Play multiple '2's and verify penalty is not stacked.

- [ ] T017 [P] [US4] Add test to ensure playing multiple '2's does not stack the penalty count in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T018 [P] [US5] Add test for auto-draw when a player has no blocking cards in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T019 [P] [US5] Add test for deck recycling when player must draw more cards than are in the deck in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T020 [P] [US5] Add test to ensure a player's turn ends after drawing and they cannot play the drawn cards in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T021 [US4] Implement validation to ensure combo '2' plays are not additive in `lib/kadi/games/play_validator.ex`
- [ ] T022 [US5] Implement auto-draw logic for penalized players at turn start in `lib/kadi/card_games.ex`
- [ ] T023 [US5] Implement deck recycling logic for when the deck is empty during a draw in `lib/kadi/card_games.ex`
- [ ] T024 [US5] Log an anomaly if the draw deck is empty and cannot be recycled in `lib/kadi/card_games.ex`

---

## Phase 5: UI Feedback & Polish

**Purpose**: Implement UI indicators and perform final validation.

- [ ] T025 [P] Add integration test to verify penalty notifications appear for all players in `test/kadi/card_games/special_cards_two_test.exs`
- [ ] T026 [P] Implement a flash notification for the penalized player in `lib/kadi_web/live/game_live.ex`
- [ ] T027 [P] Implement a persistent visual indicator on the game board while a penalty is active in `lib/kadi_web/live/game_live.ex`
- [ ] T028 [P] Style the persistent visual indicator using Tailwind CSS in `assets/css/app.css`
- [ ] T029 Run `mix test` and ensure all tests pass
- [ ] T030 Run `mix format` to ensure code style consistency
- [ ] T031 [P] Review feature for backward compatibility and adherence to DRY principle
- [ ] T032 [P] Update `quickstart.md` and `contracts/` with any final implementation details
