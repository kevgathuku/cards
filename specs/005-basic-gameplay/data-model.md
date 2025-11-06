# Phase 1: Data Model

**Feature**: Basic Gameplay - Regular Cards  
**Date**: 2025-11-06

## Overview

This document defines the data model for implementing basic gameplay mechanics. The model leverages existing schemas and adds new structures where needed.

---

## Existing Entities (Actual Implementation)

### GameSession
**Source**: `lib/kadi/games/game_session.ex`

**Attributes**:
- `id` (UUID): Primary key
- `short_code` (string): Unique game identifier for joining
- `status` (string): Enum - "lobby", "live" (NOT "waiting"/"in_progress"/"completed")
- `current_turn_player_id` (UUID, nullable): Foreign key to Player (added in feature 003)
- `created_by_id` (UUID): Foreign key to Player
- `inserted_at`, `updated_at` (utc_datetime timestamps)

**Relationships**:
- `belongs_to :created_by, Player`
- `belongs_to :current_turn_player, Player`
- `has_many :game_session_players, GameSessionPlayer`
- `many_to_many :players, through: "game_session_players"`
- `has_one :deck, Deck`

**Validations**:
- `status` must be "lobby" or "live"
- `short_code` must be unique

**Note**: NO `top_card_id` field exists yet - will need migration for feature 005

---

### GameSessionPlayer
**Source**: `lib/kadi/games/game_session_player.ex`

**Attributes**:
- `id` (UUID): Primary key
- `game_session_id` (UUID): Foreign key
- `player_id` (UUID): Foreign key
- `inserted_at`, `updated_at` (utc_datetime timestamps)

**Relationships**:
- `belongs_to :game_session, GameSession`
- `belongs_to :player, Player`

**Validations**:
- Unique combination of (game_session_id, player_id)

**Note**: 
- NO `turn_order` field - turn order determined by `inserted_at` timestamp (join order)
- NO `hand` field - player cards tracked via DeckCard with location_type='player_hand'

---

### Card
**Source**: `lib/kadi/games/card.ex`

**Attributes**:
- `id` (UUID): Primary key
- `suit` (string): "hearts", "diamonds", "clubs", "spades"
- `rank` (string): "2" through "10", "jack", "queen", "king", "ace"
- `inserted_at`, `updated_at` (utc_datetime timestamps)

**Relationships**:
- `has_many :deck_cards, DeckCard`

**Validations**:
- `suit` must be one of 4 valid suits
- `rank` must be valid (2-10, jack, queen, king, ace)
- Unique combination of (suit, rank)

**Note**: Full 52-card deck; feature 005 focuses on regular cards (4,5,6,7,9,10) but all ranks exist

---

### Deck
**Source**: `lib/kadi/games/deck.ex`

**Attributes**:
- `id` (UUID): Primary key
- `game_session_id` (UUID): Foreign key
- `inserted_at`, `updated_at` (utc_datetime timestamps)

**Relationships**:
- `belongs_to :game_session, GameSession`
- `has_many :deck_cards, DeckCard`
- `has_many :cards, through: [:deck_cards, :card]`

**Validations**:
- `game_session_id` unique (one deck per game)

**Note**: NO `cards` array field - cards tracked via DeckCard join table

---

### DeckCard (Junction Table)
**Source**: `lib/kadi/games/deck_card.ex`

**Attributes**:
- `id` (UUID): Primary key
- `deck_id` (UUID): Foreign key
- `card_id` (UUID): Foreign key
- `player_id` (UUID, nullable): Foreign key to Player
- `location_type` (string): Enum - "deck", "played_stack", "player_hand"
- `order_index` (integer, nullable): Position in deck or played_stack
- `inserted_at`, `updated_at` (utc_datetime timestamps)

**Relationships**:
- `belongs_to :deck, Deck`
- `belongs_to :card, Card`
- `belongs_to :player, Player`

**Validations**:
- `location_type` must be one of: "deck", "played_stack", "player_hand"
- Unique combination of (deck_id, card_id)
- Unique combination of (deck_id, location_type, order_index)
- When `location_type='player_hand'`:
  - `player_id` is required
  - `order_index` must be nil
- When `location_type='deck'` or `'played_stack'`:
  - `player_id` must be nil
  - `order_index` is required and must be > 0 (NOT >= 0)

**Usage**: 
- **Existing model** that already tracks card locations including played stack
- When location_type='played_stack', order_index determines stack position (higher = newer/on top)
- When location_type='deck', order_index determines draw order (lower = drawn first)
- When location_type='player_hand', cards belong to specific player_id

