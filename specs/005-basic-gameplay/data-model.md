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
- `id` (integer): Primary key (auto-incrementing)
- `short_code` (string): Unique game identifier for joining
- `status` (string): Enum - "lobby", "live" (NOT "waiting"/"in_progress"/"completed")
- `current_turn_player_id` (integer, nullable): Foreign key to Player (added in feature 003)
- `created_by_id` (integer): Foreign key to Player
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
- `id` (integer): Primary key (auto-incrementing)
- `game_session_id` (integer): Foreign key
- `player_id` (integer): Foreign key
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
- `id` (integer): Primary key (auto-incrementing)
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
- `id` (integer): Primary key (auto-incrementing)
- `game_session_id` (integer): Foreign key
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
- `id` (integer): Primary key (auto-incrementing)
- `deck_id` (integer): Foreign key
- `card_id` (integer): Foreign key
- `player_id` (integer, nullable): Foreign key to Player
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

📖 **Reference**: See `docs/database-relationships.md` for:
- Deck card ordering conventions (order_index semantics)
- Played stack ordering (higher order_index = top card)
- Validation rules for DeckCard.location_type

**Usage**: Represents a player's action; validated before persisting state changes

**Note**: NO separate entity needed - plays are validated and immediately persisted as state changes to DeckCard records

---

## Relationships Diagram

```text
GameSession (1)───(∞) GameSessionPlayer (∞)───(1) Player
     │                       
     ├── current_turn_player_id: integer  (references Player)
     ├── top_card_id: integer             (NEW - references Card)
     │
     └───(1) Deck (1)───(∞) DeckCard (∞)───(1) Card
                                 │
                                 ├── location_type: "deck" | "played_stack" | "player_hand"
                                 ├── order_index: integer (for deck/played_stack)
                                 └── player_id: integer (for player_hand)
```

**Note**: 
- Player hands tracked via DeckCard WHERE location_type='player_hand' AND player_id={id}
- Played stack tracked via DeckCard WHERE location_type='played_stack' ORDER BY order_index DESC
- Deck cards tracked via DeckCard WHERE location_type='deck' ORDER BY order_index ASC

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

📖 **Reference**: See `spec.md` FR-002 for complete single card requirements

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

📖 **Reference**: See `spec.md` FR-003, FR-004 for combo play requirements

**Rule: Player Has Cards**
```elixir
# FR-015: Validate player has cards in hand
def player_has_cards?(player_id, deck_id, card_ids) do
  # Query DeckCard to get player's hand
  hand_card_ids = from(dc in DeckCard,
    where: dc.deck_id == ^deck_id and 
           dc.location_type == "player_hand" and 
           dc.player_id == ^player_id,
    select: dc.card_id
  ) |> Repo.all()
  
  # Check if all played cards are in hand
  hand_set = MapSet.new(hand_card_ids)
  cards_set = MapSet.new(card_ids)
  MapSet.subset?(cards_set, hand_set)
end
```

📖 **Reference**: See `spec.md` FR-015 for player validation requirements

**Rule: Current Turn**
```elixir
# Implicit: Only current player can play
def is_current_player?(game_session, player_id) do
  game_session.current_turn_player_id == player_id
end
```

📖 **Reference**: See `spec.md` FR-008 for turn validation requirements

---

## State Transitions

### Play Card Flow

```text
Initial State (via DeckCard records):
  - Player hand: DeckCard[location_type='player_hand', player_id=P1] → [4H, 4D, 5S, 7C]
  - Played stack: DeckCard[location_type='played_stack'] → [..., 5H (order_index=3)]
  - Top card: GameSession.top_card_id → 5H
  - Current turn: GameSession.current_turn_player_id → P1

Action: Play ["4H", "4D"]

Validation:
  1. Parse notation → [Card{rank: "4", suit: "H"}, Card{rank: "4", suit: "D"}]
  2. Check player has cards → ✓ (query DeckCard where location_type='player_hand' AND player_id=P1)
  3. Check same number → ✓ (both "4")
  4. Check at least one matches top card → ✓ (4H matches 5H by suit)

State Update (Ecto.Multi):
  1. Update DeckCard for 4H: location_type = "played_stack", order_index = 4, player_id = nil
  2. Update DeckCard for 4D: location_type = "played_stack", order_index = 5, player_id = nil
  3. Update GameSession: top_card_id = {4D card id}, current_turn_player_id = {next player id}
  4. Broadcast game update

Final State (via DeckCard records):
  - Player hand: DeckCard[location_type='player_hand', player_id=P1] → [5S, 7C]
  - Played stack: DeckCard[location_type='played_stack'] → [..., 5H (idx=3), 4H (idx=4), 4D (idx=5)]
  - Top card: GameSession.top_card_id → 4D
  - Current turn: GameSession.current_turn_player_id → P2
```

