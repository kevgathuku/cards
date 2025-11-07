# LiveView Event Contracts

**Feature**: Basic Gameplay - Regular Cards (4,5,6,7,9,10 Only)  
**Date**: 2025-11-06  
**Protocol**: Phoenix LiveView Events

## Overview

This document defines the event contracts between the LiveView frontend and backend for gameplay actions. All events use Phoenix LiveView's event handling mechanism with server-side validation.

**⚠️ Phase 1 Restriction**: Only regular cards (4, 5, 6, 7, 9, 10) can be played. Special cards (2, 3, 8, Jack, Queen, King, Ace) will be rejected with an `INVALID_PLAY` error.

## Card Notation Protocol

**Format**: JSON array of strings (even for single card)
- Single card: `["4H"]`
- Combo: `["4H", "4D", "4S"]`
- Case-insensitive: "4h" = "4H"
- **Rank notation (Phase 1)**: "4", "5", "6", "7", "9", "10" (regular cards only)
- **Blocked ranks**: "2", "3", "8", "jack", "queen", "king", "ace" (special cards - future features)
- Suit notation: "H" (hearts), "D" (diamonds), "C" (clubs), "S" (spades)

📖 **Reference**: See `spec.md` clarification #1 for complete notation details

---

## Event: `select_card`

**Purpose**: Toggle card selection in player's hand

**Trigger**: User clicks/taps a card in their hand

**Payload**:
```elixir
%{
  "card_notation" => "4H"  # Card notation (e.g., "4H", "5D", "10C")
}
```

**Handler**: `handle_event("select_card", payload, socket)`

**Validation**:
- Card notation is valid format (number + suit letter)
- Card exists in player's hand
- Card notation is parsed case-insensitively

**Response**:
```elixir
{:noreply, assign(socket, :selected_cards, updated_selection)}
```

**State Changes**:
- If card not selected: Add to `selected_cards` list
- If card already selected: Remove from `selected_cards` list
- No server-side state change (local socket only)
- Selection cleared automatically when turn changes to another player

**Error Handling**:
- Invalid card notation: Display error "INVALID_CARD_NOTATION: '{notation}' is not a valid card"
- Card not in hand: Display flash error "CARD_NOT_IN_HAND: You don't have that card"

---

## Event: `play_cards`

**Purpose**: Submit selected cards as a play

**Trigger**: User clicks "Play Cards" button

**Payload**:
```elixir
%{
  "cards" => ["4H", "4D"]  # JSON array of card notation strings
}
```

**Handler**: `handle_event("play_cards", payload, socket)`

**Validation** (Server-Side):

📖 **Implementation**: See `quickstart.md` Phase 1 for PlayValidator module

1. Card notation format is valid (e.g., "4H", "5D", "10C")
2. **Cards are regular cards only (4,5,6,7,9,10)** - special cards blocked
3. Player is current player (turn validation via GameSession.current_turn_player_id)
4. Player has all specified cards in hand
5. Cards meet play validation rules (PlayValidator)
   - Single card: Matches suit OR rank of top card AND is a regular card
   - Multiple cards: All same rank AND first card must match top card AND all are regular cards

**Success Response**:
```elixir
{:noreply, 
  socket
  |> put_flash(:info, "Cards played successfully")
  |> assign(:selected_cards, [])
  |> assign(:game, updated_game)
}

# Broadcast to all players
Phoenix.PubSub.broadcast(
  Kadi.PubSub,
  "game:#{game_id}",
  {:game_updated, updated_game}
)
```

**Error Response with Specific Codes**:
```elixir
# Not player's turn
{:noreply,
  socket
  |> put_flash(:error, "NOT_YOUR_TURN: Please wait for your turn")
}

# Invalid card notation
{:noreply,
  socket
  |> put_flash(:error, "INVALID_CARD_NOTATION: '4X' is not a valid card")
}

# Special cards blocked (Phase 1)
{:noreply,
  socket
  |> put_flash(:error, "INVALID_PLAY: Special cards not allowed (only 4,5,6,7,9,10 in this version)")
  |> assign(:selected_cards, [])  # Clear selection
}

# Cards don't match
{:noreply,
  socket
  |> put_flash(:error, "WRONG_SUIT: The card doesn't match the suit or number")
  |> assign(:selected_cards, [])  # Clear selection
}

# Mixed numbers in combo
{:noreply,
  socket
  |> put_flash(:error, "MIXED_NUMBERS: All cards in a combo must have the same number")
  |> assign(:selected_cards, [])
}

# Cards not in hand
{:noreply,
  socket
  |> put_flash(:error, "CARDS_NOT_IN_HAND: You don't have those cards")
  |> assign(:selected_cards, [])
}
```

