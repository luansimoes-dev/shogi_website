defmodule ShogiWeb.PlayLive do
  use ShogiWeb, :live_view

  alias Shogi.Game.TimeControl
  alias Shogi.Matchmaking.Server, as: Matchmaking

  @impl true
  def mount(params, session, socket) do
    player_id = session_player_id(session)

    if connected?(socket) and player_id do
      Phoenix.PubSub.subscribe(Shogi.PubSub, "matchmaking:#{player_id}")
    end

    {time_control_id, time_control, match_error} = resolve_time_control(params)

    {:ok,
     socket
     |> assign(:player_id, player_id)
     |> assign(:time_control_id, time_control_id)
     |> assign(:time_control, time_control)
     |> assign(:matchmaking_status, :idle)
     |> assign(:match_error, match_error)
     |> assign(:game_id, nil)
     |> assign(:side, nil)}
  end

  @impl true
  def handle_event("find_match", _params, %{assigns: %{player_id: nil}} = socket) do
    {:noreply, assign(socket, :match_error, "Nao foi possivel identificar sua sessao.")}
  end

  def handle_event("find_match", _params, socket) do
    case Matchmaking.join_queue(socket.assigns.player_id, socket.assigns.time_control_id) do
      {:waiting} ->
        {:noreply,
         socket
         |> assign(:matchmaking_status, :waiting)
         |> assign(:match_error, nil)}

      {:matched, match} ->
        {:noreply, go_to_match(socket, match)}

      {:error, reason} ->
        {:noreply, assign(socket, :match_error, error_text(reason))}
    end
  end

  def handle_event("cancel_match", _params, socket) do
    if socket.assigns.player_id do
      Matchmaking.leave_queue(socket.assigns.player_id)
    end

    {:noreply,
     socket
     |> assign(:matchmaking_status, :idle)
     |> assign(:match_error, nil)}
  end

  @impl true
  def handle_info(%{event: :matched} = match, socket) do
    {:noreply, go_to_match(socket, match)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, %{assigns: %{matchmaking_status: :waiting, player_id: player_id}})
      when is_binary(player_id) do
    Matchmaking.leave_queue(player_id)
    :ok
  end

  def terminate(_reason, _socket), do: :ok

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lobby-shell">
      <section class="card lobby-panel matchmaking-panel">
        <p class="eyebrow">Matchmaking</p>
        <h1>Jogar agora</h1>
        <p class="muted">Tempo: <strong><%= @time_control.label %></strong></p>

        <%= case @matchmaking_status do %>
          <% :idle -> %>
            <p class="lobby-copy">Entre na fila e espere outro jogador anonimo.</p>

            <button type="button" class="primary-link match-button" phx-click="find_match">
              Procurar partida
            </button>

          <% :waiting -> %>
            <p class="lobby-copy">Procurando adversario...</p>
            <div class="queue-pulse" aria-hidden="true"></div>

            <button type="button" class="btn secondary match-button" phx-click="cancel_match">
              Cancelar
            </button>

          <% :matched -> %>
            <p class="lobby-copy">Partida encontrada. Redirecionando...</p>
        <% end %>

        <%= if @match_error do %>
          <div class="error-message move-error" role="alert">
            <%= @match_error %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp go_to_match(socket, match) do
    socket
    |> assign(:matchmaking_status, :matched)
    |> assign(:game_id, match.game_id)
    |> assign(:side, match.side)
    |> assign(:match_error, nil)
    |> push_navigate(to: ~p"/game/#{match.game_id}")
  end

  defp resolve_time_control(%{"tc" => time_control_id}) do
    case TimeControl.fetch(time_control_id) do
      {:ok, time_control} ->
        {time_control_id, time_control, nil}

      {:error, _reason} ->
        {TimeControl.default_id(), TimeControl.default(), "Ritmo invalido. Usando 10 + 2."}
    end
  end

  defp resolve_time_control(_params), do: {TimeControl.default_id(), TimeControl.default(), nil}

  defp session_player_id(%{"player_id" => player_id}), do: player_id
  defp session_player_id(%{player_id: player_id}), do: player_id
  defp session_player_id(_session), do: nil

  defp error_text(:already_queued), do: "Voce ja esta na fila."
  defp error_text(:invalid_time_control), do: "Ritmo de tempo invalido."
  defp error_text(reason), do: "Nao foi possivel entrar na fila: #{inspect(reason)}"
end
