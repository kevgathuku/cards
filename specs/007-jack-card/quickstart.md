# Quick Start: Jack Card Implementation

**Feature**: 007-jack-card  
**Date**: 2025-11-08  
**Estimated Time**: 4-6 hours

## Prerequisites

- Elixir 1.14+ and OTP 25+ installed
- Phoenix 1.7 development environment set up
- PostgreSQL running (database: `kadi_dev`)
- All tests passing on main branch: `mix test`
- Familiarity with Feature 006 (King card) implementation

## Development Workflow

### Phase 1: Validation Layer (1-1.5 hours)

**Goal**: Add Jack validation to PlayValidator module

**Files to modify**:
- `lib/kadi/games/play_validator.ex`
- `test/kadi/games/play_validator_test.exs`

**Steps**:

1. **Add Jack validation function** (30 min)
   ```bash
   # Open PlayValidator
   code lib/kadi/games/play_validator.ex
   ```
   
   Add after `valid_king_play?/2`:
   ```elixir
   @doc """
   Validates if a Jack card play is valid.
   
   Rules:
   - Single Jack: Must match suit OR rank of top card
   - Multiple Jacks: All cards must be Jacks, first must match top card
   - Jack combos are allowed (unlike King)
   
   ## Examples
   
       iex> top_card = %Card{suit: "hearts", rank: "5"}
       iex> jack = %Card{suit: "hearts", rank: "jack"}
       iex> PlayValidator.valid_jack_play?([jack], top_card)
       true
   """
   def valid_jack_play?([], _top_card), do: false
   def valid_jack_play?(_cards, nil), do: false
   
   def valid_jack_play?(cards, top_card) when is_list(cards) do
     all_jacks?(cards) and first_card_matches?(cards, top_card)
   end
   
   defp all_jacks?(cards) do
     Enum.all?(cards, &(&1.rank == "jack"))
   end
   ```

2. **Update main validation entry point** (15 min)
   
   In `valid_play?/2`, add Jack handling:
   ```elixir
   def valid_play?(cards, top_card) when is_list(cards) do
     cond do
       Enum.any?(cards, &(&1.rank == "king")) ->
         valid_king_play?(cards, top_card)
       
       Enum.any?(cards, &(&1.rank == "jack")) ->
         valid_jack_play?(cards, top_card)
       
       all_regular_cards?(cards) ->
         validate_combo(cards, top_card)
       
       true ->
         false
     end
   end
   ```

3. **Write validation tests** (45 min)
   ```bash
   code test/kadi/games/play_validator_test.exs
   ```
   
   Add test suite:
   ```elixir
   describe "valid_jack_play?/2" do
     test "accepts single Jack matching by suit" do
       top_card = %Card{suit: "hearts", rank: "5"}
       jack = %Card{suit: "hearts", rank: "jack"}
       assert PlayValidator.valid_jack_play?([jack], top_card)
     end
     
     test "accepts single Jack matching by rank" do
       top_card = %Card{suit: "diamonds", rank: "jack"}
       jack = %Card{suit: "clubs", rank: "jack"}
       assert PlayValidator.valid_jack_play?([jack], top_card)
     end
     
     test "accepts Jack combo when first matches" do
       top_card = %Card{suit: "hearts", rank: "5"}
       jacks = [
         %Card{suit: "hearts", rank: "jack"},
         %Card{suit: "clubs", rank: "jack"}
       ]
       assert PlayValidator.valid_jack_play?(jacks, top_card)
     end
     
     test "rejects Jack when neither suit nor rank matches" do
       top_card = %Card{suit: "diamonds", rank: "5"}
       jack = %Card{suit: "hearts", rank: "jack"}
       refute PlayValidator.valid_jack_play?([jack], top_card)
     end
     
     test "rejects combo with non-Jack cards" do
       top_card = %Card{suit: "hearts", rank: "jack"}
       cards = [
         %Card{suit: "hearts", rank: "jack"},
         %Card{suit: "hearts", rank: "5"}
       ]
       refute PlayValidator.valid_jack_play?(cards, top_card)
     end
   end
   ```

