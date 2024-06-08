defmodule KadiWeb.GameController do
  use KadiWeb, :controller

  alias Kadi.GameSession

  def new(conn, _params) do
    # session = %GameSession{}
    changeset = GameSession.changeset(%GameSession{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{game_session: game_session_params} = _params) do
    case GameSession.create_item(game_session_params) do
      {:ok, game_session} ->
        conn
        |> put_flash(:info, "Game Session created!")
        |> redirect(to: Routes.game_session_path(conn, :show, game_session))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
