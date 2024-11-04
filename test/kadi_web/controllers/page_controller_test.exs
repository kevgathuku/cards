defmodule KadiWeb.PageControllerTest do
  use KadiWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Welcome to Poker"
  end
end
