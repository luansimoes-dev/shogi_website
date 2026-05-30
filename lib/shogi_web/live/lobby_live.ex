defmodule ShogiWeb.LobbyLive do
  use ShogiWeb, :live_view

  alias Shogi.Game.{Server, TimeControl}

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:player_id, session_player_id(session))
     |> assign(:time_controls, TimeControl.all())
     |> assign(:selected_online_time_control, TimeControl.default_id())
     |> assign(:selected_private_time_control, TimeControl.default_id())
     |> assign(:join_code, "")
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("select_online_time_control", %{"time-control" => time_control_id}, socket) do
    {:noreply, select_time_control(socket, :selected_online_time_control, time_control_id)}
  end

  def handle_event("select_private_time_control", %{"time-control" => time_control_id}, socket) do
    {:noreply, select_time_control(socket, :selected_private_time_control, time_control_id)}
  end

  def handle_event("find_match", _params, socket) do
    time_control_id = socket.assigns.selected_online_time_control

    case TimeControl.fetch(time_control_id) do
      {:ok, _time_control} ->
        {:noreply, push_navigate(socket, to: ~p"/play?tc=#{time_control_id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_text(reason))}
    end
  end

  def handle_event("create_private_game", _params, socket) do
    time_control_id = socket.assigns.selected_private_time_control

    with {:ok, time_control} <- TimeControl.fetch(time_control_id) do
      game_id = new_game_id()
      start_private_game(game_id, time_control)
      {:noreply, push_navigate(socket, to: ~p"/game/#{game_id}")}
    else
      {:error, reason} ->
        {:noreply, assign(socket, :error, error_text(reason))}
    end
  end

  def handle_event("update_join_code", %{"join" => %{"code" => code}}, socket) do
    {:noreply, assign(socket, :join_code, code)}
  end

  def handle_event("join_private_game", %{"join" => %{"code" => code}}, socket) do
    join_private_game(socket, code)
  end

  def handle_event("join_private_game", _params, socket) do
    join_private_game(socket, socket.assigns.join_code)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-page">
      <section class="home-hero">
        <p class="eyebrow">MVP</p>
        <h1 class="home-title">Shogi Online</h1>
        <p class="home-subtitle">Escolha o ritmo, jogue por pareamento ou crie uma partida privada.</p>
      </section>

      <section class="home-actions">
        <article class="card play-card">
          <div>
            <p class="eyebrow">Jogar online</p>
            <h2>Matchmaking</h2>
            <p class="muted">Entre em uma fila com jogadores do mesmo ritmo.</p>
          </div>

          <div class="time-control-grid" aria-label="Tempo para jogar online">
            <%= for time_control <- @time_controls do %>
              <button
                type="button"
                class={[
                  "time-control-option",
                  @selected_online_time_control == time_control.id && "selected"
                ]}
                phx-click="select_online_time_control"
                phx-value-time-control={time_control.id}
              >
                <strong><%= time_control.label %></strong>
                <span><%= time_control.initial_seconds |> div(60) %> min</span>
              </button>
            <% end %>
          </div>

          <button type="button" class="primary-button" phx-click="find_match">
            Procurar adversário
          </button>
        </article>

        <article class="card play-card">
          <div>
            <p class="eyebrow">Partida privada</p>
            <h2>Criar link</h2>
            <p class="muted">Crie uma sala e compartilhe o link com outro jogador.</p>
          </div>

          <div class="time-control-grid" aria-label="Tempo para partida privada">
            <%= for time_control <- @time_controls do %>
              <button
                type="button"
                class={[
                  "time-control-option",
                  @selected_private_time_control == time_control.id && "selected"
                ]}
                phx-click="select_private_time_control"
                phx-value-time-control={time_control.id}
              >
                <strong><%= time_control.label %></strong>
                <span><%= time_control.initial_seconds |> div(60) %> min</span>
              </button>
            <% end %>
          </div>

          <button type="button" class="secondary-button" phx-click="create_private_game">
            Criar link
          </button>
        </article>

        <article class="card play-card join-card">
          <div>
            <p class="eyebrow">Entrar</p>
            <h2>Partida privada</h2>
            <p class="muted">Cole o código da partida ou uma URL completa.</p>
          </div>

          <.form for={%{}} as={:join} phx-change="update_join_code" phx-submit="join_private_game" class="join-private-form">
            <input
              type="text"
              name="join[code]"
              value={@join_code}
              placeholder="codigo ou /game/abc123"
              autocomplete="off"
            />

            <button type="submit" class="primary-button">Entrar</button>
          </.form>
        </article>
      </section>

      <%= if @error do %>
        <div class="error-message home-error" role="alert"><%= @error %></div>
      <% end %>
    </div>
    """
  end

  defp select_time_control(socket, assign_name, time_control_id) do
    case TimeControl.fetch(time_control_id) do
      {:ok, _time_control} ->
        socket
        |> assign(assign_name, time_control_id)
        |> assign(:error, nil)

      {:error, reason} ->
        assign(socket, :error, error_text(reason))
    end
  end

  defp join_private_game(socket, code) do
    case extract_game_id(code) do
      {:ok, game_id} ->
        {:noreply, push_navigate(socket, to: ~p"/game/#{game_id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_text(reason))}
    end
  end

  defp extract_game_id(code) when is_binary(code) do
    code = String.trim(code)

    game_id =
      case URI.parse(code) do
        %URI{path: "/game/" <> id} ->
          id

        %URI{path: path} when is_binary(path) ->
          path |> String.trim_leading("/") |> strip_game_prefix()

        _ ->
          code
      end

    game_id = game_id |> String.split(["?", "#"], parts: 2) |> List.first() |> String.trim()

    if valid_game_id?(game_id), do: {:ok, game_id}, else: {:error, :invalid_game_id}
  end

  defp extract_game_id(_code), do: {:error, :invalid_game_id}

  defp strip_game_prefix("game/" <> id), do: id
  defp strip_game_prefix(id), do: id

  defp valid_game_id?(game_id) do
    String.match?(game_id, ~r/^[A-Za-z0-9_-]{3,80}$/)
  end

  defp start_private_game(game_id, time_control) do
    child_spec = {Server, game_id: game_id, time_control: time_control}

    case DynamicSupervisor.start_child(Shogi.Game.Supervisor, child_spec) do
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

  defp error_text(:invalid_time_control), do: "Escolha um ritmo de tempo valido."
  defp error_text(:invalid_game_id), do: "Informe um codigo ou link de partida valido."
  defp error_text(reason), do: "Nao foi possivel continuar: #{inspect(reason)}"
end
