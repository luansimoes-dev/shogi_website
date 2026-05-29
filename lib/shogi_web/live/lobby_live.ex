defmodule ShogiWeb.LobbyLive do
  use ShogiWeb, :live_view

  alias Shogi.Game.Server

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:player_id, session_player_id(session))
     |> assign(:game_id, new_game_id())}
  end

  @impl true
  def handle_event("new_private_game", _params, socket) do
    game_id = new_game_id()
    start_private_game(game_id)
    {:noreply, push_navigate(socket, to: ~p"/game/#{game_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lobby-shell">
      <section class="card lobby-panel">
        <p class="eyebrow">Lobby</p>
        <h1>Shogi</h1>
        <p class="lobby-copy">
          Entre na fila para jogar automaticamente ou crie uma partida privada para compartilhar.
        </p>

        <div class="lobby-actions">
          <.link navigate={~p"/play"} class="primary-link">
            Jogar agora
          </.link>

          <button type="button" phx-click="new_private_game">
            Criar partida privada
          </button>
        </div>
      </section>
    </div>
    """
  end

  defp start_private_game(game_id) do
    case Server.start_link(game_id: game_id) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp session_player_id(%{"player_id" => player_id}), do: player_id
  defp session_player_id(%{player_id: player_id}), do: player_id
  defp session_player_id(_session), do: nil

  defp new_game_id do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
