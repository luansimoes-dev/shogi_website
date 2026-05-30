defmodule ShogiWeb.GameReplayLive do
  use ShogiWeb, :live_view

  alias Shogi.Game.Board
  alias Shogi.Games
  alias Shogi.Repo

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

        <section class="card replay-board-card">
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

          <div class="board-wrapper replay-board-wrapper">
            <div class="shogi-board" aria-label="Tabuleiro de replay">
              <%= for row <- board_rows(@perspective) do %>
                <%= for col <- board_cols(@perspective) do %>
                  <% pos = {row, col} %>
                  <% piece = Board.get(@board, pos) %>

                  <div
                    class={[
                      "square",
                      rem(row + col, 2) == 0 && "light",
                      rem(row + col, 2) == 1 && "dark"
                    ]}
                    data-row={row}
                    data-col={col}
                  >
                    <%= if piece do %>
                      <span class={[
                        "piece",
                        to_string(piece.owner),
                        piece_orientation_class(piece, @perspective),
                        promoted_piece?(piece) && "promoted-piece"
                      ]}>
                        <%= piece_symbol(piece) %>
                      </span>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </section>

        <aside class="card replay-move-card">
          <p class="eyebrow">Lance atual</p>
          <%= if @current_move do %>
            <dl class="replay-move-details">
              <div><dt>Número</dt><dd><%= @current_move.move_number %></dd></div>
              <div><dt>Lado</dt><dd><%= side_label(@current_move.side) %></dd></div>
              <div><dt>Tipo</dt><dd><%= @current_move.kind %></dd></div>
              <div><dt>Peça</dt><dd><%= empty_dash(@current_move.piece_type) %></dd></div>
              <div><dt>Origem</dt><dd><%= position_label(@current_move.from_row, @current_move.from_col) %></dd></div>
              <div><dt>Destino</dt><dd><%= position_label(@current_move.to_row, @current_move.to_col) %></dd></div>
              <div><dt>Promoveu</dt><dd><%= if @current_move.promoted, do: "sim", else: "não" %></dd></div>
              <div><dt>Captura</dt><dd><%= empty_dash(@current_move.captured_piece_type) %></dd></div>
              <div><dt>Relógio Sente</dt><dd><%= format_clock(clock_after(@current_move, "sente")) %></dd></div>
              <div><dt>Relógio Gote</dt><dd><%= format_clock(clock_after(@current_move, "gote")) %></dd></div>
              <div><dt>Resultado após</dt><dd><%= result_label(@current_move.result_after) %></dd></div>
            </dl>
          <% else %>
            <p class="muted">Posição inicial.</p>
          <% end %>
        </aside>
      <% end %>
    </div>
    """
  end

  defp assign_replay_position(%{assigns: %{load_error: true}} = socket) do
    socket
    |> assign(:board, Board.new())
    |> assign(:current_move, nil)
  end

  defp assign_replay_position(socket) do
    index = socket.assigns.move_index
    move = if index > 0, do: Enum.at(socket.assigns.moves, index - 1), else: nil
    board = board_for_move(move)

    socket
    |> assign(:current_move, move)
    |> assign(:board, board)
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

  defp board_rows(:gote), do: 8..0//-1
  defp board_rows(_side), do: 0..8

  defp board_cols(:gote), do: 8..0//-1
  defp board_cols(_side), do: 0..8

  defp piece_orientation_class(%{owner: owner}, viewer_side) do
    if owner == viewer_side, do: "own-piece", else: "opponent-piece"
  end

  defp promoted_piece?(%{type: type}) do
    type in [
      :promoted_rook,
      :promoted_bishop,
      :promoted_silver,
      :promoted_knight,
      :promoted_lance,
      :promoted_pawn
    ]
  end

  defp piece_symbol(%{type: :king}), do: "玉"
  defp piece_symbol(%{type: :rook}), do: "飛"
  defp piece_symbol(%{type: :bishop}), do: "角"
  defp piece_symbol(%{type: :gold}), do: "金"
  defp piece_symbol(%{type: :silver}), do: "銀"
  defp piece_symbol(%{type: :knight}), do: "桂"
  defp piece_symbol(%{type: :lance}), do: "香"
  defp piece_symbol(%{type: :pawn}), do: "歩"
  defp piece_symbol(%{type: :promoted_rook}), do: "龍"
  defp piece_symbol(%{type: :promoted_bishop}), do: "馬"
  defp piece_symbol(%{type: :promoted_silver}), do: "全"
  defp piece_symbol(%{type: :promoted_knight}), do: "圭"
  defp piece_symbol(%{type: :promoted_lance}), do: "杏"
  defp piece_symbol(%{type: :promoted_pawn}), do: "と"
  defp piece_symbol(_), do: "?"

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

  defp format_clock(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  defp format_clock(_seconds), do: "-"
end
