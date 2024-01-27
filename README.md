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
alias Games.Kadi.Server

# Start a game session
{:ok, state} = Server.init()

# Add some players
# This will be easier after moving to GenServer
# For now you need to keep a reference to the state, which is returned from most functions
{:ok, with_player_1} = Server.add_player(state, "Salah")
{:ok, with_player_2} = Server.add_player(state, "Mané")

# Start the game
{:ok, started} = Server.start_game(with_player_2)

# More coming soon
```

You can provide a few config options when calling `init`. For now they are:
- `start_cards_blocklist` - Any cards that should not be allowed to start the game
- `finishing_cards` - Cards that can be allowed to finish the game
- `min_players` - Minimum number of players required for a valid game
- `cards_to_deal` - Number of cards to deal to each player when starting the game