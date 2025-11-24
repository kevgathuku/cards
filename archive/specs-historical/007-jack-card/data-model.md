# Data Model: Jack Card Implementation

**Feature**: 007-jack-card  
**Date**: 2025-11-08  
**Status**: Complete

## Overview

This document describes the data model for Jack card implementation. **No schema changes or migrations are required** - all necessary database structures already exist from previous features.

## Existing Schemas (No Changes)

### GameSession
**Schema**: `lib/kadi/games/game_session.ex`  
**Table**: `game_sessions`

```elixir
schema "game_sessions" do
  field :short_code, :string
  field :status, :string, default: "lobby"          # "lobby" | "live"
  field :direction, :string, default: "clockwise"   # Used by Jack skip calculation
  belongs_to :created_by, Kadi.Accounts.Player
  belongs_to :current_turn_player, Kadi.Accounts.Player  # Updated after Jack skip
  belongs_to :top_card, Kadi.Games.Card             # Updated to Jack after play
  has_one :deck, Kadi.Games.Deck
  has_many :game_session_players, Kadi.Games.GameSessionPlayer
  many_to_many :players, Kadi.Accounts.Player, join_through: "game_session_players"
  
  timestamps(type: :utc_datetime)
end
```

**Jack Usage**:
- `direction`: Jack skip respects this value (clockwise/counter_clockwise)
- `current_turn_player_id`: Updated to player N positions away after Jack skip
- `top_card_id`: Updated to the last Jack played

**Validation Rules**:
- `status` in ["lobby", "live"]
- `direction` in ["clockwise", "counter_clockwise"]

---

### GameSessionPlayer
**Schema**: `lib/kadi/games/game_session_player.ex`  
**Table**: `game_session_players`

```elixir
schema "game_session_players" do
  belongs_to :game_session, Kadi.Games.GameSession
  belongs_to :player, Kadi.Accounts.Player
  field :status, :string, default: "normal"  # "normal" | "cardless"
  
  timestamps(type: :utc_datetime)
end
```

**Jack Usage**:
- `status`: Set to "cardless" when Jack is played as last card (FR-012)
- Player remains cardless until their turn arrives, then auto-draws one card

**Validation Rules**:
- `status` in ["normal", "cardless"]
- `unique_constraint([:game_session_id, :player_id])`

---

### Card
**Schema**: `lib/kadi/games/card.ex`  
**Table**: `cards`

```elixir
schema "cards" do
  field :suit, :string     # "hearts" | "diamonds" | "clubs" | "spades"
  field :rank, :string     # "jack" for Jack cards
  
  timestamps(type: :utc_datetime)
end
```

**Jack Cards in Database** (seeded via `priv/repo/seeds.exs`):
- Jack of hearts (id varies)
- Jack of diamonds (id varies)
- Jack of clubs (id varies)
- Jack of spades (id varies)

**Query Pattern**:
```elixir
# Find all Jacks in a player's hand:
deck_cards
|> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == player_id))
|> Enum.map(& &1.card)
|> Enum.filter(&(&1.rank == "jack"))
```

---

### DeckCard
**Schema**: `lib/kadi/games/deck_card.ex`  
**Table**: `deck_cards`

```elixir
schema "deck_cards" do
  belongs_to :deck, Kadi.Games.Deck
  belongs_to :card, Kadi.Games.Card
  belongs_to :player, Kadi.Accounts.Player
  field :location_type, :string    # "deck" | "player_hand" | "played_stack"
  field :order_index, :integer
  
  timestamps(type: :utc_datetime)
end
```

**Jack Usage**:
- Track Jack cards as they move: `deck` → `player_hand` → `played_stack`
- When Jack played: `location_type` changes to "played_stack", `order_index` set
- `player_id` cleared when moved to played_stack

---

## Data Flow

### 1. Jack Card Play Flow

```
[Player Hand] ---play_cards/3---> [Validation] ---pass---> [Execute Play]
     |                                  |
     | Jack(s) + matching cards         | valid_jack_play?/2
     |                                  v
     |                            [Detection Phase]
     |                                  |
     |                         jack_played? = true
     |                         skip_count = length(jacks)
     |                                  v
     |                            [Ecto.Multi Transaction]
     |                                  |
     |                            1. Move cards to played_stack
     |                            2. Calculate next player (skip N)
     |                            3. Update game_session.current_turn_player_id
     |                            4. Update game_session.top_card_id
     |                            5. If last cards → status = "cardless"
     |                                  v
     |                            [Broadcast Update]
     |                                  |
     |                            [:kadi, :jack, :skip_executed]
     |                            [:kadi, :jack, :cardless_entered] (if applicable)
```

### 2. Skip Calculation

```elixir
# Input:
players = [P1, P2, P3, P4]  # Ordered by inserted_at
current_player_id = P2.id
skip_count = 2              # 2 Jacks played
direction = "clockwise"

# Process:
current_index = 1           # P2 is at index 1
offset = +2                 # Clockwise, skip 2
new_index = rem(1 + 2, 4)   # = 3
next_player = P4            # Index 3

# Result:
game_session.current_turn_player_id = P4.id
```

