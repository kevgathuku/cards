defmodule KadiWeb.PageController do
  use KadiWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def game(conn, _params) do
    render(conn, :game)
  end
end
