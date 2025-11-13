defmodule Kadi.CardGames.SpecialCardsTwoTest do
  use ExUnit.Case, async: true
  alias Kadi.CardGames
  alias Kadi.Games.{Card, GameSession, GameSessionPlayer}

  describe "two card penalty logic" do
    # Add tests for:
    # - Playing '2' triggers penalty
    # - Penalty can be blocked by Ace or another '2'
    # - '2' cannot be starting or finishing card
    # - Penalty is not additive
    # - Suit matching with requested_suit
    # - UI feedback for penalty
    # - Edge cases (blocked, transferred, etc)
    test "playing '2' triggers penalty for next player" do
      # ...test implementation...
    end

    # More tests to be added per quickstart.md
  end
end
