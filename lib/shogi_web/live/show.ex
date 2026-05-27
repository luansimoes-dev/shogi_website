defmodule ShogiWeb.GameLive.Show do
  use ShogiWeb, :live_view

  alias Shogi.Game.Board
  alias Shogi.Game.Server

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Shogi.PubSub, "game:#{game_id}")
    end

    case Server.start_link(game_id: game_id) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok,
     socket
     |> assign(:game_id, game_id)
     |> assign(:player_id, nil)
     |> assign(:side, nil)
     |> assign(:selected, nil)
     |> assign(:move_error, nil)
     |> assign(:game, Server.state(game_id))}
  end

  @impl true
  def handle_event("join", %{"side" => side}, socket) do
    side = String.to_existing_atom(side)
    player_id = "player-" <> Integer.to_string(System.unique_integer([:positive]))

    case Server.join(socket.assigns.game_id, player_id, side) do
      {:ok, _phase} ->
        {:noreply,
         socket
         |> assign(:player_id, player_id)
         |> assign(:side, side)
         |> assign(:move_error, nil)
         |> assign(:game, Server.state(socket.assigns.game_id))}

      {:error, reason} ->
        {:noreply, assign(socket, :move_error, error_text(reason))}
    end
  end

  @impl true
  def handle_event("square", %{"col" => col, "row" => row}, socket) do
    pos = {String.to_integer(col), String.to_integer(row)}
    clicked_piece = Board.get(socket.assigns.game.board, pos)

    case socket.assigns.selected do
      nil ->
        select_square(socket, pos, clicked_piece)

      from ->
        if own_piece?(clicked_piece, socket.assigns.side) do
          select_square(socket, pos, clicked_piece)
        else
          move_piece(socket, from, pos)
        end
    end
  end

  @impl true
  def handle_info({:game_updated, game}, socket) do
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info({:game_started, game}, socket) do
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info({:game_over, _info}, socket) do
    {:noreply, assign(socket, :game, Server.state(socket.assigns.game_id))}
  end

  defp select_square(socket, pos, piece) do
    cond do
      socket.assigns.player_id == nil ->
        {:noreply,
         socket
         |> assign(:selected, nil)
         |> assign(:move_error, "Entre como Sente ou Gote antes de jogar.")}

      piece == nil ->
        {:noreply,
         socket
         |> assign(:selected, nil)
         |> assign(:move_error, "Escolha uma peça para mover.")}

      piece.owner != socket.assigns.side ->
        {:noreply,
         socket
         |> assign(:selected, nil)
         |> assign(:move_error, "Essa peça pertence ao outro jogador.")}

      true ->
        {:noreply,
         socket
         |> assign(:selected, pos)
         |> assign(:move_error, nil)}
    end
  end

  defp move_piece(socket, from, to) when from == to do
    {:noreply,
     socket
     |> assign(:selected, nil)
     |> assign(:move_error, nil)}
  end

  defp move_piece(socket, from, to) do
    case Server.move(socket.assigns.game_id, socket.assigns.player_id, from, to) do
      {:ok, _game} ->
        {:noreply,
         socket
         |> assign(:selected, nil)
         |> assign(:move_error, nil)
         |> assign(:game, Server.state(socket.assigns.game_id))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:selected, nil)
         |> assign(:move_error, error_text(reason))
         |> assign(:game, Server.state(socket.assigns.game_id))}
    end
  end

  defp own_piece?(%{owner: owner}, side), do: owner == side
  defp own_piece?(_, _side), do: false

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

  defp side_label(:sente), do: "Sente"
  defp side_label(:gote), do: "Gote"
  defp side_label(nil), do: "Nao entrou"
  defp side_label(side), do: inspect(side)

  defp phase_label(:waiting), do: "Aguardando jogadores"
  defp phase_label(:playing), do: "Em jogo"
  defp phase_label(:finished), do: "Finalizada"
  defp phase_label(phase), do: inspect(phase)

  defp selected_label(nil), do: "Nenhuma"
  defp selected_label({col, row}), do: "#{col}, #{row}"

  defp error_text(:side_taken), do: "Esse lado ja esta ocupado."
  defp error_text(:already_joined), do: "Voce ja entrou nesta partida."
  defp error_text(:game_not_waiting), do: "A partida ja comecou."
  defp error_text(:game_not_started), do: "A partida ainda nao comecou."
  defp error_text(:game_finished), do: "A partida ja terminou."
  defp error_text(:not_your_turn), do: "Nao e o seu turno."
  defp error_text(:not_a_player), do: "Entre como Sente ou Gote antes de jogar."
  defp error_text(:invalid_move), do: "Movimento invalido para essa peca."
  defp error_text(:no_piece), do: "Nao existe peca na origem."
  defp error_text(:invalid_position), do: "Casa fora do tabuleiro."
  defp error_text(:own_piece_on_destination), do: "O destino tem uma peca sua."
  defp error_text(:blocked_by_own_piece), do: "O destino tem uma peca sua."
  defp error_text(:path_blocked), do: "Ha uma peca bloqueando o caminho."
  defp error_text(reason), do: "Jogada recusada: #{inspect(reason)}"

  defp piece_symbol(%{type: :king}), do: "王"
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