---

## Required Schema Changes for Feature 005

### GameSession - Add top_card_id

**Migration Needed**:
```elixir
defmodule Kadi.Repo.Migrations.AddTopCardToGameSessions do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :top_card_id, references(:cards, on_delete: :nilify_all)
    end

    create index(:game_sessions, [:top_card_id])
  end
end
```

**Schema Update**:
```elixir
# lib/kadi/games/game_session.ex
schema "game_sessions" do
  # ... existing fields ...
  belongs_to :top_card, Kadi.Games.Card  # ADD THIS
  # ...
end
```

**Purpose**: Quick reference to current top card on played stack for validation

**Note**: Top card can also be queried via: "SELECT * FROM deck_cards WHERE location_type='played_stack' ORDER BY order_index DESC LIMIT 1"

**Usage**: Represents a player's action; validated before persisting state changes

---

### CardNotation (Parser Output)

**Definition**: Parsed from client input "4H 4D"

```elixir
defmodule Kadi.Games.CardNotation do
  @type t :: %{
    rank: String.t(),
    suit: String.t()
  }
end
```

**Usage**: Intermediate format for mapping notation to Card entities

---

## Relationships Diagram

```text
GameSession (1)───(∞) GameSessionPlayer (∞)───(1) Player
     │                       │
     │                       └── hand: [Card IDs]
     │
     ├── current_turn: integer
     ├── played_stack: [Card IDs]  (NEW)
     ├── top_card_id: Card ID      (NEW)
     │
     └───(1) Deck (1)───(∞) DeckCard (∞)───(1) Card
                                 │
                                 └── position: integer
```

---

## Validation Rules

### Card Play Validation

**Rule: Single Card Match**
```elixir
# FR-002: Accept single regular cards that match top card
def valid_single_card?(card, top_card) do
  card.suit == top_card.suit or card.rank == top_card.rank
end
```

**Rule: Combo Validation**
```elixir
# FR-003, FR-004: Accept multiple cards with same number, at least one matches
def valid_combo?(cards, top_card) do
  same_number?(cards) and 
  Enum.any?(cards, &valid_single_card?(&1, top_card))
end

defp same_number?(cards) do
  cards
  |> Enum.map(& &1.rank)
  |> Enum.uniq()
  |> length() == 1
end
```

**Rule: Player Has Cards**
```elixir
# FR-015: Validate player has cards in hand
def player_has_cards?(player_hand, card_ids) do
  hand_set = MapSet.new(player_hand)
  cards_set = MapSet.new(card_ids)
  MapSet.subset?(cards_set, hand_set)
end
```

**Rule: Current Turn**
```elixir
# Implicit: Only current player can play
def is_current_player?(game_session, player_id) do
  current_player = get_current_player(game_session)
  current_player.id == player_id
end
```

---

## State Transitions

### Play Card Flow

```text
Initial State (via DeckCard records):
  - Player hand: DeckCard[location_type='player_hand', player_id=P1] → [4H, 4D, 5S, 7C]
  - Played stack: DeckCard[location_type='played_stack'] → [..., 5H (order_index=3)]
  - Top card: 5H (highest order_index in played_stack)
  - Current turn: Player 1

Action: Play ["4H", "4D"]

Validation:
  1. Parse notation → [Card{rank: "4", suit: "H"}, Card{rank: "4", suit: "D"}]
  2. Check player has cards → ✓ (query DeckCard where location_type='player_hand' AND player_id=P1)
  3. Check same number → ✓ (both "4")
  4. Check at least one matches top card → ✓ (4H matches 5H by suit)

State Update (Ecto.Multi):
  1. Update DeckCard for 4H: location_type = "played_stack", order_index = 4, player_id = nil
  2. Update DeckCard for 4D: location_type = "played_stack", order_index = 5, player_id = nil
  3. Update GameSession: top_card_id = {4D id}, current_turn_player_id = {next player}
  4. Broadcast game update

Final State (via DeckCard records):
  - Player hand: DeckCard[location_type='player_hand', player_id=P1] → [5S, 7C]
  - Played stack: DeckCard[location_type='played_stack'] → [..., 5H (idx=3), 4H (idx=4), 4D (idx=5)]
  - Top card: 4D (highest order_index=5 in played_stack)
  - Current turn: Player 2
```

**Note**: Array order in payload ["4H", "4D"] determines order_index assignment (first card gets lower index, last card gets highest index and becomes top card)

---

### Draw Card Flow

