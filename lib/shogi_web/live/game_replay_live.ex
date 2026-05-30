defmodule ShogiWeb.GameReplayLive do
  use ShogiWeb, :live_view

  alias Shogi.Game.Board
  alias Shogi.Games
  alias Shogi.Repo

  import ShogiWeb.Components.GameBoard

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    game = Games.get_game_record_by_public_id(game_id)
    moves = Games.list_moves(game_id)

    socket =
      socket
      |> assign(:game_id, game_id)
      |> assign(:game, preload_players(game))
      |> assign(:moves, moves)
      |> assign(:move_index, 0)
      |> assign(:perspective, :sente)
      |> assign(:load_error, game == nil)

    {:ok, assign_replay_position(socket)}
  end

  @impl true
  def handle_event("go_start", _params, socket) do
    {:noreply, socket |> assign(:move_index, 0) |> assign_replay_position()}
  end

  def handle_event("go_prev", _params, socket) do
    index = max(socket.assigns.move_index - 1, 0)
    {:noreply, socket |> assign(:move_index, index) |> assign_replay_position()}
  end

  def handle_event("go_next", _params, socket) do
    index = min(socket.assigns.move_index + 1, length(socket.assigns.moves))
    {:noreply, socket |> assign(:move_index, index) |> assign_replay_position()}
  end

  def handle_event("go_end", _params, socket) do
    {:noreply,
     socket |> assign(:move_index, length(socket.assigns.moves)) |> assign_replay_position()}
  end

  def handle_event("toggle_perspective", _params, socket) do
    perspective = if socket.assigns.perspective == :sente, do: :gote, else: :sente
    {:noreply, assign(socket, :perspective, perspective)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="replay-page">
      <%= if @load_error do %>
        <section class="card replay-panel">
          <p class="eyebrow">Replay</p>
          <h1>Partida não encontrada</h1>
          <p class="muted">Não existe partida persistida com o código <strong><%= @game_id %></strong>.</p>
          <.link navigate={~p"/"} class="btn secondary">Voltar ao lobby</.link>
        </section>
      <% else %>
        <section class="card replay-panel replay-summary">
          <div>
            <p class="eyebrow">Replay</p>
            <h1>Shogi</h1>
            <p class="muted">Game ID: <strong><%= @game.game_id %></strong></p>
          </div>

          <dl class="replay-info-grid">
            <div>
              <dt>Sente</dt>
              <dd><%= player_for(@game, "sente") %></dd>
            </div>
            <div>
              <dt>Gote</dt>
              <dd><%= player_for(@game, "gote") %></dd>
            </div>
            <div>
              <dt>Vencedor</dt>
              <dd><%= side_label(@game.winner_side) %></dd>
            </div>
            <div>
              <dt>Resultado</dt>
              <dd><%= result_label(@game.result_reason) %></dd>
            </div>
            <div>
              <dt>Tempo</dt>
              <dd><%= time_control_label(@game.time_control) %></dd>
            </div>
            <div>
              <dt>Lances</dt>
              <dd><%= @game.move_count %></dd>
            </div>
          </dl>
        </section>

        <div class="replay-main">
          <section class="card replay-toolbar-card">
            <div class="replay-toolbar">
              <div class="replay-counter">Lance <%= @move_index %> / <%= length(@moves) %></div>

              <div class="replay-controls">
                <button type="button" class="btn secondary" phx-click="go_start" disabled={@move_index == 0}>Início</button>
                <button type="button" class="btn secondary" phx-click="go_prev" disabled={@move_index == 0}>Anterior</button>
                <button type="button" class="btn secondary" phx-click="go_next" disabled={@move_index == length(@moves)}>Próximo</button>
                <button type="button" class="btn secondary" phx-click="go_end" disabled={@move_index == length(@moves)}>Final</button>
                <button type="button" class="btn sente" phx-click="toggle_perspective">Inverter</button>
              </div>
            </div>
          </section>

          <section class="card replay-current-move" aria-live="polite">
            <%= current_move_summary(@current_move) %>
          </section>

          <.game_board
            board={@board}
            side={@perspective}
            last_move={@last_move}
            clickable?={false}
            hands_clickable?={false}
            disabled?={true}
            replay_mode?={true}
            clocks={@replay_clocks}
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp assign_replay_position(%{assigns: %{load_error: true}} = socket) do
    socket
    |> assign(:board, Board.new())
    |> assign(:current_move, nil)
    |> assign(:last_move, nil)
    |> assign(:replay_clocks, replay_clocks(nil))
  end

  defp assign_replay_position(socket) do
    index = socket.assigns.move_index
    move = if index > 0, do: Enum.at(socket.assigns.moves, index - 1), else: nil
    board = board_for_move(move)

    socket
    |> assign(:current_move, move)
    |> assign(:board, board)
    |> assign(:last_move, replay_last_move(move))
    |> assign(:replay_clocks, replay_clocks(move))
  end

  defp board_for_move(nil), do: Board.new()

  defp board_for_move(move) do
    case Games.deserialize_board(move.board_after) do
      {:ok, board} -> board
      {:error, _reason} -> Board.new()
    end
  end

  defp preload_players(nil), do: nil
  defp preload_players(game), do: Repo.preload(game, :players)

  defp player_for(%{players: players}, side) do
    players
    |> Enum.find(&(&1.side == side))
    |> case do
      nil -> "-"
      player -> player.player_id
    end
  end

  defp replay_last_move(
         %{kind: "move", from_row: from_row, from_col: from_col, to_row: to_row, to_col: to_col} =
           move
       )
       when is_integer(from_row) and is_integer(from_col) and is_integer(to_row) and
              is_integer(to_col) do
    {:move, {from_row, from_col}, {to_row, to_col}, move.promoted, move.captured_piece_type}
  end

  defp replay_last_move(%{kind: "drop", to_row: to_row, to_col: to_col, piece_type: piece_type})
       when is_integer(to_row) and is_integer(to_col) do
    {:drop, piece_type, {to_row, to_col}}
  end

  defp replay_last_move(_move), do: nil

  defp replay_clocks(nil), do: %{sente: nil, gote: nil}

  defp replay_clocks(move) do
    %{sente: clock_after(move, "sente"), gote: clock_after(move, "gote")}
  end

  defp current_move_summary(nil), do: "Lance atual: Posição inicial."

  defp current_move_summary(move) do
    [
      "Lance atual: #{move.move_number}",
      side_label(move.side),
      move.kind,
      empty_dash(move.piece_type),
      move_path(move),
      "captura: #{empty_dash(move.captured_piece_type)}",
      "promoveu: #{if move.promoted, do: "sim", else: "não"}",
      "relógio: Sente #{format_clock(clock_after(move, "sente"))} / Gote #{format_clock(clock_after(move, "gote"))}",
      result_segment(move.result_after)
    ]
    |> Enum.reject(&(&1 in [nil, "", "-"]))
    |> Enum.join(" · ")
  end

  defp move_path(%{from_row: nil, from_col: nil, to_row: nil, to_col: nil}), do: nil

  defp move_path(%{from_row: nil, from_col: nil, to_row: row, to_col: col}),
    do: "drop em #{position_label(row, col)}"

  defp move_path(%{from_row: from_row, from_col: from_col, to_row: to_row, to_col: to_col}) do
    "#{position_label(from_row, from_col)} → #{position_label(to_row, to_col)}"
  end

  defp result_segment(nil), do: nil
  defp result_segment(result), do: "resultado após: #{result_label(result)}"

  defp side_label(nil), do: "-"
  defp side_label(:sente), do: "Sente"
  defp side_label(:gote), do: "Gote"
  defp side_label("sente"), do: "Sente"
  defp side_label("gote"), do: "Gote"
  defp side_label(side), do: to_string(side)

  defp result_label(nil), do: "-"
  defp result_label("checkmate"), do: "Xeque-mate"
  defp result_label("resignation"), do: "Desistência"
  defp result_label("timeout"), do: "Tempo"
  defp result_label(result), do: to_string(result)

  defp time_control_label(%{"label" => label}), do: label
  defp time_control_label(%{label: label}), do: label
  defp time_control_label(_time_control), do: "-"

  defp position_label(nil, nil), do: "-"
  defp position_label(row, col), do: "#{row},#{col}"

  defp empty_dash(nil), do: "-"
  defp empty_dash(value), do: to_string(value)

  defp clock_after(move, side) do
    case move.clocks_after do
      %{} = clocks -> Map.get(clocks, side) || Map.get(clocks, String.to_atom(side))
      _ -> nil
    end
  end
end
