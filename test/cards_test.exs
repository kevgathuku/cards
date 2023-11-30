defmodule CardsTest do
  use ExUnit.Case
  doctest Cards

  test "generates a valid deck" do
    deck = Cards.create_deck()
    assert length(deck) == 52
    assert Enum.member?(deck, {:two, :hearts}) == true
    assert Enum.member?(deck, {:three, :diamonds}) == true
  end
end