**Integration**: Uses existing `CardGames.draw_card_from_deck/2` from feature 003

```text
Initial State:
  - Player hand: [7C, 9S]
  - Played stack: [..., 4H]
  - Deck cards: 5
  - Current turn: Player 1

Precondition: Player has no cards matching 4H

Action: Draw card (via existing draw_card_from_deck/2)

Validation (handled by existing function):
  1. Check current turn → ✓
  2. Check deck not empty → ✓

State Update (handled by existing Ecto.Multi):
  1. Get top card from deck (lowest order_index)
  2. Update card: location_type = "player_hand", player_id = {player}
  3. Update game_session: current_turn_player_id = {next_player}
  4. Broadcast game update

Final State:
  - Player hand: [7C, 9S, {drawn card}]
  - Deck cards: 4
  - Current turn: Player 2
```

---

### Deck Recycling Flow

**Integration**: Automatic via existing `CardGames.recycle_played_stack/1` from feature 004

```text
Initial State:
  - Player hand: [7C, 9S]
  - Played stack: [..., 4H, 5D, 6C]  (20+ cards)
  - Deck cards: 0
  - Current turn: Player 1

Precondition: Player needs to draw but deck is empty

Action: Recycle and draw (automatic via draw_card_from_deck/2)

State Update (handled by existing recycle_played_stack/1 then draw):
  1. Detect deck empty in draw_card_from_deck/2
  2. Call recycle_played_stack/1:
     a. Get all played_stack cards except topmost (6C)
     b. Shuffle recycled cards (Enum.shuffle)
     c. Assign new order_index values (1..N in shuffled order)
     d. Update cards: location_type = "deck", player_id = nil
  3. Retry draw_card_from_deck/2 with recycled deck
  4. Draw card and advance turn
  5. Single broadcast after complete flow

Final State:
  - Player hand: [7C, 9S, {drawn card}]
  - Played stack: [6C]  (topmost card remains)
  - Deck cards: 19
  - Current turn: Player 2
```

**Important**: Feature 005 does NOT reimplement draw or recycle logic - it integrates with existing features 003 and 004.

---

## Indexes and Performance

### Required Indexes

```sql
-- GameSession lookups
CREATE INDEX idx_game_sessions_status ON game_sessions(status);

-- GameSessionPlayer lookups
CREATE INDEX idx_game_session_players_game_id 
  ON game_session_players(game_session_id);
  
CREATE INDEX idx_game_session_players_turn_order 
  ON game_session_players(game_session_id, turn_order);

-- DeckCard ordering
CREATE INDEX idx_deck_cards_position 
  ON deck_cards(deck_id, position);
```

### Query Optimization

**Preload Strategy** (avoid N+1):
```elixir
game_session
|> Repo.preload([
  :game_session_players,
  deck: [deck_cards: :card]
])
```

**Batch Operations**:
```elixir
# Use Ecto.Multi for atomic updates
Multi.new()
|> Multi.update(:game_session, game_changeset)
|> Multi.update_all(:update_hand, hand_query, [])
|> Multi.insert_all(:add_to_stack, DeckCard, stack_entries)
|> Repo.transaction()
```

---

## Migration Scripts

### Add Played Stack to GameSession

```elixir
defmodule Kadi.Repo.Migrations.AddPlayedStackToGameSession do
  use Ecto.Migration

  def change do
    alter table(:game_sessions) do
      add :played_stack, {:array, :binary_id}, default: []
      add :top_card_id, references(:cards, type: :binary_id)
    end

    create index(:game_sessions, [:top_card_id])
  end
end
```

---

## Data Integrity Constraints

### Invariants

1. **Deck Conservation**: 
   ```
   count(all_hands) + count(played_stack) + count(deck) = total_cards
   ```

2. **Turn Bounds**: 
   ```
   0 <= current_turn < player_count
   ```

3. **Top Card Consistency**:
   ```
   top_card_id == List.last(played_stack)
   ```

4. **Hand Validity**:
   ```
   All card IDs in hand exist in cards table
   ```

### Enforcement

- **Application level**: Validation in context functions
- **Database level**: Foreign key constraints
- **Transaction level**: Ecto.Multi ensures atomicity

---

## Summary

**Entities Modified**: GameSession (add played_stack, top_card_id)  
**New Entities**: None (use existing schema)  
**New Modules**: PlayValidator, TurnManager (logic only, no schema)  
**Migrations Required**: 1 (add fields to game_sessions)

**Ready for**: Contract definition and quickstart guide.
