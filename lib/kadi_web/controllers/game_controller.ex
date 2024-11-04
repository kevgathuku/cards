defmodule KadiWeb.GameController do
  use KadiWeb, :controller

  alias Kadi.GameSession
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

  def show(conn, %{"id" => game_session_id} = _params) do
    case Kadi.Repo.get(GameSession, game_session_id) do
      nil ->
      conn
      |> put_flash(:error, "Game Session not found!")
      |> redirect(to: "/")

      game_session ->
        render(conn, :show, game_session: game_session)
    end
  end
end
