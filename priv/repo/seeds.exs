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
alias Kadi.Repo
alias Kadi.Games.Card

suits = ~w(hearts diamonds clubs spades)
ranks = Enum.map(2..10, &to_string/1) ++ ~w(jack queen king ace)

Enum.each(suits, fn suit ->
  Enum.each(ranks, fn rank ->
    card_attrs = %{suit: suit, rank: rank}
    card_changeset = Card.changeset(%Card{}, card_attrs)

    case Repo.insert(card_changeset) do
      {:ok, card} ->
        IO.puts("Inserted card: #{card.suit} #{card.rank}")

      {:error, changeset} ->
        errors = Enum.map(changeset.errors, fn {field, {msg, _}} -> "#{field}: #{msg}" end)
        raise "Failed to insert card #{suit} #{rank}: #{Enum.join(errors, ", ")}"
    end
  end)
end)