**State Changes** (on success):
- Remove cards from player's hand
- Add cards to played stack (in order)
- Update top_card_id
- Advance current_turn
- Clear selected_cards
- Broadcast update to all players

**Performance Target**: <100ms from event to broadcast

---

## Event: `draw_card`

**Purpose**: Draw a card from the deck (reuses existing `CardGames.draw_card_from_deck/2` from feature 003)

**Trigger**: User clicks "Draw Card" button

**Payload**:
```elixir
%{}  # No payload needed
```

**Handler**: `handle_event("draw_card", _payload, socket)`

**Preconditions**:
1. Player is current player
2. Button visible only when it's player's turn (UI safeguard)

**Success Response**:
```elixir
{:noreply,
  socket
  |> put_flash(:info, "Card drawn")
  |> assign(:game, updated_game)
}

# Broadcast
Phoenix.PubSub.broadcast(
  Kadi.PubSub,
  "game:#{game_id}",
  {:game_updated, updated_game}
)
```

**Error Response**:
```elixir
# Not player's turn
{:noreply,
  socket
  |> put_flash(:error, "NOT_YOUR_TURN: Please wait for your turn")
}

# Edge case: deck empty triggers recycling (automatic via feature 004)
# No error shown to user - handled transparently
```

**State Changes** (on success):
- Remove top card from deck
- Add card to player's hand
- Advance current_turn
- If deck empty: Automatic recycle via `recycle_played_stack/1` (feature 004)
- Broadcast update to all players

**Special Case: Deck Recycling** (handled by existing feature 004)
```elixir
# Automatic when deck is empty - NO reimplementation needed
# Uses existing CardGames.recycle_played_stack/1
1. Get all played_stack except top card
2. Shuffle cards (Enum.shuffle)
3. Replace deck with shuffled cards
4. Set played_stack = [top_card]
5. Draw from new deck
```

**Performance Target**: <100ms including shuffle operation

---

## Event: `deselect_all`

**Purpose**: Clear all selected cards

**Trigger**: User clicks "Clear Selection" or cancels

**Payload**:
```elixir
%{}  # No payload needed
```

**Handler**: `handle_event("deselect_all", _payload, socket)`

**Response**:
```elixir
{:noreply, assign(socket, :selected_cards, [])}
```

**State Changes**:
- Clear selected_cards list (local socket only)
- No server or game state changes

---

## PubSub Messages

### Message: `{:game_updated, game_state}`

**Purpose**: Notify all players of game state change

**Publisher**: CardGames context functions after successful mutation

**Topic**: `"game:#{game_session_id}"`

**Payload**:
```elixir
{:game_updated, %GameSession{
  id: "...",
  current_turn: 2,
  played_stack: ["card-id-1", "card-id-2", "card-id-3"],
  top_card_id: "card-id-3",
  game_session_players: [
    %{player_id: "...", hand: [...], turn_order: 0},
    %{player_id: "...", hand: [...], turn_order: 1},
    # ...
  ],
  deck: %{cards: [...]}
}}
```

**Subscribers**: All LiveView processes for players in the game

**Handler**: `handle_info({:game_updated, game_state}, socket)`

**Response**:
```elixir
{:noreply, assign(socket, :game, game_state)}
```

**Rendering**: Automatic via LiveView assigns update

---

## Error Codes and Messages

### Validation Errors

| Code | Message | User-Facing Message |
|------|---------|---------------------|
| `:not_your_turn` | Player attempted action out of turn | "NOT_YOUR_TURN: Please wait for your turn" |
| `:wrong_suit` | No card matches suit or number | "WRONG_SUIT: The card doesn't match the suit or number" |
| `:mixed_numbers` | Combo has different numbers | "MIXED_NUMBERS: All cards in a combo must have the same number" |
| `:no_match` | First card in combo doesn't match top card | "NO_MATCH: The first card must match the top card" |
| `:cards_not_in_hand` | Player doesn't have specified cards | "CARDS_NOT_IN_HAND: You don't have those cards" |
| `:invalid_card_notation` | Malformed card notation format | "INVALID_CARD_NOTATION: '{notation}' is not a valid card" |
| `:deck_empty` | Deck is empty and cannot recycle | "DECK_EMPTY: Cannot draw, deck is empty" |

