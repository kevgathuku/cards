# API Contracts: Randomize Player Card Distribution

**Date**: 2025-11-03
**Feature**: 002-randomize-player-cards

## Overview

This feature **does not introduce new API contracts** or change existing external interfaces. It modifies internal behavior of the `deal_cards/2` private function.

## Why No Contracts?

1. **Private Function**: `deal_cards/2` is a private helper function in `Kadi.CardGames` context
2. **No External API**: No REST endpoints, GraphQL resolvers, or LiveView events are added or modified
3. **Behavioral Change Only**: The public interface (`start_game/1`) signature and return values remain unchanged
4. **Internal Implementation**: Sorting logic is an internal optimization that doesn't affect callers

## Existing Public Interface (Unchanged)

### Function: `CardGames.start_game/1`

**Module**: `Kadi.CardGames`
**Visibility**: Public
**Purpose**: Starts a game session, deals cards to players, and transitions status to "live"

**Signature**:
```elixir
@spec start_game(GameSession.t()) :: {:ok, GameSession.t()} | {:error, atom()}
```

**Input**:
- `game_session`: A `%GameSession{}` struct with status `"lobby"` and at least 2 players

**Output**:
- `{:ok, updated_game_session}` - Game started successfully
  - `updated_game_session.status` = `"live"`
  - `updated_game_session.current_turn_player_id` = randomly selected player
  - Players have 4 cards each in their hands
  - One valid start card in played pile (as of feature 006-king-card, Kings are allowed as start cards)
- `{:error, :not_enough_players}` - Fewer than 2 players in session
- `{:error, :not_enough_cards_in_deck}` - Deck has insufficient cards (shouldn't happen with 52-card deck)
- `{:error, :no_valid_start_card_found}` - No non-special card available for start (rare edge case - excludes 2, 3, J, Q, A only)

**Behavioral Change** (internal only):
- **Before**: Cards dealt in undefined order (likely database insertion order)
- **After**: Cards dealt in `order_index` sequence (randomized during deck creation)
- **Observable Effect**: Player hands have more randomized distribution (no sequential patterns like 4,5,6,7 of hearts)

**Contract Stability**: ✅ **Stable** - No breaking changes to signature, parameters, or return types

## LiveView Events (Unchanged)

### Event: `game_updated`

**Topic**: `"game:" <> game_session.id`
**Trigger**: After successful `start_game/1`
**Payload**:
```elixir
%{game_session: updated_game_session}
```

**No Changes**: Payload structure remains identical. Only the internal card distribution order differs.

## Database Schema (Unchanged)

No migrations or schema changes. Existing `order_index` field is used as designed.

## Summary

**API Contract Status**: ✅ **No changes required**

This feature is a pure internal optimization. All public interfaces, return values, and event payloads remain stable and backward-compatible.
