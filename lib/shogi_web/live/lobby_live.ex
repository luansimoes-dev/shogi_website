defmodule ShogiWeb.LobbyLive do
  use ShogiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :game_id, new_game_id())}
  end

  @impl true
  def handle_event("new_game", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/game/#{new_game_id()}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lobby-shell">
      <section class="lobby-panel">
        <p class="eyebrow">Lobby</p>
        <h1>Shogi</h1>
        <p class="lobby-copy">
          Crie uma partida e compartilhe o link com o segundo jogador.
        </p>

        <div class="lobby-actions">
          <.link navigate={~p"/game/#{@game_id}"} class="primary-link">
            Abrir partida
          </.link>

          <button type="button" phx-click="new_game">
            Nova partida
          </button>
        </div>
      </section>
    </div>
    """
  end

  defp new_game_id do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
