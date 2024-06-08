defmodule KadiWeb.GameController do
  use KadiWeb, :controller

  def new(conn, _params) do
    render(conn, :new)
  end
end
