# API Contract: Player Actions (Feature 009 - Two Card)

## Action: play_card
- **Input:**
  - game_session_id: integer
  - player_id: integer
  - card_id: integer
- **Validation:**
  - If card is '2', cannot be starting or finishing card
  - If penalty is active, only Ace or '2' can be played
  - If requested_suit is set, must match suit
- **Output:**
  - {:ok, updated_game_session}
  - {:error, reason}

## Action: draw_card
- **Input:**
  - game_session_id: integer
  - player_id: integer
- **Validation:**
  - If penalty is active, player must draw 2 cards
  - If penalty is blocked, no draw
- **Output:**
  - {:ok, updated_game_session}
  - {:error, reason}

## Action: block_penalty
- **Input:**
  - game_session_id: integer
  - player_id: integer
  - card_id: integer (Ace or '2')
- **Validation:**
  - Only Ace or '2' can block penalty
- **Output:**
  - {:ok, updated_game_session}
  - {:error, reason}

## Action: finish_game
- **Input:**
  - game_session_id: integer
  - player_id: integer
- **Validation:**
  - Cannot finish with '2' card
- **Output:**
  - {:ok, updated_game_session}
  - {:error, reason}
