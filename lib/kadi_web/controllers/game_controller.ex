defmodule KadiWeb.GameController do
  use KadiWeb, :controller

  alias Kadi.{Fetcher}
  alias Kadi.Games.GameSession
  require Ecto.UUID

  def new(conn, _params) do
    alias Phoenix.Component
    form = %GameSession{} |> Ecto.Changeset.change() |> Component.to_form()
    render(conn, :new, form: form)
  end

  def create(conn, %{"game_session" => game_session_params} = _params) do
    game_code = Ecto.UUID.generate()
    params_with_code = Map.merge(game_session_params, %{"short_code" => game_code})
    changeset = GameSession.changeset(%GameSession{}, params_with_code)

    case Kadi.Repo.insert(changeset) do
      {:ok, game_session} ->
        # Create the Game Server here
        conn
        |> put_flash(:info, "Game Session created!")
        |> redirect(to: ~p"/games/#{game_session}")

      {:error, changeset} ->
        # do something with changeset
        render(conn, :new, changeset: changeset)
    end
  end
end
