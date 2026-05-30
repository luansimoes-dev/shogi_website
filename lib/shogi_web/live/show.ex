defmodule ShogiWeb.GameLive.Show do
  use ShogiWeb, :live_view

  alias Shogi.Game.{Board, Rules, Server}

  @impl true
  def mount(%{"game_id" => game_id}, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Shogi.PubSub, "game:#{game_id}")
      :timer.send_interval(1_000, self(), :clock_tick)
    end

    start_game(game_id)

    game = Server.state(game_id)
    player_id = session_player_id(session)

    {:ok,
     socket
     |> assign(:game_id, game_id)
     |> assign(:player_id, player_id)
     |> assign(:side, side_for_player(game, player_id))
     |> assign(:selected, nil)
     |> assign(:selected_drop, nil)
     |> assign(:pending_promotion, nil)
     |> assign(:confirm_resign, false)
     |> assign(:move_error, nil)
     |> assign(:game, game)}
  end

  @impl true
  def handle_event("join", %{"side" => side}, socket) do
    with {:ok, side} <- parse_side(side),
         player_id when is_binary(player_id) <- socket.assigns.player_id do
      case Server.join(socket.assigns.game_id, player_id, side) do
        {:ok, _phase} ->
          {:noreply,
           socket
           |> assign(:player_id, player_id)
           |> assign(:side, side)
           |> clear_interaction()
           |> assign(:game, Server.state(socket.assigns.game_id))}

        {:error, reason} ->
          {:noreply, assign(socket, :move_error, error_text(reason))}
      end
    else
      nil -> {:noreply, assign(socket, :move_error, "Sessao sem jogador anonimo.")}
      :error -> {:noreply, assign(socket, :move_error, "Lado invalido.")}
    end
  end

  @impl true
  def handle_event("select_drop", %{"type" => type, "side" => side}, socket) do
    with :ok <- ensure_game_active(socket),
         {:ok, type} <- parse_piece_type(type),
         {:ok, side} <- parse_side(side),
         :ok <- validate_drop_selection(socket, type, side) do
      {:noreply,
       socket
       |> assign(:selected, nil)
       |> assign(:selected_drop, %{type: type, owner: side})
       |> assign(:pending_promotion, nil)
       |> assign(:move_error, nil)}
    else
      {:error, reason} -> {:noreply, assign(socket, :move_error, error_text(reason))}
      :error -> {:noreply, assign(socket, :move_error, "Peca invalida para drop.")}
    end
  end

  @impl true
  def handle_event("square", %{"col" => col, "row" => row}, socket) do
    pos = {String.to_integer(row), String.to_integer(col)}

    cond do
      finished?(socket.assigns.game) ->
        {:noreply, assign(socket, :move_error, "A partida ja terminou.")}

      socket.assigns.pending_promotion != nil ->
        {:noreply, assign(socket, :move_error, "Escolha se deseja promover antes de continuar.")}

      socket.assigns.selected_drop != nil ->
        %{type: type} = socket.assigns.selected_drop
        {:noreply, drop_piece(socket, type, pos)}

      true ->
        clicked_piece = Board.get(socket.assigns.game.board, pos)

        case socket.assigns.selected do
          nil ->
            select_square(socket, pos, clicked_piece)

          from ->
            if own_piece?(clicked_piece, socket.assigns.side) do
              select_square(socket, pos, clicked_piece)
            else
              {:noreply, move_piece(socket, from, pos)}
            end
        end
    end
  end

  @impl true
  def handle_event("confirm_promotion", %{"promote" => promote}, socket) do
    promote? = promote == "true"

    if finished?(socket.assigns.game) do
      {:noreply, assign(socket, :move_error, "A partida ja terminou.")}
    else
      case socket.assigns.pending_promotion do
        %{from: from, to: to} ->
          {:noreply, execute_move(socket, from, to, promote?)}

        nil ->
          {:noreply, assign(socket, :move_error, "Nao ha promocao pendente.")}
      end
    end
  end

  @impl true
  def handle_event("request_resign", _params, socket) do
    if can_resign?(socket.assigns.game, socket.assigns.side) do
      {:noreply, assign(socket, :confirm_resign, true)}
    else
      {:noreply, assign(socket, :move_error, "Nao e possivel desistir agora.")}
    end
  end

  def handle_event("cancel_resign", _params, socket) do
    {:noreply, assign(socket, :confirm_resign, false)}
  end

  def handle_event("confirm_resign", _params, socket) do
    case Server.resign(socket.assigns.game_id, socket.assigns.player_id) do
      {:ok, game} ->
        {:noreply,
         socket
         |> clear_interaction()
         |> assign(:game, game)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:confirm_resign, false)
         |> assign(:move_error, error_text(reason))}
    end
  end

  @impl true
  def handle_info(:clock_tick, socket) do
    if socket.assigns.game.phase == :playing do
      {:noreply, assign_game(socket, Server.state(socket.assigns.game_id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:game_updated, game}, socket) do
    {:noreply, assign_game(socket, game)}
  end

  def handle_info({:game_started, game}, socket) do
    {:noreply, assign_game(socket, game)}
  end

  def handle_info({:game_over, _info}, socket) do
    {:noreply, assign_game(socket, Server.state(socket.assigns.game_id))}
  end

  defp start_game(game_id) do
    case DynamicSupervisor.start_child(Shogi.Game.Supervisor, {Server, game_id: game_id}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
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
         |> assign(:selected_drop, nil)
         |> assign(:pending_promotion, nil)
         |> assign(:move_error, nil)}
    end
  end

  defp move_piece(socket, from, to) when from == to do
    socket
    |> assign(:selected, nil)
    |> assign(:move_error, nil)
  end

  defp move_piece(socket, from, to) do
    board = socket.assigns.game.board
    side = socket.assigns.side
    piece = Board.get(board, from)

    cond do
      not Rules.valid_move?(board, from, to, side) ->
        execute_move(socket, from, to, false)

      Board.must_promote?(piece, to, side) ->
        execute_move(socket, from, to, true)

      Board.can_promote?(piece, from, to) ->
        socket
        |> assign(:selected, nil)
        |> assign(:selected_drop, nil)
        |> assign(:pending_promotion, %{from: from, to: to, piece: piece})
        |> assign(:move_error, nil)

      true ->
        execute_move(socket, from, to, false)
    end
  end

  defp execute_move(socket, from, to, promote?) do
    case Server.move(socket.assigns.game_id, socket.assigns.player_id, from, to,
           promote: promote?
         ) do
      {:ok, _game} ->
        socket
        |> clear_interaction()
        |> assign(:game, Server.state(socket.assigns.game_id))

      {:error, reason} ->
        socket
        |> assign(:selected, nil)
        |> assign(:pending_promotion, nil)
        |> assign(:move_error, error_text(reason))
        |> assign(:game, Server.state(socket.assigns.game_id))
    end
  end

  defp drop_piece(socket, type, to) do
    case Server.drop(socket.assigns.game_id, socket.assigns.player_id, type, to) do
      {:ok, _game} ->
        socket
        |> clear_interaction()
        |> assign(:game, Server.state(socket.assigns.game_id))

      {:error, reason} ->
        socket
        |> assign(:move_error, error_text(reason))
        |> assign(:game, Server.state(socket.assigns.game_id))
    end
  end

  defp validate_drop_selection(socket, type, side) do
    cond do
      finished?(socket.assigns.game) -> {:error, :game_finished}
      socket.assigns.player_id == nil -> {:error, :not_a_player}
      side != socket.assigns.side -> {:error, :not_your_piece}
      side != socket.assigns.game.turn -> {:error, :not_your_turn}
      type not in socket.assigns.game.board.hands[side] -> {:error, :piece_not_in_hand}
      true -> :ok
    end
  end

  defp clear_interaction(socket) do
    socket
    |> assign(:selected, nil)
    |> assign(:selected_drop, nil)
    |> assign(:pending_promotion, nil)
    |> assign(:confirm_resign, false)
    |> assign(:move_error, nil)
  end

  defp assign_game(socket, %{phase: :finished} = game) do
    socket
    |> clear_interaction()
    |> assign(:game, game)
  end

  defp assign_game(socket, game), do: assign(socket, :game, game)

  defp ensure_game_active(socket) do
    if finished?(socket.assigns.game), do: {:error, :game_finished}, else: :ok
  end

  defp finished?(%{phase: :finished}), do: true
  defp finished?(%{winner: winner}) when winner != nil, do: true
  defp finished?(_game), do: false

  defp can_resign?(%{phase: :playing}, side) when side in [:sente, :gote], do: true
  defp can_resign?(_game, _side), do: false

  defp side_for_player(%{players: %{sente: player_id}}, player_id) when is_binary(player_id),
    do: :sente

  defp side_for_player(%{players: %{gote: player_id}}, player_id) when is_binary(player_id),
    do: :gote

  defp side_for_player(_game, _player_id), do: nil

  defp session_player_id(%{"player_id" => player_id}), do: player_id
  defp session_player_id(%{player_id: player_id}), do: player_id
  defp session_player_id(_session), do: nil

  defp own_piece?(%{owner: owner}, side), do: owner == side
  defp own_piece?(_, _side), do: false

  defp square_status(selected, last_move, pos) do
    cond do
      selected == pos -> "selected"
      last_move_highlight?(last_move, pos) -> "last-move"
      true -> nil
    end
  end

  defp selected_drop_class(%{selected_drop: %{type: type, owner: owner}}, type, owner),
    do: "selected-drop"

  defp selected_drop_class(_assigns, _type, _owner), do: nil

  defp board_rows(:gote), do: 8..0//-1
  defp board_rows(_side), do: 0..8

  defp board_cols(:gote), do: 8..0//-1
  defp board_cols(_side), do: 0..8

  defp piece_orientation_class(%{owner: owner}, viewer_side) do
    if owner == viewer_side_or_default(viewer_side), do: "own-piece", else: "opponent-piece"
  end

  defp viewer_side_or_default(nil), do: :sente
  defp viewer_side_or_default(side), do: side

  defp top_side(:sente), do: :gote
  defp top_side(:gote), do: :sente
  defp top_side(_side), do: :gote

  defp bottom_side(:sente), do: :sente
  defp bottom_side(:gote), do: :gote
  defp bottom_side(_side), do: :sente

  defp format_clock(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  defp format_clock(_seconds), do: "--:--"

  defp clock_class(game, side) do
    seconds = get_in(game, [:clocks, side]) || 0

    [
      "clock",
      game.turn == side and game.phase == :playing && "active",
      seconds <= 10 && "low-time"
    ]
  end

  defp hand_sections(%{board: board}, :gote) do
    [
      %{title: "Sua mao", side: :gote, pieces: board.hands.gote, clickable?: true},
      %{title: "Mao do adversario", side: :sente, pieces: board.hands.sente, clickable?: false}
    ]
  end

  defp hand_sections(%{board: board}, :sente) do
    [
      %{title: "Sua mao", side: :sente, pieces: board.hands.sente, clickable?: true},
      %{title: "Mao do adversario", side: :gote, pieces: board.hands.gote, clickable?: false}
    ]
  end

  defp hand_sections(%{board: board}, _side) do
    [
      %{title: "Sente", side: :sente, pieces: board.hands.sente, clickable?: false},
      %{title: "Gote", side: :gote, pieces: board.hands.gote, clickable?: false}
    ]
  end

  defp last_move_highlight?({:move, from, to, _promote, _captured}, pos), do: pos in [from, to]
  defp last_move_highlight?({:drop, _type, to}, pos), do: pos == to
  defp last_move_highlight?(_, _pos), do: false

  defp parse_side("sente"), do: {:ok, :sente}
  defp parse_side("gote"), do: {:ok, :gote}
  defp parse_side(_side), do: :error

  defp parse_piece_type("pawn"), do: {:ok, :pawn}
  defp parse_piece_type("lance"), do: {:ok, :lance}
  defp parse_piece_type("knight"), do: {:ok, :knight}
  defp parse_piece_type("silver"), do: {:ok, :silver}
  defp parse_piece_type("gold"), do: {:ok, :gold}
  defp parse_piece_type("bishop"), do: {:ok, :bishop}
  defp parse_piece_type("rook"), do: {:ok, :rook}
  defp parse_piece_type(_type), do: :error

  defp side_label(:sente), do: "Sente"
  defp side_label(:gote), do: "Gote"
  defp side_label(nil), do: "Nao entrou"
  defp side_label(side), do: inspect(side)

  defp phase_label(:waiting), do: "Aguardando jogadores"
  defp phase_label(:playing), do: "Em jogo"
  defp phase_label(:finished), do: "Finalizada"
  defp phase_label(phase), do: inspect(phase)

  defp time_control_label(%{time_control: %{label: label}}), do: label
  defp time_control_label(_game), do: "10 + 2"

  defp selected_label(nil), do: "Nenhuma"
  defp selected_label({row, col}), do: "row #{row}, col #{col}"

  defp result_title(game, viewer_side) do
    cond do
      game.winner == nil -> "Partida finalizada"
      viewer_side == nil -> "#{side_label(game.winner)} venceu"
      game.winner == viewer_side -> "Voce venceu!"
      true -> "Voce perdeu."
    end
  end

  defp result_reason(%{result_reason: :checkmate}, _viewer_side), do: "Vitoria por xeque-mate."

  defp result_reason(%{result_reason: :resignation, resigned_by: resigned_by}, viewer_side) do
    cond do
      resigned_by == viewer_side -> "Voce desistiu."
      viewer_side in [:sente, :gote] -> "O adversario desistiu."
      true -> "#{side_label(resigned_by)} desistiu."
    end
  end

  defp result_reason(
         %{result_reason: :timeout, timed_out_side: timed_out_side, winner: winner},
         viewer_side
       ) do
    cond do
      timed_out_side == viewer_side -> "Voce perdeu por tempo."
      winner == viewer_side -> "Voce venceu por tempo."
      true -> "#{side_label(timed_out_side)} perdeu por tempo."
    end
  end

  defp result_reason(_game, _viewer_side), do: "Partida finalizada."

  defp error_text(:game_not_found), do: "Essa partida expirou."
  defp error_text(:side_taken), do: "Esse lado ja esta ocupado."
  defp error_text(:already_joined), do: "Voce ja entrou nesta partida."
  defp error_text(:game_not_waiting), do: "A partida ja comecou."
  defp error_text(:game_not_started), do: "A partida ainda nao comecou."
  defp error_text(:game_finished), do: "A partida ja terminou."
  defp error_text(:game_already_finished), do: "A partida ja terminou."
  defp error_text(:cannot_resign), do: "Nao e possivel desistir agora."
  defp error_text(:not_your_turn), do: "Nao e o seu turno."
  defp error_text(:not_your_piece), do: "Essa peca nao e sua."
  defp error_text(:not_a_player), do: "Entre como Sente ou Gote antes de jogar."
  defp error_text(:invalid_move), do: "Movimento invalido."
  defp error_text(:illegal_move), do: "Movimento invalido."
  defp error_text(:no_piece), do: "Nao existe peca na origem."
  defp error_text(:invalid_position), do: "Casa fora do tabuleiro."
  defp error_text(:own_piece_on_destination), do: "O destino tem uma peca sua."
  defp error_text(:blocked_by_own_piece), do: "O destino tem uma peca sua."
  defp error_text(:square_occupied), do: "Essa casa esta ocupada."
  defp error_text(:occupied), do: "Essa casa esta ocupada."
  defp error_text(:path_blocked), do: "Ha uma peca bloqueando o caminho."
  defp error_text(:invalid_drop), do: "Voce nao pode colocar essa peca ai."
  defp error_text(:piece_not_in_hand), do: "Essa peca nao esta na sua mao."
  defp error_text(:nifu), do: "Voce ja tem um peao nao promovido nessa coluna."
  defp error_text(:stuck_piece), do: "Essa peca nao teria movimentos nessa casa."
  defp error_text(:must_promote), do: "Essa peca precisa promover."
  defp error_text(:invalid_promotion), do: "Essa peca nao pode promover nessa jogada."
  defp error_text(reason), do: "Jogada invalida: #{inspect(reason)}"

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
