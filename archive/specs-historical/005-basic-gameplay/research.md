# Phase 0: Research & Technical Decisions

**Feature**: Basic Gameplay - Regular Cards  
**Date**: 2025-11-06

## Overview

This document captures technical research and decisions for implementing the core gameplay mechanics for regular cards in the Kadi card game.

## Research Areas

### 1. Card Play Validation Strategy

**Decision**: Pure function-based validation with pattern matching

**Rationale**:
- Elixir's pattern matching excels at matching suit/number combinations
- Pure functions enable easy testing without database dependencies
- Validation logic can be composed and reused for different card types
- Aligns with Constitution principle of "pattern matching first"

**Implementation Approach**:
```elixir
defmodule Kadi.Games.PlayValidator do
  # Pure validation functions
  def valid_play?(cards, top_card, player_hand)
  def valid_single_card?(card, top_card)
  def valid_combo?(cards, top_card)
  def same_number?(cards)
  def matches_suit_or_number?(card, top_card)
end
```

**Alternatives Considered**:
- Rule engine pattern: Too complex for simple matching logic
- Database constraints: Validation should happen before persistence
- Changeset validation: Not suitable for cross-entity validation

---

### 2. Turn Management

**Decision**: Dedicated TurnManager module with sequential turn progression

**Rationale**:
- Single responsibility: Separates turn logic from play validation
- Testable: Can test turn progression independently
- Extensible: Easy to add special cards that skip/reverse turns later
- Constitution compliance: Small, focused functions

**Implementation Approach**:
```elixir
defmodule Kadi.Games.TurnManager do
  def current_player(game_session)
  def advance_turn(game_session)
  def can_play?(game_session, player_id)
end
```

**Alternatives Considered**:
- GenServer for turn state: Overkill for simple sequential progression
- Database-only approach: Would require additional queries for validation
- Inline in GameSession: Violates single responsibility

---

### 3. Deck Recycling and Shuffling

**Decision**: ✅ **REUSE EXISTING** - Leverage `CardGames.recycle_played_stack/1` from feature 004

**Rationale**:
- Feature 004-recycle-played-stack already implements complete recycling logic
- Uses `Enum.shuffle/1` for randomization as required
- Automatically triggered by `draw_card_from_deck/2` when deck is empty
- Already tested and production-ready
- **Constitution 1.5**: Reuse before rebuild

**Existing Implementation** (from `lib/kadi/card_games.ex`):
```elixir
def recycle_played_stack(game_session) do
  # 1. Get played cards, exclude topmost
  # 2. Shuffle remaining cards with Enum.shuffle/1
  # 3. Assign new order_index values (1..N)
  # 4. Move cards from played_stack to deck
  # 5. Clear player_id on recycled cards
  # 6. Execute atomic transaction with Ecto.Multi
end
```

**Integration Approach**:
- NO NEW CODE NEEDED - Function already called by `draw_card_from_deck/2`
- When deck is empty, draw function automatically triggers recycle and retries
- Feature 005 only needs to call `draw_card_from_deck/2` for "no valid play" scenario

**Alternatives Considered**:
- ❌ Reimplementing shuffle logic: Violates Constitution 1.5 (reuse before rebuild)
- ❌ Custom shuffle algorithm: Already solved by feature 004
- ❌ Direct invocation: Not needed - automatic in draw flow

---

### 4. State Management and Atomicity

**Decision**: Use Ecto.Multi for atomic game state updates

**Rationale**:
- Ensures all-or-nothing updates (hand, played stack, turn, deck)
- Prevents partial state corruption on errors
- Aligns with Constitution performance requirement for batch operations
- Enables easy rollback on validation failures

**Implementation Approach**:
```elixir
Multi.new()
|> Multi.update(:remove_from_hand, remove_cards_changeset)
|> Multi.update(:add_to_stack, add_to_stack_changeset)
|> Multi.update(:advance_turn, advance_turn_changeset)
|> Repo.transaction()
```

