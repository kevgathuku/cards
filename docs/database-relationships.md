# Database Relationships & Cascade Behavior

**Last Reviewed**: 2025-11-06  
**Status**: ✅ Verified and Correct

## Summary

The database schema is properly configured to ensure that **Players are never deleted when GameSessions are deleted**. All cascade relationships are working correctly.

## Relationship Map

```
Players (never deleted when GameSessions are removed)
   ↑
   │ (protected by on_delete: :restrict)
   │
   ├─── game_sessions.created_by_id
   │    ├─ on_delete: :restrict → Cannot delete Player who created games
   │    └─ Schema: belongs_to :created_by
   │
   ├─── game_sessions.current_turn_player_id  
   │    ├─ on_delete: :nilify_all → Sets to NULL if Player deleted
   │    └─ Schema: belongs_to :current_turn_player
   │
   ├─── game_session_players.player_id
   │    ├─ on_delete: :restrict → Cannot delete Player in any game
   │    └─ Schema: belongs_to :player
   │
   └─── deck_cards.player_id
        ├─ on_delete: :nothing → Orphans reference (but DeckCard itself is deleted)
        └─ Schema: belongs_to :player

GameSessions (cascade deletes properly)
   │
   ├─── Decks (game_session_id)
   │    ├─ on_delete: :delete_all
   │    └─ Cascades → DeckCards
   │         └─ on_delete: :delete_all
   │              └─ Player references remain (via :nothing)
   │
   └─── GameSessionPlayers (game_session_id)
        └─ on_delete: :delete_all
             └─ Player references remain (via :restrict)
```

## Cascade Behavior When GameSession Deleted

**Action**: `Repo.delete!(game_session)`

**Cascade Chain**:
1. ✅ `game_session_players` records deleted (on_delete: :delete_all)
   - Player objects remain intact
2. ✅ `decks` record deleted (on_delete: :delete_all)
3. ✅ `deck_cards` records deleted (on_delete: :delete_all from deck)
   - Player references become orphaned but DeckCards are deleted
4. ✅ `current_turn_player_id` set to NULL in any other sessions (on_delete: :nilify_all)

**Result**: ✅ Players remain in database, all related game data is cleaned up

## Detailed Foreign Key Constraints

### Protecting Players

| Foreign Key | Table | On Delete | Effect |
|------------|-------|-----------|---------|
| `created_by_id` | game_sessions | `:restrict` | ✅ Prevents player deletion if they created games |
| `player_id` | game_session_players | `:restrict` | ✅ Prevents player deletion if in any game |
| `player_id` | deck_cards | `:nothing` | ⚠️ Orphans reference (but safe because DeckCard is deleted) |
| `current_turn_player_id` | game_sessions | `:nilify_all` | ✅ Safe fallback - sets to NULL |

### Cascade Deletions

| Foreign Key | Table | On Delete | Effect |
|------------|-------|-----------|---------|
| `game_session_id` | decks | `:delete_all` | ✅ Deletes deck when game deleted |
| `deck_id` | deck_cards | `:delete_all` | ✅ Deletes all cards when deck deleted |
| `game_session_id` | game_session_players | `:delete_all` | ✅ Deletes join records when game deleted |

### No Cascade (Shared Resources)

| Foreign Key | Table | On Delete | Effect |
|------------|-------|-----------|---------|
| `card_id` | deck_cards | `:restrict` | ✅ Prevents deletion of shared Card resources |

## Verification Test

A test was run to verify the cascade behavior:

```elixir
# Create 2 players
# Create game session with both players
# Start the game (deals cards)
# Delete game session
# Verify players still exist ✅

# Result: SUCCESS - Players remained after GameSession deletion
```

**Test Output**: ✅ All players existed after GameSession deletion

## Migration Files

Key migrations defining these relationships:

1. **`20250928105630_alter_game_sessions_created_by.exs`**
   - `created_by_id` → `on_delete: :restrict`

2. **`20250928185027_create_game_session_players.exs`**
   - `game_session_id` → `on_delete: :delete_all`
   - `player_id` → `on_delete: :restrict`

3. **`20250922203946_create_deck_cards.exs`**
   - `deck_id` → `on_delete: :delete_all`
   - `card_id` → `on_delete: :restrict`
   - `player_id` → `on_delete: :nothing`

4. **`20250922200611_create_decks.exs`**
   - `game_session_id` → `on_delete: :delete_all`

5. **`20251103184537_add_current_turn_player_to_game_sessions.exs`**
   - `current_turn_player_id` → `on_delete: :nilify_all`

## Schema Consistency

All Ecto schemas properly use `assoc_constraint/2` to validate associations:

```elixir
# game_session.ex
|> assoc_constraint(:created_by)
|> assoc_constraint(:current_turn_player)

# game_session_player.ex
|> assoc_constraint(:game_session)
|> assoc_constraint(:player)

# deck_card.ex
|> assoc_constraint(:deck)
|> assoc_constraint(:card)
|> assoc_constraint(:player)
```

## Recommendations

### Current Status: ✅ Safe and Correct

No changes are required. The database is properly configured.

### Optional Enhancement

Consider changing `deck_cards.player_id` from `:nothing` to `:restrict` for more explicit protection:

```elixir
# Current (works fine):
add :player_id, references(:players, on_delete: :nothing)

# More explicit alternative:
add :player_id, references(:players, on_delete: :restrict)
```

**Reason**: More explicit protection, though in practice players are already protected by `game_session_players` constraint.

**Priority**: Low (cosmetic improvement only)

## Deck Card Ordering System

**Last Reviewed**: 2025-11-06  
**Status**: ✅ Documented

### Order Index Semantics

The `order_index` field on `deck_cards` determines the position of cards in the deck and played stack:

- **Range**: Integer > 0 (validation: `order_index > 0`)
- **Deck ordering**: Lower `order_index` = top of deck (drawn first)
- **Played stack ordering**: Higher `order_index` = top of played stack (visible card)

### Drawing Cards from Deck

When drawing a card via `draw_card_from_deck/2`:

```elixir
# Get cards in deck location
deck_cards
|> Enum.filter(&(&1.location_type == "deck"))
|> Enum.sort_by(& &1.order_index)  # Ascending sort

# Draw first card (lowest order_index)
[card_to_draw | _] = sorted_deck_cards
```

**Key Decision**: The card with the **lowest order_index is drawn first** (top of deck).

**Example**:
- Cards with order_index 1, 5, 10, 15 in deck
- Draw operation takes card with order_index = 1
- Next draw takes card with order_index = 5

### Initial Deck Shuffling

When a deck is created:

```elixir
# Shuffle indices 1..52
order_indices = Enum.shuffle(1..52)

# Assign shuffled indices to cards
Enum.zip([cards, order_indices])
|> Enum.each(fn {card_attrs, order_index} ->
  # Each card gets a random order_index from 1-52
end)
```

**Result**: Cards are randomly distributed across order_index values 1-52.

### Recycling Played Stack

When recycling cards back to deck via `recycle_played_stack/1`:

```elixir
# Find topmost played card (highest order_index)
topmost_card = Enum.max_by(played_cards, & &1.order_index)

# Get all other cards for recycling
recyclable_cards = Enum.reject(played_cards, &(&1.id == topmost_card.id))

# Shuffle and reassign indices 1..N
shuffled_indices = Enum.shuffle(1..num_cards)

# Reassign as deck cards with new order_index
```

**Key Decisions**:
1. Topmost card (highest order_index) stays in played stack
2. Other cards get shuffled order_index values starting from 1
3. Cards move from `played_stack` to `deck` location

### Played Stack Ordering

When cards are played to the played stack:

```elixir
# First card played gets order_index: 1
changeset = DeckCard.changeset(start_card, %{
  location_type: "played_stack", 
  order_index: 1
})

# Subsequent plays increment order_index
# Latest played card has highest order_index
```

**Visible Card**: The card with the **highest order_index** in played_stack is the "top" card that determines valid plays.

### Summary Table

| Location | Order Direction | Accessed From |
|----------|----------------|---------------|
| **Deck** | Lowest first | `order_index` ascending (1, 2, 3...) |
| **Played Stack** | Highest is top | `order_index` descending (...3, 2, 1) |
| **Player Hand** | No ordering | `order_index` is `nil` |

### Validation Rules

From `deck_card.ex`:

```elixir
# Player hand cards have no order
"player_hand" -> validate_is_nil(:order_index)

# Deck and played stack cards must have order > 0
"deck" -> validate_number(:order_index, greater_than: 0)
"played_stack" -> validate_number(:order_index, greater_than: 0)
```

## Related Documentation

- Ecto Foreign Keys: https://hexdocs.pm/ecto_sql/Ecto.Migration.html#references/2
- On Delete Options:
  - `:restrict` - Prevent deletion if references exist
  - `:delete_all` - Cascade delete all references
  - `:nilify_all` - Set references to NULL
  - `:nothing` - Do nothing (orphan the reference)

## Conclusion

✅ **The database relationships are correctly configured**  
✅ **Players are protected from deletion when GameSessions are removed**  
✅ **All cascade deletions work as expected**  
✅ **No changes needed**
