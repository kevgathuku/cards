type suit =
  | Hearts
  | Diamonds
  | Spades
  | Flowers;

type cardValue =
  | Two
  | Three
  | Four
  | Five
  | Six
  | Seven
  | Eight
  | Nine
  | Ten
  | K
  | Q
  | J
  | A;

type card = {
  suit,
  number: str,
};

type player = {
  card: string,
  name: string,
};

type state = {
  foo: int,
  bar: string,
  players: list(player),
  deck: list(card),
  played: list(card),
  player_turn: int,
};

type rules = {
  start_cards_blocklist: list(cardValue),
  finishing_cards: list(cardValue),
  min_players: int,
  cards_to_deal: int,
};

type gameStatus =
  | NotStarted
  | Lobby
  | AwaitingDeck
  | AwaitingPlayerCards
  | AwaitingStartCard
  | Live
  | Kadi
  | GameOver;

type action =
  | Start
  | AddPlayer
  | AddDeck
  | DealPlayerCards
  | DealStartCard
  | PlayHand
  | Pick
  | Finish;

let initialState = {players: [], deck: [], played: [], player_turn: 0};

let defaultRules = {
  start_cards_blocklist: [K, Q, J, A, Two, Three, Eight],
  finishing_cards: [A, Two, Three, Four, Five, Six, Seven, Nine, Ten],
  min_players: 2,
  cards_to_deal: 4,
};

let transition = (action, state) =>
  switch (state) {
  | NotStarted =>
    switch (input) {
    | Start => Lobby
    | _ => state
    }
  //   Add checks for player names in state, dups, etc.
  | Lobby =>
    switch (action) {
    | AddPlayer => AwaitingDeck
    | _ => state
    }
  | AwaitingDeck =>
    switch (action) {
    | AddDeck => AwaitingPlayerCards
    | _ => state
    }
  | AwaitingPlayerCards =>
    switch (action) {
    | DealPlayerCards => AwaitingStartCard
    | _ => state
    }
  | AwaitingStartCard =>
    switch (action) {
    | DealStartCard => Live
    | _ => state
    }
  | Live =>
    switch (action) {
    | PlayHand => Kadi
    | _ => state
    }
  | Kadi =>
    switch (action) {
    | PlayHand => GameOver
    | _ => state
    }
  | GameOver => state
  };