**Alternatives Considered**:
- Sequential updates: Risk of partial failures and inconsistent state
- GenServer state: Loses persistence benefits of database
- Single large changeset: Harder to test and maintain

---

### 5. Real-Time Updates via PubSub

**Decision**: Phoenix.PubSub for broadcasting game state changes

**Rationale**:
- Already configured in Phoenix application
- Meets UX requirement for real-time updates (Constitution)
- Supports multiple subscribers per game session
- Low latency for <100ms update requirement

**Implementation Approach**:
```elixir
# After successful play
Phoenix.PubSub.broadcast(
  Kadi.PubSub,
  "game:#{game_session_id}",
  {:game_updated, game_state}
)

# In LiveView
@impl true
def handle_info({:game_updated, game_state}, socket) do
  {:noreply, assign(socket, :game, game_state)}
end
```

**Alternatives Considered**:
- Polling: Higher latency, more server load
- Server-Sent Events: More complex than PubSub for bidirectional
- WebSockets only: PubSub provides higher-level abstraction

---

### 6. Card Notation Protocol

**Decision**: Compact string format "4H 4D" for client-server communication

**Rationale**:
- Human-readable and debuggable
- Minimal payload size
- Easy to parse with String.split and pattern matching
- Case-insensitive for better UX (per spec)

**Implementation Approach**:
```elixir
def parse_card_notation(notation) do
  notation
  |> String.upcase()
  |> String.split(" ", trim: true)
  |> Enum.map(&parse_single_card/1)
end

defp parse_single_card(<<number::binary-size(1), suit::binary-size(1)>>) do
  # Handle single-digit numbers
end
defp parse_single_card(<<number::binary-size(2), suit::binary-size(1)>>) do
  # Handle two-digit numbers (10)
end
```

**Alternatives Considered**:
- JSON with card objects: More verbose, unnecessary complexity
- Binary protocol: Harder to debug, premature optimization
- Card IDs only: Loses semantic meaning in logs

---

### 7. Frontend Card Selection UI

**Decision**: LiveView components with click handlers and selected state

**Rationale**:
- Leverages LiveView's built-in state management
- No separate frontend framework needed
- Server-side validation prevents client-side manipulation
- Aligns with Phoenix architecture (minimal client JS)

**Implementation Approach**:
```heex
<.card_hand 
  cards={@player_hand}
  selected={@selected_cards}
  on_select={&handle_card_select/1}
/>
```

**Alternatives Considered**:
- React/Vue.js: Adds complexity, violates Phoenix LiveView architecture
- Alpine.js: Still requires separate state management
- Pure JS: Harder to maintain than LiveView components

---

### 8. Error Handling and User Feedback

**Decision**: LiveView flash messages and inline validation feedback

**Rationale**:
- Phoenix flash provides temporary user feedback
- Inline errors near UI elements (Constitution UX requirement)
- Errors returned from context functions map to user messages
- Maintains optimistic UI with rollback pattern

**Implementation Approach**:
```elixir
case CardGames.play_cards(game_session, player_id, cards) do
  {:ok, updated_game} ->
    socket
    |> put_flash(:info, "Cards played successfully")
    |> assign(:game, updated_game)
    
  {:error, :invalid_play, reason} ->
    socket
    |> put_flash(:error, "Invalid play: #{reason}")
    |> assign(:selected_cards, [])  # Clear selection
end
```

**Alternatives Considered**:
- Modal dialogs: More disruptive to game flow
- Console logging only: Fails accessibility requirements
- Silent failures: Violates Constitution UX principles

---

## Dependencies and Libraries

All required dependencies already present in mix.exs:
- **Phoenix**: Web framework and LiveView
- **Ecto**: Database ORM and query builder
- **Phoenix.PubSub**: Real-time message broadcasting
- **Postgrex**: PostgreSQL adapter
- **Phoenix.LiveView**: Real-time UI updates

No new dependencies required.

---

## Performance Considerations

