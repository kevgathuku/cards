# Kadi

A collection of card games.

### Poker

A classic card game popular in Kenya

## Installation

- [Install Elixir](https://elixir-lang.org/install.html). The current stable version should be fine.
- Clone the repo
- For a basic sanity test, run `mix test`

### Runthrough

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

#### Console

Run the following commands inside an iex session `iex -S mix`

```elixir
alias Kadi.Games.Poker

# Create a new game, passing in a name, and an optional config object
Kadi.Registry.create(Kadi.Registry, "poker", %{})

# Lookup the game by the name
{:ok, game_pid} = Kadi.Registry.lookup(Kadi.Registry, "poker")

# Show the current state
Poker.Server.get_state(game_pid)

# Add players
Poker.Server.add_player(game_pid, "Kevin")
Poker.Server.add_player(game_pid, "Devin")

alias Kadi.Games.Poker.Card
deck = [
    # Player 1
    "5♥",
    "8♥",
    # Player 2
    "7♣",
    "6♣",
    # Start card
    "6♦",
    # Remaining stack
    "8♦",
]|> Enum.map(&Card.parse/1)

# Start the game. You can pass in a custom deck if needed
Poker.Server.start_game(game_pid, deck)

# Game now in play
# process some cards played
Poker.Server.play_hand(game_pid, hand)

# More coming soon
```

You can provide a few config options when calling `init`. For now they are:
- `start_cards_blocklist` - Any cards that should not be allowed to start the game
- `finishing_cards` - Cards that can be allowed to finish the game
- `min_players` - Minimum number of players required for a valid game
- `cards_to_deal` - Number of cards to deal to each player when starting the game

Prior art:
- [Level10](https://level10.games/) - https://github.com/dnsbty/level10

Regarding saving server state:
- Save the actions and re-create the latest state if needed

### Current State Machine Transitions

```mermaid
graph TD;
  idle --> |start| lobby;
  lobby --> |add_player| lobby;
  lobby --> |add_player| awaiting_deck;
  lobby --> |start_game| live;
  live --> |play_hand| live;
  live --> |pick| live;
  live --> |play_hand| kadi;
  kadi --> |play_finish_card| end_game;
```
