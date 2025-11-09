# DeckCard Query Functions

This document describes the Rails-style "scopes" implemented as query functions in the Kadi project.

## Overview

We implemented two layers of query functionality:

1. **Query Functions** in `Kadi.Games.DeckCard` - Composable query builders (similar to Rails scopes)
2. **Context Helpers** in `Kadi.CardGames` - Higher-level convenience functions for common operations

## Query Functions (DeckCard module)

These functions follow Ecto's convention of accepting a query as the first parameter with a default value, making them chainable.

### Location Filters

- `in_hand/1` - Filter cards in player hands (`location_type == "player_hand"`)
- `in_deck/1` - Filter cards in deck pile (`location_type == "deck"`)
- `played/1` - Filter cards in played stack (`location_type == "played_stack"`)

### Player Filter

- `for_player/2` - Filter cards belonging to specific player

### Card Attribute Filters

- `of_rank/2` - Filter by card rank (requires join with `cards` table)
- `of_suit/2` - Filter by card suit (requires join with `cards` table)

### Associations

- `with_card/1` - Preload the `card` association

### Ordering

- `ordered/1` - Order by `order_index` ASC
- `ordered_desc/1` - Order by `order_index` DESC

## Usage Examples

### Direct Query Usage

```elixir
import Ecto.Query
alias Kadi.Games.{DeckCard, Deck}

# Get all cards in hands for a game
from(dc in DeckCard,
  join: d in Deck,
  on: dc.deck_id == d.id,
  where: d.game_session_id == ^game_session.id
)
|> DeckCard.in_hand()
|> Repo.all()

# Chain multiple filters
from(dc in DeckCard,
  join: d in Deck,
  on: dc.deck_id == d.id,
  where: d.game_session_id == ^game_session.id
)
|> DeckCard.in_hand()
|> DeckCard.for_player(player_id)
|> DeckCard.of_suit("hearts")
|> DeckCard.with_card()
|> Repo.all()

# Get top card from played stack (using top_card_id for efficiency)
from(dc in DeckCard,
  join: d in Deck,
  on: dc.deck_id == d.id,
  where: d.game_session_id == ^game_session.id and dc.card_id == ^game_session.top_card_id
)
|> DeckCard.played()
|> Repo.one()
```

### Context Helper Usage (Recommended)

```elixir
# Get player's hand (with cards preloaded)
hand = CardGames.get_player_hand(game_session, player_id)

# Count cards in player's hand
count = CardGames.count_player_cards(game_session, player_id)

# Get specific rank from player's hand
jacks = CardGames.get_player_cards_by_rank(game_session, player_id, "jack")

# Get top played card
{:ok, top_card} = CardGames.get_top_played_card(game_session)

# Count remaining deck cards
remaining = CardGames.count_deck_cards(game_session)

# Count played cards
played_count = CardGames.count_played_cards(game_session)
```

## Context Helpers (CardGames module)

These functions provide a higher-level API and handle the complexity of joining through the game_session → deck → deck_cards relationship.

### Available Functions

1. `get_player_hand/2` - Returns list of DeckCards with card association preloaded
2. `count_player_cards/2` - Returns integer count of cards in player's hand
3. `get_player_cards_by_rank/3` - Returns player's cards filtered by rank
4. `get_top_played_card/1` - Returns `{:ok, card}` or `{:error, :no_cards_played}`
5. `count_deck_cards/1` - Returns count of cards in deck pile
6. `count_played_cards/1` - Returns count of cards in played stack

## Design Decisions

### Why Not Use `Ecto.assoc`?

Initial implementation attempted to use `Ecto.assoc(game_session, :deck) |> Ecto.assoc(:deck_cards)` but this doesn't work because:

1. GameSession doesn't have a direct `:deck_cards` association
2. Would require loading associations into memory first
3. Cannot build composable queries from preloaded data

Instead, context helpers build queries using explicit joins:

```elixir
from(dc in DeckCard,
  join: d in Deck,
  on: dc.deck_id == d.id,
  where: d.game_session_id == ^game_session.id
)
```

### When to Use Query Functions vs Context Helpers

**Use Query Functions when:**
- You need custom filtering beyond what helpers provide
- Building complex queries with multiple conditions
- Performance optimization requires specific query structure

**Use Context Helpers when:**
- Performing common operations
- Working at the business logic layer
- Want consistent API across the application

## Testing

Comprehensive test suite in `test/kadi/games/deck_card_queries_test.exs`:

- 11 tests for query functions (composition, filtering, ordering)
- 6 tests for context helpers (practical usage scenarios)
- All tests use actual database transactions for accuracy

## Performance Considerations

- Query functions defer execution - no database hit until `Repo.all()` or `Repo.one()`
- Context helpers always execute queries and return results
- Use `count` helpers instead of loading full lists when only count is needed
- Card preloading is automatic in context helpers to avoid N+1 queries

## Comparison to Rails Scopes

| Rails Scopes | Ecto Query Functions |
|-------------|---------------------|
| `scope :active, -> { where(active: true) }` | `def active(query \\ Model), do: where(query, active: true)` |
| `Model.active.recent.limit(10)` | `Model \|> Model.active() \|> Model.recent() \|> limit(10)` |
| Implicit query building | Explicit query building with `from` or `Ecto.assoc` |
| `Model.active` (no parens) | `Model.active()` (parens required) |
