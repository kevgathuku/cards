# Research & Decisions: Deal Start Card (Final Revision)

**Status**: Completed

This document confirms the implementation approach based on the project architecture outlined in `GEMINI.md`.

## 1. How to store and track card locations?

-   **Context**: The feature requires tracking cards in the deck, in player hands, and in a played pile.
-   **Decision**: The existing architecture, which uses a `deck_cards` join table with a `location_type` field, is the correct and required approach.
-   **Rationale**: `GEMINI.md` makes it clear that the system is designed to track card locations (`deck`, `player_hand`, `played_stack`) via the `location_type` field on the `DeckCard` model. This avoids database migrations and adheres to the established architecture. All game logic will be built around updating this field.

## 2. How to handle shuffling?

-   **Decision**: The `Enum.shuffle/1` function remains the correct tool for this.
-   **Rationale**: The implementation will fetch all `DeckCard` records with a `location_type` of `"deck"`, shuffle this list of structs, and then process them. This is the idiomatic Elixir approach.