4. **Verify validation tests pass**
   ```bash
   mix test test/kadi/games/play_validator_test.exs
   ```

---

### Phase 2: Skip Calculation Logic (1.5-2 hours)

**Goal**: Implement skip calculation in CardGames context

**Files to modify**:
- `lib/kadi/card_games.ex`

**Steps**:

1. **Enhance get_next_player_with_direction/3** (45 min)
   
   Find existing function and add optional skip_count parameter:
   ```elixir
   # Current signature:
   defp get_next_player_with_direction(players, current_player_id, direction)
   
   # Enhanced signature:
   defp get_next_player_with_direction(players, current_player_id, direction, skip_count \\ 1)
   ```
   
   Implementation:
   ```elixir
   defp get_next_player_with_direction(players, current_player_id, direction, skip_count \\ 1) do
     current_index = Enum.find_index(players, &(&1.id == current_player_id))
     player_count = length(players)
     
     offset = case direction do
       "clockwise" -> skip_count
       "counter_clockwise" -> -skip_count
     end
     
     # Handle wrap-around (including negative values)
     next_index = rem(current_index + offset + player_count * abs(offset), player_count)
     
     Enum.at(players, next_index)
   end
   ```

2. **Add Jack detection to execute_play/3** (30 min)
   
   Find the King detection section (~line 654) and add Jack logic:
   ```elixir
   # Existing King detection
   king_played? = Enum.any?(cards_to_play, &(&1.rank == "king"))
   
   # Add Jack detection
   jack_played? = Enum.any?(cards_to_play, &(&1.rank == "jack"))
   jack_count = if jack_played?, do: Enum.count(cards_to_play), else: 0
   
   # Calculate skip count (Jack takes precedence over King for turn advancement)
   skip_count = if jack_played?, do: jack_count, else: 1
   ```

3. **Update turn calculation** (15 min)
   
   Modify next player calculation:
   ```elixir
   # Old:
   next_player = get_next_player_with_direction(players, player.id, new_direction)
   
   # New:
   next_player = get_next_player_with_direction(players, player.id, new_direction, skip_count)
   ```

4. **Add cardless detection for Jack** (30 min)
   
   Update will_be_cardless condition:
   ```elixir
   # Old (King only):
   will_be_cardless = player_hand == cards_played_count and king_played?
   
   # New (King OR Jack):
   will_be_cardless = player_hand == cards_played_count and (king_played? or jack_played?)
   ```

---

### Phase 3: Telemetry Events (30-45 min)

**Goal**: Add observability for Jack plays

**Files to modify**:
- `lib/kadi/card_games.ex`

**Steps**:

1. **Add telemetry emission after transaction** (30 min)
   
   Find King telemetry section (~line 734) and add Jack telemetry:
   ```elixir
   # After successful transaction in execute_play/3
   if jack_played? do
     from_player_id = player.id
     to_player_id = next_player.id
     
     :telemetry.execute(
       [:kadi, :jack, :skip_executed],
       %{skip_count: jack_count},
       %{
         game_session_id: game_session.id,
         player_id: from_player_id,
         from_player_id: from_player_id,
         to_player_id: to_player_id,
         jack_count: jack_count,
         card_ids: Enum.map(cards_to_play, & &1.id)
       }
     )
   end
   
   if will_be_cardless and jack_played? do
     :telemetry.execute(
       [:kadi, :jack, :cardless_entered],
       %{},
       %{
         game_session_id: game_session.id,
         player_id: player.id,
         card_id: last_card.id,
         reason: "jack_last_card"
       }
     )
   end
   ```

2. **Add helper function** (15 min)
   ```elixir
   defp emit_jack_skip_event(game_id, from_player_id, to_player_id, skip_count, card_ids) do
     :telemetry.execute(
       [:kadi, :jack, :skip_executed],
       %{skip_count: skip_count},
       %{
         game_session_id: game_id,
         player_id: from_player_id,
         from_player_id: from_player_id,
         to_player_id: to_player_id,
         jack_count: skip_count,
         card_ids: card_ids
       }
     )
   end
   ```

---

### Phase 4: Starting Card Logic (30 min)

