# Quickstart Guide: Deal Start Card (Final Revision)

**Status**: Ready for Implementation

This guide provides a developer with the correct implementation steps based on the project's established architecture. **No database migrations are needed.**

### Step 1: Review the Data Model

-   Familiarize yourself with the key schemas: `GameSession`, `Deck`, `Card`, and especially `DeckCard`.
-   Note that all card location logic is handled by the `location_type` field on the `deck_cards` table (e.g., `"deck"`, `"player_hand"`, `"played_stack"`).

### Step 2: Implement the Core Game Logic in `Kadi.CardGames`

1.  Navigate to the `Kadi.CardGames` context (`lib/kadi/card_games.ex`).
2.  Modify the `start_game/1` function.
3.  **The logic should be as follows**:
    -   Preload the `GameSession` with its `deck` and the deck's `deck_cards` (which should also have their `card` preloaded).
    -   **Deal Cards**: For each player, take a number of `DeckCard` records from the list of available cards (where `location_type` is `"deck"`) and update their `location_type` to `"player_hand"` (and associate them with the player).
    -   **Find Starting Card**:
        a. Gather the remaining `DeckCard`s still in the `"deck"`.
        b. Shuffle this list of structs using `Enum.shuffle()`.
        c. In a loop or recursive function, take the first `DeckCard` from the shuffled list.
        d. Check its associated `card.rank`.
        e. If it's a special card, repeat the loop (drawing the next card from the shuffled list).
        f. If it's a valid card, update its `location_type` to `"played_stack"` and set its `order_index` to 1.
    -   **Persist Changes**:
        a. Gather all the `Ecto.Changeset`s for the updated `DeckCard`s.
        b. Create a changeset to update the `GameSession`'s `status` to `"live"`.
        c. Use `Ecto.Multi` to run all these updates in a single database transaction.
    -   **Broadcast**: After the transaction succeeds, broadcast the updated `game_session` to all players via PubSub.

### Step 3: Update the Frontend (`GameLive`)

1.  In `lib/kadi_web/live/game_live.ex`, update the logic that populates assigns.
2.  `@player_hand` should be derived by filtering the preloaded `deck_cards` for the current player.
3.  `@played_pile` is the list of cards from `deck_cards` where `location_type` is `"played_stack"`.
4.  `@deck_size` is the count of `deck_cards` where `location_type` is `"deck"`.
5.  The `handle_info/2` for `"game_updated"` should correctly reload and re-filter this data.

### Step 4: Run Tests

-   Run `mix test`. Add new tests specifically for the `start_game/1` logic, ensuring `location_type` fields are updated correctly and that a valid start card is always chosen.
