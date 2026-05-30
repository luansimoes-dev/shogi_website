defmodule ShogiWeb.Components.GameBoard do
  use ShogiWeb, :html

  alias Shogi.Game.Board

  def game_board(assigns) do
    assigns =
      assigns
      |> assign_new(:side, fn -> :sente end)
      |> assign_new(:selected, fn -> nil end)
      |> assign_new(:selected_drop, fn -> nil end)
      |> assign_new(:last_move, fn -> nil end)
      |> assign_new(:clickable?, fn -> false end)
      |> assign_new(:hands_clickable?, fn -> false end)
      |> assign_new(:disabled?, fn -> false end)
      |> assign_new(:replay_mode?, fn -> false end)
      |> assign_new(:clocks, fn -> %{sente: nil, gote: nil} end)
      |> assign_new(:turn, fn -> nil end)
      |> assign_new(:phase, fn -> nil end)
      |> then(fn assigns ->
        assigns
        |> assign(:top_side, top_side(assigns.side))
        |> assign(:bottom_side, bottom_side(assigns.side))
        |> assign(
          :hand_sections,
          hand_sections(assigns.board, assigns.side, assigns.replay_mode?)
        )
      end)

    ~H"""
    <section class="card board-card">
      <div class="clock-row top-clock">
        <div class={clock_class(@clocks, @turn, @phase, @top_side)}>
          <span><%= side_label(@top_side) %></span>
          <strong><%= format_clock(clock_value(@clocks, @top_side)) %></strong>
        </div>
      </div>

      <div class={["board-wrapper", @replay_mode? && "replay-board-wrapper"]}>
        <div class="shogi-board" aria-label="Tabuleiro de Shogi">
          <%= for row <- board_rows(@side) do %>
            <%= for col <- board_cols(@side) do %>
              <% pos = {row, col} %>
              <% piece = Board.get(@board, pos) %>
              <% square_class = [
                "square",
                rem(row + col, 2) == 0 && "light",
                rem(row + col, 2) == 1 && "dark",
                square_status(@selected, @last_move, pos)
              ] %>

              <%= if @clickable? do %>
                <button
                  type="button"
                  class={square_class}
                  phx-click="square"
                  phx-value-row={row}
                  phx-value-col={col}
                  aria-label={"Casa row #{row}, col #{col}"}
                  data-row={row}
                  data-col={col}
                  disabled={@disabled?}
                >
                  <.piece_view piece={piece} side={@side} />
                </button>
              <% else %>
                <div class={square_class} data-row={row} data-col={col}>
                  <.piece_view piece={piece} side={@side} />
                </div>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </div>

      <div class="clock-row bottom-clock">
        <div class={clock_class(@clocks, @turn, @phase, @bottom_side)}>
          <span><%= side_label(@bottom_side) %></span>
          <strong><%= format_clock(clock_value(@clocks, @bottom_side)) %></strong>
        </div>
      </div>
    </section>

    <%= for hand <- @hand_sections do %>
      <aside class={["card", "hand", to_string(hand.side)]}>
        <div>
          <p class="eyebrow"><%= side_label(hand.side) %></p>
          <h2><%= hand.title %></h2>
        </div>

        <div class="hand-list">
          <%= if hand.pieces == [] do %>
            <span class="empty-hand">Sem pecas</span>
          <% else %>
            <%= for piece <- hand.pieces do %>
              <%= if hand.clickable? and @hands_clickable? and not @disabled? do %>
                <button
                  type="button"
                  class={[
                    "hand-piece",
                    to_string(hand.side),
                    piece_orientation_class(%{owner: hand.side}, @side),
                    selected_drop_class(@selected_drop, piece, hand.side)
                  ]}
                  phx-click="select_drop"
                  phx-value-type={to_string(piece)}
                  phx-value-side={hand.side}
                >
                  <%= piece_symbol(%{type: piece, owner: hand.side}) %>
                </button>
              <% else %>
                <span class={[
                  "hand-piece",
                  to_string(hand.side),
                  piece_orientation_class(%{owner: hand.side}, @side),
                  "disabled"
                ]}>
                  <%= piece_symbol(%{type: piece, owner: hand.side}) %>
                </span>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </aside>
    <% end %>
    """
  end

  defp piece_view(%{piece: nil} = assigns),
    do: ~H"""
    """

  defp piece_view(assigns) do
    ~H"""
    <span class={[
      "piece",
      to_string(@piece.owner),
      piece_orientation_class(@piece, @side)
    ]}>
      <%= piece_symbol(@piece) %>
    </span>
    """
  end

  defp top_side(:sente), do: :gote
  defp top_side(:gote), do: :sente
  defp top_side(_side), do: :gote

  defp bottom_side(:sente), do: :sente
  defp bottom_side(:gote), do: :gote
  defp bottom_side(_side), do: :sente

  defp board_rows(:gote), do: 8..0//-1
  defp board_rows(_side), do: 0..8

  defp board_cols(:gote), do: 8..0//-1
  defp board_cols(_side), do: 0..8

  defp hand_sections(board, _side, true) do
    [
      %{title: "Capturas", side: :gote, pieces: board.hands.gote, clickable?: false},
      %{title: "Capturas", side: :sente, pieces: board.hands.sente, clickable?: false}
    ]
  end

  defp hand_sections(board, :gote, _replay?) do
    [
      %{title: "Sua mao", side: :gote, pieces: board.hands.gote, clickable?: true},
      %{title: "Mao do adversario", side: :sente, pieces: board.hands.sente, clickable?: false}
    ]
  end

  defp hand_sections(board, :sente, _replay?) do
    [
      %{title: "Sua mao", side: :sente, pieces: board.hands.sente, clickable?: true},
      %{title: "Mao do adversario", side: :gote, pieces: board.hands.gote, clickable?: false}
    ]
  end

  defp hand_sections(board, _side, _replay?) do
    [
      %{title: "Sente", side: :sente, pieces: board.hands.sente, clickable?: false},
      %{title: "Gote", side: :gote, pieces: board.hands.gote, clickable?: false}
    ]
  end

  defp piece_orientation_class(%{owner: owner}, viewer_side) do
    if owner == viewer_side_or_default(viewer_side), do: "own-piece", else: "opponent-piece"
  end

  defp viewer_side_or_default(nil), do: :sente
  defp viewer_side_or_default(side), do: side

  defp square_status(selected, last_move, pos) do
    cond do
      selected == pos -> "selected"
      last_move_highlight?(last_move, pos) -> "last-move"
      true -> nil
    end
  end

  defp last_move_highlight?({:move, from, to, _promote, _captured}, pos), do: pos in [from, to]
  defp last_move_highlight?({:drop, _type, to}, pos), do: pos == to
  defp last_move_highlight?(_, _pos), do: false

  defp selected_drop_class(%{type: type, owner: owner}, type, owner), do: "selected-drop"
  defp selected_drop_class(_selected_drop, _type, _owner), do: nil

  defp clock_class(clocks, turn, phase, side) do
    seconds = clock_value(clocks, side)

    [
      "clock",
      turn == side and phase == :playing && "active",
      is_integer(seconds) and seconds <= 10 && "low-time"
    ]
  end

  defp clock_value(%{} = clocks, side),
    do: Map.get(clocks, side) || Map.get(clocks, to_string(side))

  defp clock_value(_clocks, _side), do: nil

  def format_clock(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  def format_clock(_seconds), do: "--:--"

  defp side_label(:sente), do: "Sente"
  defp side_label(:gote), do: "Gote"
  defp side_label(nil), do: "Nao entrou"
  defp side_label(side), do: inspect(side)

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
end