**Goal**: Allow Jack as starting card without skip effect

**Files to modify**:
- `lib/kadi/card_games.ex`

**Steps**:

1. **Update start_game/1 comments** (15 min)
   
   Find the start card selection logic (~line 831):
   ```elixir
   # Current comment:
   # Per FR-003: Kings are allowed as start cards (no direction reversal occurs)
   
   # Enhanced comment:
   # Per FR-003 (feature 006): Kings are allowed as start cards (no direction reversal)
   # Per FR-015 (feature 007): Jacks are allowed as start cards (no skip effect)
   # Special effects only trigger when cards are played during gameplay
   ```

2. **Verify start card exclusions** (15 min)
   
   Ensure Jacks are NOT in the excluded list:
   ```elixir
   # Special cards excluded as start cards:
   special_ranks = ["2", "3", "jack", "queen", "ace"]
   
   # Should be (Jack allowed):
   special_ranks = ["2", "3", "queen", "ace"]  # Jack and King allowed
   ```

---

### Phase 5: Integration Tests (1.5-2 hours)

**Goal**: Comprehensive test coverage for Jack gameplay

**Files to modify**:
- `test/kadi/card_games_test.exs`

**Steps**:

1. **Add test setup** (15 min)
   ```elixir
   describe "play_cards/3 with Jack card" do
     setup do
       player1 = player_fixture()
       player2 = player_fixture()
       player3 = player_fixture()
       
       {:ok, game_session} = CardGames.create_game_session(player1, %{short_code: "Jack Test"})
       {:ok, _} = CardGames.join_game_session(player2, game_session.id)
       {:ok, _} = CardGames.join_game_session(player3, game_session.id)
       {:ok, game_session} = CardGames.start_game(game_session)
       
       %{
         game_session: game_session,
         player1: player1,
         player2: player2,
         player3: player3
       }
     end
     
     # Tests follow...
   end
   ```

2. **Write core skip tests** (45 min)
   ```elixir
   test "single Jack skips 1 player in 3-player game", %{game_session: game_session} do
     # Setup: Ensure current player has Jack matching top card
     # Action: Play Jack
     # Assert: Turn advanced 2 positions (skipped 1 player)
   end
   
   test "2 Jacks skip 2 players in 3-player game", %{game_session: game_session} do
     # Setup: Give player 2 Jacks matching top card
     # Action: Play both Jacks
     # Assert: Turn wraps around to same player
   end
   
   test "Jack respects counter_clockwise direction", %{game_session: game_session} do
     # Setup: Play King first to set counter_clockwise
     # Setup: Give player Jack matching top card
     # Action: Play Jack
     # Assert: Turn goes backward (skip in reverse direction)
   end
   ```

3. **Write cardless tests** (30 min)
   ```elixir
   test "playing Jack as last card enters cardless state", %{game_session: game_session} do
     # Setup: Player with only 1 Jack matching top card
     # Action: Play Jack
     # Assert: Player status = "cardless", turn advanced with skip
   end
   
   test "cardless player draws 1 card when turn returns", %{game_session: game_session} do
     # Setup: Player in cardless state from Jack
     # Action: Turn arrives back to cardless player
     # Assert: Auto-draws 1 card, status = "normal"
   end
   ```

4. **Write edge case tests** (30 min)
   ```elixir
   test "2-player game: Jack skips other player, returns to same player" do
     # 2-player setup, play Jack, verify turn returns to player
   end
   
   test "4 Jacks in 3-player game wraps correctly" do
     # Play 4 Jacks, verify wrap-around math (skip 4 positions)
   end
   
   test "Jack allowed as starting card, no skip on game start" do
     # Check start_game with Jack start card, P1 goes first
   end
   ```

5. **Run full test suite** (10 min)
   ```bash
   mix test test/kadi/card_games_test.exs
   ```

---

### Phase 6: Manual Testing (30-45 min)

**Goal**: Verify behavior in live UI

**Steps**:

1. **Start development server**
   ```bash
   mix phx.server
   ```

