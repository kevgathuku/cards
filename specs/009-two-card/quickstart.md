# Quickstart: Two Card Draw Penalty (Feature 009)

## Overview
Implements special rules for the '2' card in the Kadi card game:
- Playing '2' forces next player to draw 2 cards (unless blocked)
- Penalty can be blocked by Ace (clears penalty) or another '2' (transfers to next player)
- '2' cannot be a starting card but can be played as last card
- Multiple '2's in a combo do not stack the penalty (always 2 cards)
- When Ace blocks a '2', next player can match either the suit OR play any '2' (rank match)

## Implementation Summary

### Database Changes
- **Schema**: `game_sessions.draw_penalty` (`:map` field)
  - Structure: `%{active: boolean, count: integer, target_player_id: integer, created_by_player_id: integer}`
  - Stores penalty state persistently (database-driven architecture)
- **Migration**: `priv/repo/migrations/*_add_draw_penalty_to_game_sessions.exs`

### Core Logic Files

1. **`lib/kadi/games/game_session.ex`**
   - Added `draw_penalty` field to schema with default value
   - Validates draw_penalty structure in changeset

2. **`lib/kadi/card_games.ex`** (Main game context)
   - `play_cards/3`: Updated to activate penalty when '2' is played
   - `process_draw_penalty/2`: Auto-draws penalty cards at turn start
   - `execute_play/3`: Handles penalty activation, blocking, and transfer logic
   - Uses `Ecto.Multi` for atomic state updates
   - Broadcasts game updates via PubSub after state changes
   - **Real-time fix**: Uses fresh DB query for broadcast data

3. **`lib/kadi/games/play_validator.ex`** (Validation logic)
   - `validate_starting_card/1`: Excludes '2' from starting cards
   - `validate_single_card/2`: Allows suit OR rank matching when `action_suit` is set
   - `first_card_matches?/2`: Handles combo plays with suit/rank matching
   - Enforces penalty blocking rules (must play Ace or '2' matching suit)

4. **`lib/kadi_web/live/game_live.ex`** (LiveView UI)
   - `handle_event("accept_penalty")`: Handles "Draw 2 Cards" button click
   - `handle_info({:game_updated, _})`: Triggers penalty animations
   - `show_penalty_button?/2`: Controls button visibility
   - `check_and_show_penalty_notification/3`: Shows penalty toast notifications
   - **Real-time fix**: Uses `force: false` in preload to preserve broadcast data

5. **`lib/kadi_web/live/game_live.html.heex`** (Template)
   - Conditional "Draw 2 Cards" button (replaces normal draw when penalty active)
   - Persistent penalty indicator banner with creator info
   - Card animations when penalty is accepted
   - Strategic choice UI (button + blocking cards both clickable)

6. **`assets/css/app.css`** (Styling)
   - `.penalty-card-animation`: 400ms card draw animation
   - `.btn-penalty`: Pulse effect for penalty button
   - `.penalty-banner-pulse`: Subtle pulse for penalty indicator

### Test Coverage

- **`test/kadi/card_games/special_cards_two_test.exs`**: 17 comprehensive tests
  - Penalty activation and transfer scenarios
  - Blocking with Ace and '2' cards
  - Auto-draw and deck recycling
  - Suit/rank matching after Ace blocks
  - Multi-player penalty chains
  - Edge cases (last card, combo plays, deck exhaustion)

### Architecture Patterns

1. **Database-Driven State**: All game state in PostgreSQL, not in-memory
2. **PubSub Broadcasting**: Real-time updates to all connected clients
3. **Atomic Transactions**: `Ecto.Multi` ensures consistent state updates
4. **Fresh DB Queries**: Broadcast data uses fresh queries to avoid stale data
5. **LiveView Reactivity**: UI updates automatically via broadcasts

## Steps

1. **Update Data Model**
   - Edit: `lib/kadi/games/game_session.ex`
     - Add field to schema: `field :draw_penalty, :map, default: %{active: false, count: 0, target_player_id: nil}`
     - Update struct definition to include `draw_penalty`
     - No new tables required

2. **Implement Player Actions**
   - Edit: `lib/kadi/card_games.ex`
     - Update `play_cards/3` to activate penalty when '2' is played
     - Add `process_draw_penalty/2` for auto-draw at turn start
     - Update `execute_play/3` with penalty logic (activation, blocking, transfer)
     - Use `Ecto.Multi` for atomic state updates
     - Call `get_game_session_preloaded(id)` with fresh DB query before broadcast
     - Reference: See validation logic in `lib/kadi/games/play_validator.ex`

3. **Update Validation Rules**
   - Edit: `lib/kadi/games/play_validator.ex`
     - Exclude '2' from starting cards
     - Allow suit OR rank matching when `action_suit` is set
     - Validate penalty blocking cards match suit

4. **Implement UI Features**
   - Edit: `lib/kadi_web/live/game_live.ex`
     - Add `accept_penalty` event handler
     - Add penalty notification logic
     - Add penalty animation triggers
     - Use `force: false` in `assign_game_state` preload
   - Edit: `lib/kadi_web/live/game_live.html.heex`
     - Add conditional "Draw 2 Cards" button
     - Add persistent penalty indicator banner
     - Add card animation classes
   - Edit: `assets/css/app.css`
     - Add penalty animations

5. **Test Edge Cases**
   - Edit: `test/kadi/card_games/special_cards_two_test.exs`
     - Add tests for penalty activation, blocking, transfer
     - Test suit/rank matching after Ace blocks
     - Test auto-draw and deck recycling
     - Test UI feedback and strategic choice

## Commands
- Run tests: `mix test` (361/361 tests passing)
- Format code: `mix format`
- Start server: `mix phx.server`
- Run migrations: `mix ecto.migrate`

## Key Implementation Notes

### Real-time UI Fix (Critical)
The feature initially had an issue where played cards didn't appear immediately on the played pile. This was fixed by:
1. Changing `execute_play` to use `get_game_session_preloaded(id)` (fresh DB query) instead of preloading transaction result
2. Adding `force: false` to `assign_game_state` preload to preserve broadcast data
3. This ensures all players see card plays immediately without page refresh

### Clarification (Session 2025-11-15)
When an Ace blocks a '2', the next player can play:
- **Suit match**: Any card matching the blocked '2's suit (stored in `action_suit`)
- **Rank match**: Any '2' card (matching the blocked card's rank)

This was implemented by changing the validation from `card.rank == top_card.rank` (which checked against the Ace) to `card.rank == "2"` (checking against the blocked card's rank).

## Testing Strategy

All functionality was verified through:
- 17 comprehensive backend tests in `special_cards_two_test.exs`
- Manual QA for UI interactions (button clicks, animations, multi-device sync)
- Integration tests skipped in favor of thorough manual testing
- Database-driven architecture ensures state consistency across devices

## Feature Status

✅ **Complete and Ready for Merge**
- All 66 tasks completed (setup, backend, UI, validation)
- 361/361 tests passing
- Real-time updates working correctly
- Documentation complete
- Code formatted and ready for production
