# Cards

A collection of card games.

### Kadi

A classic card game popular in Kenya

## Installation

- [Install Elixir](https://elixir-lang.org/install.html). The current stable version should be fine.
- Clone the repo
- For a basic sanity test, run `mix test`

### Runthrough

Run the following commands inside an iex session `iex -S mix`

```elixir
{:ok, _pid} = Finitomata.start_link()

Finitomata.start_fsm Games.Kadi.FsmServer, "KadiServer", %{}

# Start the game -> config optional
Finitomata.transition "KadiServer", {:init, %{cards_to_deal: 2}}

# Show the current state
Finitomata.state "KadiServer"

# Add players
Finitomata.transition "KadiServer", {:add_player, "Kevin"}
Finitomata.transition "KadiServer", {:add_player, "Devin"}

alias Games.Kadi.Card
deck = [
    # Player 1
    %Card{suit: :hearts, number: :five},
    %Card{suit: :hearts, number: :eight},
    # Player 2
    %Card{suit: :flowers, number: :seven},
    %Card{suit: :flowers, number: :six},
    # Start card
    %Card{suit: :diamonds, number: :six},
    # Remaining stack
    %Card{suit: :diamonds, number: :eight}
]

# Add deck
Finitomata.transition "KadiServer", {:add_deck, %{deck: deck}}

# Deal cards to the players
Finitomata.transition "KadiServer", {:deal_player_cards, nil}

# Deal the start card
Finitomata.transition "KadiServer", {:deal_start_card, nil}

# Game now in play
# More coming soon
```

You can provide a few config options when calling `init`. For now they are:
- `start_cards_blocklist` - Any cards that should not be allowed to start the game
- `finishing_cards` - Cards that can be allowed to finish the game
- `min_players` - Minimum number of players required for a valid game
- `cards_to_deal` - Number of cards to deal to each player when starting the game

Prior art:
- [Level10](https://level10.games/) - https://github.com/dnsbty/level10
