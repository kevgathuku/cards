# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Kadi.Repo.insert!(%Kadi.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
suits = ~w(hearts diamonds clubs spades)
ranks = Enum.map(2..10, &to_string/1) ++ ~w(jack queen king ace)

for suit <- suits, rank <- ranks do
  Kadi.Repo.insert!(%Kadi.Games.Card{suit: suit, rank: rank})
end