---

## Request/Response Flow Diagrams

### Play Card Flow

```text
Client                    LiveView               Context              PubSub
  |                          |                      |                    |
  |--- select_card --------->|                      |                    |
  |<-- updated UI -----------|                      |                    |
  |                          |                      |                    |
  |--- play_cards ---------->|                      |                    |
  |                          |--- play_cards ------>|                    |
  |                          |                      |--- validate        |
  |                          |                      |--- Ecto.Multi     |
  |                          |<-- {:ok, game} ------|                    |
  |                          |                      |                    |
  |<-- flash + updated UI ---|                      |                    |
  |                          |--- broadcast ----------------------->|    |
  |                          |                      |                    |
  |<======= game_updated ====================================|<----------|
Other Players                                                |
  |<======= game_updated ====================================|
```

### Draw Card Flow

```text
Client                    LiveView               Context              PubSub
  |                          |                      |                    |
  |--- draw_card ----------->|                      |                    |
  |                          |--- draw_card ------->|                    |
  |                          |                      |--- check deck      |
  |                          |                      |--- recycle if empty|
  |                          |                      |--- draw + turn     |
  |                          |<-- {:ok, game} ------|                    |
  |                          |                      |                    |
  |<-- flash + updated UI ---|                      |                    |
  |                          |--- broadcast ----------------------->|    |
  |                          |                      |                    |
  |<======= game_updated ====================================|<----------|
Other Players                                                |
  |<======= game_updated ====================================|
```

---

## WebSocket Frame Examples

### Play Cards Event (Client → Server)

```json
[
  "4",
  "phx_join",
  "lv:phx-...",
  "event",
  {
    "type": "click",
    "event": "play_cards",
    "value": {
      "card_ids": [
        "550e8400-e29b-41d4-a716-446655440000",
        "550e8400-e29b-41d4-a716-446655440001"
      ]
    }
  }
]
```

### Game Updated Broadcast (Server → All Clients)

```json
[
  null,
  null,
  "lv:phx-...",
  "diff",
  {
    "0": {
      "s": [
        "<div>...</div>"
      ]
    }
  }
]
```

Note: LiveView sends HTML diffs, not raw JSON. The actual payload is a DOM patch.

---

## Rate Limiting

**Not Required for MVP**: Turn-based gameplay naturally rate-limits actions

**Future Consideration**: 
- Prevent spam clicking: Debounce client-side
- Detect rapid invalid plays: Flag suspicious behavior

---

## Security Considerations

### Input Validation
- ✅ All card IDs validated against player's hand
- ✅ Turn validation prevents out-of-turn plays
- ✅ Server-side validation; client cannot bypass

### State Integrity
- ✅ Ecto.Multi ensures atomic updates
- ✅ Optimistic locking prevents race conditions
- ✅ PubSub broadcasts immutable game state

### Privacy
- ✅ Players only see their own hand in full
- ✅ Other players' hands show count only
- ✅ Deck contents hidden until drawn

---

## Testing Contract Compliance

### Unit Tests (PlayValidator)
```elixir
test "valid single card play - suit match" do
  assert PlayValidator.valid_play?(["4H"], top_card: %{suit: "H", rank: "5"})
end

test "invalid play - no match" do
  refute PlayValidator.valid_play?(["4H"], top_card: %{suit: "C", rank: "5"})
end
```

### Integration Tests (LiveView)
```elixir
test "play cards updates game state", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")
  
  # Select cards
  view |> element("#card-4H") |> render_click()
  view |> element("#card-4D") |> render_click()
  
  # Play
  view |> element("#play-button") |> render_click()
  
  # Assert
  assert has_element?(view, "#flash-info", "Cards played successfully")
  refute has_element?(view, "#card-4H")
end
```

---

## Summary

**Total Events**: 4 (select_card, play_cards, draw_card, deselect_all)  
**PubSub Topics**: 1 per game (`game:#{id}`)  
**Error Types**: 6 validation errors  
**Performance Target**: <100ms event → broadcast  

**Protocol**: Phoenix LiveView native event handling (no custom API)  
**Serialization**: Elixir terms over WebSocket (LiveView handles encoding)

**Ready for**: Quickstart guide and implementation.
