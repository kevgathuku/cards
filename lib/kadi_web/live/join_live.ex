defmodule KadiWeb.JoinLive do
  use KadiWeb, :live_view

  alias Kadi.{CardGames, Repo}
  alias Kadi.Games.GameSession

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"short_code" => ""})
    {:ok, assign(socket, form: form)}
  end

  @impl true
  def handle_event("join_game", %{"short_code" => short_code}, socket) do
    current_player = socket.assigns.current_player

    case Repo.get_by(GameSession, short_code: String.upcase(short_code)) do
      nil ->
        {:noreply, put_flash(socket, :error, "The join code provided does not exist!")}

      game_session ->
        case CardGames.join_game_session(current_player, game_session.id) do
          {:ok, _} ->
            {:noreply, redirect(socket, to: ~p"/games/#{game_session.id}")}

          {:error, changeset} ->
            # If already joined (unique constraint), still redirect
            if Enum.any?(changeset.errors, fn {_, {msg, _}} ->
                 String.contains?(msg, "has already been taken")
               end) do
              {:noreply, redirect(socket, to: ~p"/games/#{game_session.id}")}
            else
              error_msg =
                changeset.errors
                |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
                |> Enum.join(", ")

              {:noreply, put_flash(socket, :error, "Failed to join game: #{error_msg}")}
            end
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto p-6 bg-white rounded-lg shadow-md">
      <h1 class="text-2xl font-bold text-gray-800 mb-6">Join a Game</h1>
      <.form for={@form} phx-submit="join_game" class="space-y-4">
        <.input field={@form[:short_code]} type="text" label="Short Code" required />
        <button
          type="submit"
          class="w-full rounded-md bg-teal-50 px-3 py-2 text-sm font-semibold text-green-700 border border-green-700 hover:text-white hover:bg-green-800 focus:ring-4"
        >
          Join Game
        </button>
      </.form>
    </div>
    """
  end
end
