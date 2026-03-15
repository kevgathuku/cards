```mermaid
flowchart TD
    S([*]) -->|game-created| Lobby
    Lobby -->|join-game| Lobby
    Lobby -->|"start-game (≥2 players)\ndeals cards + sets starting card"| Live

    subgraph Live ["Status: :live"]
        Normal["Normal Turn\n(no active effect)"]
        Penalty["Penalty Active\n(effect: :penalty)"]
        Suit["Awaiting Suit Select\n(effect: :select-suit)"]
        Answer["Awaiting Answer\n(effect: :awaiting-answer)"]

        Normal -->|"play 2 or 3\n→ creates :penalty effect"| Penalty
        Penalty -->|"play matching 2/3\n→ chain / stack penalty"| Penalty
        Penalty -->|"play Ace\n→ blocks penalty, suit auto-set\nfrom blocked card (no selection needed)"| Normal
        Penalty -->|"accept-penalty\n→ draw 2 or 3 cards"| Normal

        Normal -->|"play Ace (no active penalty)\n→ Ace player selects suit"| Suit
        Suit -->|"select-suit"| Normal

        Normal -->|"play Q or 8 (no answer)\n→ next player must draw to answer"| Answer
        Answer -->|"answer-question\n→ draw 1 card"| Normal

        Normal -->|"play Q or 8 with answer\n(Q/8 + non-Q/8 cards in one play)"| Normal
        Normal -->|"play K\n→ reverse turn direction"| Normal
        Normal -->|"play J (one or more)\n→ skip 1+ players"| Normal
        Normal -->|"play regular card (4-7, 9, 10)"| Normal
        Normal -->|"draw-card\n→ pass turn"| Normal

        Normal -->|"kadi player plays special card\nas last card → player becomes :cardless\n(must draw-card before playing again)"| Normal
    end

    Live -->|"kadi player plays non-special card\n(4-7, 9, 10) as last card\n→ win"| Finished([*])
```

**Notes on game model:**

- **Game statuses**: `:lobby` → `:live` → `:finished` (only 3 top-level states)
- **Effects** live inside `:live` status — they constrain valid actions, not separate game states
- **Player statuses** (per-player, not game-level):
  - `:normal` — regular play
  - `:kadi` — declared; can win on next valid finish
  - `:cardless` — played a special card (K/J/Q/8/2/3/A) as their very last card; must draw before playing
- **Valid combos**: multiple Aces, multiple Jacks, multiple 2s, multiple 3s, multiple Q/8 cards; Kings cannot be combined
- **Invalid starting cards**: J, 2, 3 (Q, K, A, and regular cards are all valid starting cards)
- **Win condition**: player must be in `:kadi` status AND empty their hand with a non-special card (4-7, 9, 10)