**Note**: Array order in payload ["4H", "4D"] determines order_index assignment (first card gets lower index, last card gets highest index and becomes top card)

📖 **Reference**: See `docs/database-relationships.md` for order_index semantics

---

### Draw Card Flow

**Integration**: Uses existing `CardGames.draw_card_from_deck/2` from feature 003

```text
Initial State:
  - Player hand (via DeckCard): [7C, 9S]
  - Played stack (via DeckCard): [..., 4H]
  - Deck cards: 5 (location_type='deck')
  - Current turn: GameSession.current_turn_player_id → P1

Precondition: Player has no cards matching 4H

Action: Draw card (via existing draw_card_from_deck/2)

Validation (handled by existing function):
  1. Check current turn → ✓ (current_turn_player_id == player_id)
  2. Check deck not empty → ✓

State Update (handled by existing Ecto.Multi):
  1. Get top card from deck (lowest order_index where location_type='deck')
  2. Update DeckCard: location_type = "player_hand", player_id = {player}, order_index = nil
  3. Update GameSession: current_turn_player_id = {next_player id}
  4. Broadcast game update

Final State:
  - Player hand (via DeckCard): [7C, 9S, {drawn card}]
  - Deck cards: 4 (location_type='deck')
  - Current turn: GameSession.current_turn_player_id → P2
```

📖 **Reference**: See feature 003 (`draw_card_from_deck/2`) for existing implementation

---

### Deck Recycling Flow

**Integration**: Automatic via existing `CardGames.recycle_played_stack/1` from feature 004

```text
Initial State:
  - Player hand (via DeckCard): [7C, 9S]
  - Played stack (via DeckCard): [..., 4H, 5D, 6C]  (20+ cards with location_type='played_stack')
  - Deck cards: 0 (location_type='deck')
  - Current turn: GameSession.current_turn_player_id → P1

Precondition: Player needs to draw but deck is empty

Action: Recycle and draw (automatic via draw_card_from_deck/2)

State Update (handled by existing recycle_played_stack/1 then draw):
  1. Detect deck empty in draw_card_from_deck/2
  2. Call recycle_played_stack/1:
     a. Get all played_stack DeckCards except topmost (highest order_index = 6C)
     b. Shuffle recycled cards (Enum.shuffle)
     c. Assign new order_index values (1..N in shuffled order)
     d. Update DeckCards: location_type = "deck", player_id = nil
  3. Retry draw_card_from_deck/2 with recycled deck
  4. Draw card and advance turn (update DeckCard and GameSession.current_turn_player_id)
  5. Single broadcast after complete flow

Final State:
  - Player hand (via DeckCard): [7C, 9S, {drawn card}]
  - Played stack (via DeckCard): [6C]  (topmost card remains)
  - Deck cards: 19 (location_type='deck')
  - Current turn: GameSession.current_turn_player_id → P2
```

**Important**: Feature 005 does NOT reimplement draw or recycle logic - it integrates with existing features 003 and 004.

📖 **Reference**: See feature 004 (`recycle_played_stack/1`) for existing implementation

---

## Indexes and Performance

### Required Indexes

