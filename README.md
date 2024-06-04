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
{:ok, _pid} = Finitomata.start_link()

Finitomata.start_fsm Kadi.Games.Poker.FsmServer, "KadiServer", %{}

# Start the game -> config optional
Finitomata.transition "KadiServer", {:start, %{cards_to_deal: 2}}

# Show the current state
Finitomata.state "KadiServer"

# Add players
Finitomata.transition "KadiServer", {:add_player, "Kevin"}
Finitomata.transition "KadiServer", {:add_player, "Devin"}

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


TODO:
- Figure out the best place to start the finitomata instance - on session create??
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

Desired payload on auto-start: 
Started with: `Finitomata.start_fsm Kadi.Games.Poker.FsmServer, "KadiServer", %{}`

```
[debug] [→ ↹] [state: #Finitomata<[name: "KadiServer", state: [current: :*, previous: nil, payload: %{}], internals: [errored?: false, persisted?: false, timer: false]]>, exiting: :*]
```

Ideal way to start this:
```
Finitomata.start_fsm Kadi.Games.Poker.FsmServer, "session-code", %{}
```

On the player logging in and creating a new session.
There should also be a few transitions