defmodule UtilsTest do
  use ExUnit.Case, async: true

  test "create_deck" do
    deck = Utils.create_deck()

    suits = ~w(Hearts Flowers Diamonds Spades)
    num_twos = for suit <- suits, do: {2, suit}

    assert Enum.all?(num_twos, fn card -> Enum.member?(deck, card) end)
    assert Enum.all?(deck, fn {_, suit} -> Enum.member?(suits, suit) end)
  end
end
