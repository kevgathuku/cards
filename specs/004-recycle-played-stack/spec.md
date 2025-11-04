# Feature Specification: Recycle Played Stack into Deck

**Feature Branch**: `004-recycle-played-stack`  
**Created**: 2025-11-04
**Status**: Stub (To Be Implemented Later)  
**Dependency**: Requires feature 003-pick-card-from-deck to be completed first

## Quick Summary

When the deck is empty and a player tries to draw a card, rebuild the deck by taking all cards from the played stack (excluding the topmost card which stays visible), shuffling them, and assigning new randomized `order_index` values.

## User Story

As a player, when the deck runs out of cards and I try to draw, I want the played cards to be automatically recycled into a new deck so that the game can continue without interruption.

## Key Requirements (Draft)

- **Take all played stack cards** except the topmost/last played card
- **Shuffle** the cards (randomize order)
- **Assign new `order_index`** values (similar to initial deck creation)
- **Move cards** from `location_type = 'played_stack'` to `location_type = 'deck'`
- **Keep topmost card** visible on played pile as reference
- **Atomic operation** using database transaction
- **Broadcast** deck rebuild to all players

## Technical Notes

- Reuse shuffle logic from `create_game_session` (lines 105-110 in card_games.ex)
- Identify "topmost" card by highest `order_index` in played_stack
- May need to track played_stack order separately from deck order_index
- Consider: What if played stack only has 1 card? Cannot recycle (need min 2 cards)

## Dependencies

- Feature 003 must be complete (draw card functionality)
- May need played_stack ordering mechanism
- UI should show feedback when deck is rebuilt

## Related Questions to Address Later

1. What visual feedback should players see when deck is rebuilt?
2. Should there be a minimum number of cards in played stack to recycle?
3. How to handle edge case: only 1 card in played stack?
4. Should shuffle algorithm be cryptographically secure or just pseudo-random?

---

**Status**: This feature will be planned and implemented after feature 003 is complete.