2. **Test scenario 1: Basic Jack skip** (10 min)
   - Create game with 3 players
   - Get Jack matching top card (may need to manipulate in IEx)
   - Play Jack
   - Verify next player is skipped in UI

3. **Test scenario 2: Jack combo** (10 min)
   - Set up 2 Jacks matching top card
   - Play combo
   - Verify 2 players skipped

4. **Test scenario 3: Cardless from Jack** (10 min)
   - Play Jack as last card
   - Verify cardless indicator appears
   - Wait for turn to return
   - Verify auto-draw happens

5. **Test scenario 4: Jack + King interaction** (15 min)
   - Play King (direction reverses)
   - Play Jack
   - Verify skip goes in correct direction

---

## Verification Checklist

Before considering feature complete:

- [ ] All PlayValidator tests pass
- [ ] All CardGames tests pass  
- [ ] Full test suite passes: `mix test`
- [ ] No compiler warnings: `mix compile --warnings-as-errors`
- [ ] Code formatted: `mix format`
- [ ] Manual UI testing completed for all scenarios
- [ ] Telemetry events visible in logs
- [ ] No regressions in existing card functionality

---

## Common Issues & Solutions

### Issue 1: Skip calculation off by one

**Symptom**: Turn doesn't land on expected player

**Solution**: Check rem/2 handling of negative numbers in counter_clockwise
```elixir
# Wrong:
next_index = rem(current_index + offset, player_count)

# Right (handles negatives):
next_index = rem(current_index + offset + player_count * abs(offset), player_count)
```

### Issue 2: Jack validation failing

**Symptom**: Valid Jack plays rejected

**Solution**: Ensure `all_jacks?/1` and `first_card_matches?/2` helpers are defined

### Issue 3: Cardless not triggering

**Symptom**: Player wins instead of going cardless

**Solution**: Check condition includes `jack_played?`
```elixir
will_be_cardless = player_hand == cards_played_count and (king_played? or jack_played?)
```

### Issue 4: Tests failing with "card not found"

**Symptom**: Test setup doesn't have matching Jack

**Solution**: Manually move Jack to player's hand from deck:
```elixir
jack_card = game_session.deck.deck_cards
  |> Enum.find(&(&1.card.rank == "jack" and &1.card.suit == "hearts"))
  
Kadi.Games.DeckCard.changeset(jack_card, %{
  location_type: "player_hand",
  player_id: player.id,
  order_index: nil
})
|> Repo.update!()
```

---

## Time Estimates

| Phase | Estimated Time | Cumulative |
|-------|---------------|------------|
| Phase 1: Validation | 1-1.5 hours | 1-1.5 hours |
| Phase 2: Skip Logic | 1.5-2 hours | 2.5-3.5 hours |
| Phase 3: Telemetry | 30-45 min | 3-4.25 hours |
| Phase 4: Start Card | 30 min | 3.5-4.75 hours |
| Phase 5: Integration Tests | 1.5-2 hours | 5-6.75 hours |
| Phase 6: Manual Testing | 30-45 min | 5.5-7.5 hours |

**Total: 5.5-7.5 hours** (realistic estimate with breaks and debugging)

---

## Success Criteria

Feature is complete when:

1. ✅ All 16 functional requirements (FR-001 through FR-016) implemented
2. ✅ All 6 success criteria (SC-001 through SC-006) verified
3. ✅ All user stories (1-5) have passing acceptance tests
4. ✅ Edge cases (wrap-around, 2-player, starting card) handled
5. ✅ Telemetry events emitting correctly
6. ✅ No regressions in existing features (King, regular cards)
7. ✅ Code passes constitution checks (DRY, pattern matching, error handling)
8. ✅ Manual UI testing confirms expected behavior

---

## Next Steps

After completion:
1. Create PR with title: `Feature 007: Jack Card (Jump/Skip)`
2. Link PR to this plan and spec
3. Request code review
4. Address feedback
5. Merge to main

## References

- Feature spec: `specs/007-jack-card/spec.md`
- Research doc: `specs/007-jack-card/research.md`
- Data model: `specs/007-jack-card/data-model.md`
- King card reference: `specs/006-king-card/`
- Constitution: `.specify/memory/constitution.md`