```sql
-- GameSession lookups
CREATE INDEX idx_game_sessions_status ON game_sessions(status);
CREATE INDEX idx_game_sessions_top_card ON game_sessions(top_card_id);

-- GameSessionPlayer lookups  
CREATE INDEX idx_game_session_players_game_id 
  ON game_session_players(game_session_id);
  
CREATE INDEX idx_game_session_players_inserted_at 
  ON game_session_players(game_session_id, inserted_at);

-- DeckCard location and ordering
CREATE INDEX idx_deck_cards_location 
  ON deck_cards(deck_id, location_type, order_index);
  
CREATE INDEX idx_deck_cards_player_hand
  ON deck_cards(deck_id, location_type, player_id) 
  WHERE location_type = 'player_hand';
```

**Note**: Turn order determined by `game_session_players.inserted_at` (join order), not a separate `turn_order` field

📖 **Reference**: See `docs/database-relationships.md` for index performance considerations

### Query Optimization

**Preload Strategy** (avoid N+1):
```elixir
game_session
|> Repo.preload([
  :top_card,
  :current_turn_player,
  game_session_players: :player,
  deck: [deck_cards: :card]
])
```

**Get Player Hand** (efficient query):
```elixir
def get_player_hand(deck_id, player_id) do
  from(dc in DeckCard,
    where: dc.deck_id == ^deck_id and 
           dc.location_type == "player_hand" and
           dc.player_id == ^player_id,
    preload: :card
  )
  |> Repo.all()
end
```

**Get Top Card** (efficient query):
```elixir
def get_top_played_card(deck_id) do
  from(dc in DeckCard,
    where: dc.deck_id == ^deck_id and 
           dc.location_type == "played_stack",
    order_by: [desc: dc.order_index],
    limit: 1,
    preload: :card
  )
  |> Repo.one()
end
```

**Batch Operations**:
```elixir
# Use Ecto.Multi for atomic updates
Multi.new()
|> Multi.update(:game_session, game_changeset)
|> Multi.update(:move_card_1, deck_card_changeset_1)
|> Multi.update(:move_card_2, deck_card_changeset_2)
|> Repo.transaction()
```

📖 **Reference**: See Constitution section 4.1 for database performance requirements

---

## Data Integrity Constraints

### Invariants

1. **Deck Conservation**: 
   ```
   count(location_type='player_hand') + 
   count(location_type='played_stack') + 
   count(location_type='deck') = 52
   ```

2. **Turn Player Exists**: 
   ```
   current_turn_player_id IN (SELECT player_id FROM game_session_players WHERE game_session_id = ?)
   ```

3. **Top Card Consistency**:
   ```
   top_card_id = (SELECT card_id FROM deck_cards 
                  WHERE location_type='played_stack' 
                  ORDER BY order_index DESC LIMIT 1)
   ```

4. **Hand Validity**:
   ```
   All deck_cards with location_type='player_hand' must have valid player_id
   ```

5. **Order Index Uniqueness**:
   ```
   Within same deck and location_type, order_index values must be unique
   ```

### Enforcement

- **Application level**: Validation in context functions and PlayValidator
- **Database level**: Foreign key constraints, unique constraints on (deck_id, location_type, order_index)
- **Transaction level**: Ecto.Multi ensures atomicity

📖 **Reference**: See `spec.md` for functional requirements that enforce these invariants

---

## Summary

**Entities Modified**: GameSession (add top_card_id field only)  
**Entities Used**: GameSession, GameSessionPlayer, DeckCard, Card, Deck (all existing)
**New Modules**: PlayValidator (logic only, no schema)  
**Migrations Required**: 1 (add top_card_id to game_sessions)

**Key Schema Facts**:
- ✅ Played stack tracked via DeckCard.location_type='played_stack'
- ✅ Player hands tracked via DeckCard.location_type='player_hand'  
- ✅ Turn order tracked via GameSessionPlayer.inserted_at (join order)
- ✅ Current turn tracked via GameSession.current_turn_player_id (UUID)
- ✅ NO played_stack array needed
- ✅ NO turn_order field needed
- ✅ NO hand array needed

**Ready for**: Contract definition and quickstart guide.

📖 **References**:
- `docs/database-relationships.md` - Schema relationships and ordering
- `spec.md` - Functional requirements
- `research.md` - Technical decisions
