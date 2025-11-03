# Data Model: Deal Start Card (Final Revision)

**Status**: Completed

This document has been completely revised based on the architecture described in `GEMINI.md`. No database schema changes are required for this feature.

## 1. Existing Data Architecture

The implementation will use the existing database schema without modification.

-   **`game_sessions`**: Contains the core game data, including the `status` field (`"lobby"`, `"live"`).

-   **`decks`**: Each `GameSession` has one `Deck`.

-   **`cards`**: A central table holding the 52 unique card definitions (`%Kadi.Games.Card{}`).

-   **`deck_cards`**: This is the key table for this feature. It joins a `Deck` to `Cards` and, crucially, tracks the location of every card in a game session.

## 2. The `deck_cards.location_type` Field

This field is central to the feature's implementation. It tracks where a card is at any given time.

-   **Data Type**: `string`
-   **Possible Values**:
    -   `"deck"`: The card is in the draw pile.
    -   `"player_hand"`: The card is in a player's hand (will also require a `player_id` foreign key on the `deck_cards` table).
    -   `"played_stack"`: The card is in the pile of played cards.

-   **`order_index`**: For cards in the `played_stack`, this integer field will be used to maintain the order of play. The highest `order_index` represents the top card of the pile.

## 3. Implementation Strategy

Instead of adding new columns, the implementation will consist of updating the `location_type` field on `deck_cards` records.

-   **Dealing Cards**: A set of `deck_cards` records will have their `location_type` changed from `"deck"` to `"player_hand"`.
-   **Drawing the Start Card**: One `deck_card` record will be selected from the remaining cards in the `"deck"` and its `location_type` will be changed to `"played_stack"`.