### Database Queries
- **Preload strategy**: Load player hands and played stack in single query
- **Indexing**: Ensure indexes on `game_session_id`, `player_id` in junction tables
- **Query plan**: Use `Ecto.Query.preload/3` to avoid N+1 queries

### Validation Performance
- **Pure functions**: Validation happens in memory, no DB calls
- **Early returns**: Use guard clauses to fail fast on invalid inputs
- **Minimal allocations**: Pattern matching avoids temporary data structures

### Real-time Updates
- **Targeted broadcasts**: Only to game participants, not global
- **Payload optimization**: Send minimal game state, not full database records
- **Debouncing**: Not needed for turn-based gameplay

---

## Security Considerations

### Input Validation
- **Server-side validation**: All validation happens in context, never trust client
- **Player ownership**: Verify player_id matches current turn before processing
- **Card existence**: Validate player actually has cards before removing from hand

### State Integrity
- **Atomic operations**: Ecto.Multi ensures consistent state
- **Rollback on errors**: Database transactions automatically rollback
- **Concurrent play prevention**: Turn validation prevents simultaneous plays

---

## Testing Strategy

### Unit Tests
- **PlayValidator**: Test all validation rules with pure functions
- **TurnManager**: Test turn progression logic
- **Card notation parser**: Test all valid/invalid formats

### Integration Tests
- **CardGames context**: Test full play flow with database
- **Deck recycling**: Test empty deck handling and shuffling
- **Error cases**: Test all rejection scenarios

### LiveView Tests
- **Play card interaction**: Test card selection and submission
- **Draw card interaction**: Test draw button and state updates
- **Real-time updates**: Test PubSub broadcasts to multiple clients
- **Error display**: Test flash messages and inline errors

### Property-Based Tests (Optional Enhancement)
- **Deck conservation**: Total cards in (hands + stack + deck) = constant
- **Turn sequence**: Turn counter always increases sequentially
- **Valid plays**: Generated valid plays always succeed

---

## Migration Requirements

### Database Changes

**Status**: No schema changes required for MVP

The existing schema already supports the required entities:
- `game_sessions`: Tracks current turn
- `game_session_players`: Links players to games  
- `cards`: Card definitions with suit and rank
- `decks`: Game deck instance
- `deck_cards`: Junction table for cards in deck
- Similar structures exist for hands and played stack

**Potential Future Enhancements**:
- Add `current_turn_index` to `game_sessions` for explicit turn tracking
- Add `last_action_type` enum for better game state debugging
- Add composite index on `(game_session_id, position)` for stack ordering

---

## Monitoring and Observability

### Telemetry Events
```elixir
:telemetry.execute(
  [:kadi, :game, :play_card],
  %{duration: duration},
  %{game_id: game_id, valid: valid, card_count: card_count}
)
```

### Logging
- **Info level**: Successful plays with game_id and player_id
- **Warning level**: Invalid play attempts
- **Error level**: Unexpected validation failures or state corruption

### Metrics (Future)
- Play validation latency (p50, p95, p99)
- Invalid play rate per game
- Average cards played per turn
- Deck recycling frequency

---

## Open Questions and Future Research

### Phase 2+ Considerations
1. **Special card effects**: How will 2 (pick 2), 8 (skip), Jack (reverse) integrate?
2. **Multiple game variants**: Support for different rule sets?
3. **Replay/undo**: Should we store play history for debugging?
4. **AI players**: Framework for bot opponents?

### Performance Optimization Opportunities
1. **Caching**: Cache current turn in game session to avoid queries?
2. **Projection**: Maintain denormalized view of game state?
3. **Connection pooling**: Current pool size adequate for 50 concurrent games?

---

## Summary

All technical decisions are grounded in:
- ✅ Elixir/Phoenix best practices
- ✅ Constitution requirements (pattern matching, pure functions, testing)
- ✅ Performance targets (<100ms updates)
- ✅ Existing codebase architecture

**Ready for Phase 1**: Data model design and contract definition.
