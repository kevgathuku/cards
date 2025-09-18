defmodule Kadi.Fetcher do
  @moduledoc """
  Fetcher keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  import Ecto.Query, warn: false
  alias Kadi.{GameSession, Repo}

  @doc """
  Returns the state of a specific game, constructed from the events
  """
  def get_game_state(game_id) do
    case Repo.get(GameSession, game_id) do
      game_session when not is_nil(game_session) -> {:ok, game_session}
      _ -> {:error, :not_found}
    end
  end

  def fetch_games() do
    # TODO: Fetch by player when auth is added
    GameSession |> Repo.all
  end

end
