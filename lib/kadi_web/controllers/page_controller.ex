defmodule KadiWeb.PageController do
  use KadiWeb, :controller

  def chat(conn, _params) do
    render(conn, :chat)
  end
end
