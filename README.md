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
alias Kadi.Games.Poker.Server

# Pass in an optional config object
{:ok, game_pid} = GenStateMachine.start_link(Server, %{})

# Show the current state
Server.get_state(game_pid)

# Add players
Server.add_player(game_pid, "Kevin")
Server.add_player(game_pid, "Devin")

alias Kadi.Games.Poker.Card
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

# Start the game. You can pass in a custom deck if needed
Server.start_game(game_pid, deck)

# Game now in play
# process some cards played
Server.play_hand(game_pid, hand)

# More coming soon
```

You can provide a few config options when calling `init`. For now they are:
- `start_cards_blocklist` - Any cards that should not be allowed to start the game
- `finishing_cards` - Cards that can be allowed to finish the game
- `min_players` - Minimum number of players required for a valid game
- `cards_to_deal` - Number of cards to deal to each player when starting the game

Prior art:
- [Level10](https://level10.games/) - https://github.com/dnsbty/level10


TODO:
- Add this after scaffolding the sessions stuff
- Read through OTP process docs on this topic
- Does this need a dynamic supervisor?

```
defp do_start_fsm(id, name, impl, payload) when is_atom(impl) do
  DynamicSupervisor.start_child(
    Finitomata.Supervisor.manager_name(id),
    {impl, name: fqn(id, name), payload: payload}
  )
end
```

On the player logging in and creating a new session.
There should also be a few transitions

Regarding saving server state:
- Save the actions and re-create the latest state if needed

### Managing the Dynamically Started Games:

```elixir

# Start process registry to keep track of named processes
{:ok, _} = Registry.start_link(keys: :unique, name: Kadi.Registry)
# Pass in a unique Game ID
game_session = {:via, Registry, {Kadi.Registry, "ABC"}}
# Start the game server, and pass in the name
{:ok, _} = GenStateMachine.start_link(Kadi.Games.Poker.Server, %{}, name: game_session)

# And now the game can be accessed through the name
Server.get_state(game_session)
```