### 3. Cardless State Transition

```elixir
# Condition:
player_hand_count = 2       # Player has 2 cards
cards_played = [Jack♥, Jack♦]  # Playing 2 Jacks
jack_played? = true

will_be_cardless = (2 == 2) and true  # → true

# Action:
GameSessionPlayer
|> where(game_session_id: ^game_id, player_id: ^player_id)
|> update(set: [status: "cardless"])

# When turn returns:
if player.status == "cardless" do
  draw_card_from_deck(game_session, player_id)  # Draws 1 card
  update_status(player, "normal")
end
```

---

## Validation Rules

### Jack Play Validation

**Rule 1: All cards must be Jacks** (FR-003)
```elixir
all_jacks? = Enum.all?(cards_to_play, &(&1.rank == "jack"))
```

**Rule 2: First Jack must match top card** (FR-001, FR-009)
```elixir
first_jack = List.first(cards_to_play)
matches? = first_jack.suit == top_card.suit or first_jack.rank == top_card.rank
```

**Rule 3: Cards must be in player's hand** (existing from play_cards/3)
```elixir
player_card_ids = get_player_hand(game_session, player_id) |> Enum.map(& &1.id)
all_in_hand? = Enum.all?(card_ids, &(&1 in player_card_ids))
```

**Rule 4: Must be player's turn** (existing from play_cards/3)
```elixir
is_current_turn? = game_session.current_turn_player_id == player_id
```

---

## State Transitions

### Player Status

```
normal --[play Jack(s) as last card]--> cardless
cardless --[turn arrives, auto-draw]--> normal
```

### Card Location

```
deck --[deal_cards]--> player_hand
player_hand --[play_cards with Jack]--> played_stack
played_stack --[recycle_played_stack]--> deck
```

### Turn Order (3-player example)

```
# Normal play:
P1 → P2 → P3 → P1 → ...

# P1 plays 1 Jack:
P1 → [skip P2] → P3 → P1 → P2 → ...

# P1 plays 2 Jacks:
P1 → [skip P2, P3] → P1 → P2 → P3 → ...

# With counter_clockwise:
P1 → [skip P3] → P2 → P1 → P3 → ...
```

---

## Indexes (Existing)

**No new indexes required.** Existing indexes support Jack queries:

```sql
-- game_sessions
CREATE INDEX game_sessions_status_index ON game_sessions(status);
CREATE INDEX game_sessions_current_turn_player_id_index ON game_sessions(current_turn_player_id);

-- game_session_players  
CREATE UNIQUE INDEX game_session_players_game_session_id_player_id_index 
  ON game_session_players(game_session_id, player_id);

-- deck_cards
CREATE INDEX deck_cards_deck_id_index ON deck_cards(deck_id);
CREATE INDEX deck_cards_player_id_index ON deck_cards(player_id);
CREATE INDEX deck_cards_location_type_index ON deck_cards(location_type);
```

---

## Relationships

### Cascade Behavior (No Changes)

**From docs/database-relationships.md:**

```
game_session (on_delete: :delete_all)
  └─> game_session_players (on_delete: :delete_all)
  └─> deck (on_delete: :delete_all)
       └─> deck_cards (on_delete: :delete_all)

cards (on_delete: :restrict)  # Shared resource, never deleted
players (on_delete: :restrict)  # Protected from deletion
```

Jack implementation respects these constraints - no special cascade handling needed.

---

## Data Integrity Constraints

### Existing Constraints (Enforced)

1. **Turn player must be in game**:
   ```elixir
   assoc_constraint(:current_turn_player)
   ```

2. **Top card must exist**:
   ```elixir
   assoc_constraint(:top_card)
   ```

3. **Player status values**:
   ```elixir
   validate_inclusion(:status, ["normal", "cardless"])
   ```

4. **Direction values**:
   ```elixir
   validate_inclusion(:direction, ["clockwise", "counter_clockwise"])
   ```

### Application-Level Constraints (Jack-specific)

1. **Skip count must be positive**: `skip_count = max(1, length(jacks))`
2. **Cardless player can only draw 1 card**: Enforced in `draw_card_from_deck/2`
3. **Starting Jack has no skip effect**: Checked in `start_game/1`

---

## Summary

**Schema Changes**: None  
**Migrations Required**: None  
**New Tables**: None  
**Modified Tables**: None

**Reused Infrastructure**:
- ✅ GameSession (direction, current_turn_player_id)
- ✅ GameSessionPlayer (status field for cardless)
- ✅ Card (52 cards including 4 Jacks already seeded)
- ✅ DeckCard (location tracking for card movement)

**Implementation Impact**: Pure logic changes in `CardGames` context and `PlayValidator` module. Zero database changes required.
