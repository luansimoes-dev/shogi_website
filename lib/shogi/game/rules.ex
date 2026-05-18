defmodule Shogi.Game.Rules do
  alias Shogi.Game.Board

  # =====================================================================
  # API pública
  # =====================================================================

  def valid_move?(board, from, to, player) do
    with {:ok, piece} <- get_piece(board, from),
         :ok <- owns_piece?(piece, player),
         :ok <- valid_destination?(board, to, player),
         :ok <- piece_can_reach?(board, piece, from, to) do
      true
    else
      _ -> false
    end
  end

  # Valida drop (colocar peça da mão no tabuleiro)
  def valid_drop?(board, type, to, player) do
    with :ok <- square_empty?(board, to),
         :ok <- no_nifu?(board, type, to, player),
         :ok <- not_stuck?(type, to, player) do
      true
    else
      _ -> false
    end
  end

  # Modificado para API Pública: Usado pelo cálculo de Xeque-mate no fim do módulo
  def checkmate?(board, player) do
    in_check?(board, player) and no_legal_moves?(board, player)
  end

  # Modificado para API Pública: Usado pelo cálculo de Xeque-mate no fim do módulo
  def in_check?(board, player) do
    case Board.king_position(board, player) do
      {:ok, king_pos} -> square_attacked_by?(board, king_pos, opponent(player))
      {:error, _} -> false
    end
  end

  # =====================================================================
  # Guards privados básicos
  # =====================================================================

  defp get_piece(board, pos) do
    case Board.get(board, pos) do
      nil -> {:error, :no_piece}
      piece -> {:ok, piece}
    end
  end

  defp owns_piece?(%{owner: owner}, player) when owner == player, do: :ok
  defp owns_piece?(_, _), do: {:error, :not_your_piece}

  defp valid_destination?(board, to, player) do
    case Board.get(board, to) do
      %{owner: ^player} -> {:error, :blocked_by_own_piece}
      _ -> :ok
    end
  end

  defp square_empty?(board, to) do
    case Board.get(board, to) do
      nil -> :ok
      _ -> {:error, :square_occupied}
    end
  end

  # =====================================================================
  # Movimento por tipo de peça
  # Coordenadas: {col, row}, row 1 = topo (lado gote), row 9 = fundo (lado sente)
  # Sente avança diminuindo row; gote avança aumentando row
  # =====================================================================

  # — — — Peças de passo único — — —

  # Peão (fu): avança 1 casa
  defp piece_can_reach?(_board, %{type: :pawn, owner: :sente}, {c, r}, {c, r2})
       when r2 == r - 1,
       do: :ok

  defp piece_can_reach?(_board, %{type: :pawn, owner: :gote}, {c, r}, {c, r2})
       when r2 == r + 1,
       do: :ok

  # Lança (kyosha): avança várias casas em linha reta (sem obstáculos)
  defp piece_can_reach?(board, %{type: :lance, owner: :sente}, {c, r}, {c, r2})
       when r2 < r do
    check_clear_vertical(board, c, r2 + 1, r - 1)
  end

  defp piece_can_reach?(board, %{type: :lance, owner: :gote}, {c, r}, {c, r2})
       when r2 > r do
    check_clear_vertical(board, c, r + 1, r2 - 1)
  end

  # Cavalo (keima): movimento em L fixo (2 à frente, 1 lateral) — PULA peças
  defp piece_can_reach?(_board, %{type: :knight, owner: :sente}, {c, r}, {c2, r2})
       when r2 == r - 2 and abs(c2 - c) == 1,
       do: :ok

  defp piece_can_reach?(_board, %{type: :knight, owner: :gote}, {c, r}, {c2, r2})
       when r2 == r + 2 and abs(c2 - c) == 1,
       do: :ok

  # Prata (gin): 5 direções (frente, diagonais — inclui diagonais para trás)
  defp piece_can_reach?(_board, %{type: :silver, owner: :sente}, {c, r}, {c2, r2}) do
    dr = r2 - r
    dc = abs(c2 - c)

    if {dr, dc} in [{-1, 0}, {-1, 1}, {1, 1}, {1, -1}] or (dr == -1 and dc == 1) or
         (dr == 1 and dc == 1),
       do: :ok,
       else: {:error, :invalid_move}
  end

  defp piece_can_reach?(_board, %{type: :silver, owner: :gote}, {c, r}, {c2, r2}) do
    dr = r2 - r
    dc = abs(c2 - c)

    # espelha: "frente" para gote é dr positivo
    if {dr, dc} in [{1, 0}, {1, 1}, {-1, 1}] or (dr == 1 and dc == 1) or
         (dr == -1 and dc == 1),
       do: :ok,
       else: {:error, :invalid_move}
  end

  # Ouro (kin) + peças promovidas que movem como ouro
  defp piece_can_reach?(_board, %{type: type, owner: owner}, from, to)
       when type in [:gold, :promoted_pawn, :promoted_lance, :promoted_knight, :promoted_silver] do
    gold_move?(owner, from, to)
  end

  # Bispo (kaku): diagonal livre
  defp piece_can_reach?(board, %{type: :bishop}, {c, r}, {c2, r2}) do
    dr = abs(r2 - r)
    dc = abs(c2 - c)

    if dr == dc and dr > 0 do
      check_clear_diagonal(board, {c, r}, {c2, r2})
    else
      {:error, :invalid_move}
    end
  end

  # Torre (hisha): linha/coluna livre
  defp piece_can_reach?(board, %{type: :rook}, {c, r}, {c2, r2}) do
    cond do
      c == c2 and r != r2 -> check_clear_vertical(board, c, min(r, r2) + 1, max(r, r2) - 1)
      r == r2 and c != c2 -> check_clear_horizontal(board, r, min(c, c2) + 1, max(c, c2) - 1)
      true -> {:error, :invalid_move}
    end
  end

  # Rei (ou/gyoku): 1 casa em qualquer direção
  defp piece_can_reach?(_board, %{type: type}, {c, r}, {c2, r2})
       when type in [:king] do
    if abs(c2 - c) <= 1 and abs(r2 - r) <= 1 and {c, r} != {c2, r2},
      do: :ok,
      else: {:error, :invalid_move}
  end

  # Bispo promovido (ryuma): diagonal + 1 casa ortogonal
  defp piece_can_reach?(board, %{type: :promoted_bishop}, {c, r}, {c2, r2}) do
    dr = abs(r2 - r)
    dc = abs(c2 - c)

    cond do
      dr == dc and dr > 0 -> check_clear_diagonal(board, {c, r}, {c2, r2})
      # passo de rei
      dr <= 1 and dc <= 1 -> :ok
      true -> {:error, :invalid_move}
    end
  end

  # Torre promovida (ryuo): linha/coluna + 1 casa diagonal
  defp piece_can_reach?(board, %{type: :promoted_rook}, {c, r}, {c2, r2}) do
    dr = abs(r2 - r)
    dc = abs(c2 - c)

    cond do
      c == c2 and r != r2 -> check_clear_vertical(board, c, min(r, r2) + 1, max(r, r2) - 1)
      r == r2 and c != c2 -> check_clear_horizontal(board, r, min(c, c2) + 1, max(c, c2) - 1)
      # passo diagonal de rei
      dr == 1 and dc == 1 -> :ok
      true -> {:error, :invalid_move}
    end
  end

  # Fallthrough
  defp piece_can_reach?(_board, _piece, _from, _to), do: {:error, :invalid_move}

  # =====================================================================
  # Helpers de movimento
  # =====================================================================

  # Movimento de ouro — 6 direções (frente, lados, trás; sem diagonais traseiras)
  defp gold_move?(:sente, {c, r}, {c2, r2}) do
    delta = {r2 - r, c2 - c}

    if delta in [{-1, 0}, {0, -1}, {0, 1}, {1, 0}, {-1, -1}, {-1, 1}],
      do: :ok,
      else: {:error, :invalid_move}
  end

  defp gold_move?(:gote, {c, r}, {c2, r2}) do
    delta = {r2 - r, c2 - c}

    if delta in [{1, 0}, {0, -1}, {0, 1}, {-1, 0}, {1, -1}, {1, 1}],
      do: :ok,
      else: {:error, :invalid_move}
  end

  # Caminho livre em coluna entre row_min e row_max (inclusive)
  defp check_clear_vertical(_board, _c, row_min, row_max) when row_min > row_max, do: :ok

  defp check_clear_vertical(board, c, row_min, row_max) do
    blocked =
      Enum.any?(row_min..row_max, fn r ->
        Board.get(board, {c, r}) != nil
      end)

    if blocked, do: {:error, :path_blocked}, else: :ok
  end

  # Caminho livre em linha entre col_min e col_max (inclusive)
  defp check_clear_horizontal(_board, _r, col_min, col_max) when col_min > col_max, do: :ok

  defp check_clear_horizontal(board, r, col_min, col_max) do
    blocked =
      Enum.any?(col_min..col_max, fn c ->
        Board.get(board, {c, r}) != nil
      end)

    if blocked, do: {:error, :path_blocked}, else: :ok
  end

  # Caminho diagonal livre entre dois pontos
  defp check_clear_diagonal(board, {c, r}, {c2, r2}) do
    dc = if c2 > c, do: 1, else: -1
    dr = if r2 > r, do: 1, else: -1
    steps = abs(c2 - c) - 1

    blocked =
      Enum.any?(1..steps//1, fn i ->
        Board.get(board, {c + dc * i, r + dr * i}) != nil
      end)

    if blocked, do: {:error, :path_blocked}, else: :ok
  end

  # =====================================================================
  # Regras de drop
  # =====================================================================

  # Nifu: não pode ter dois peões na mesma coluna
  defp no_nifu?(board, :pawn, {c, _r}, player) do
    has_pawn =
      Enum.any?(1..9, fn r ->
        case Board.get(board, {c, r}) do
          %{type: :pawn, owner: ^player} -> true
          _ -> false
        end
      end)

    if has_pawn, do: {:error, :nifu}, else: :ok
  end

  defp no_nifu?(_board, _type, _to, _player), do: :ok

  # Peças que não podem ser dropadas em casas onde ficariam presas
  defp not_stuck?(:pawn, {_c, r}, :sente) when r == 1, do: {:error, :stuck_piece}
  defp not_stuck?(:pawn, {_c, r}, :gote) when r == 9, do: {:error, :stuck_piece}
  defp not_stuck?(:lance, {_c, r}, :sente) when r == 1, do: {:error, :stuck_piece}
  defp not_stuck?(:lance, {_c, r}, :gote) when r == 9, do: {:error, :stuck_piece}
  defp not_stuck?(:knight, {_c, r}, :sente) when r <= 2, do: {:error, :stuck_piece}
  defp not_stuck?(:knight, {_c, r}, :gote) when r >= 8, do: {:error, :stuck_piece}
  defp not_stuck?(_type, _to, _player), do: :ok

  # =====================================================================
  # Xeque e xeque-mate (Movidos para dentro do bloco do módulo)
  # =====================================================================

  # Verifica se uma casa está sob ataque de qualquer peça do atacante
  defp square_attacked_by?(board, target_pos, attacker) do
    Board.pieces_of(board, attacker)
    |> Enum.any?(fn {from, piece} ->
      piece_can_reach?(board, piece, from, target_pos) == :ok
    end)
  end

  # Testa todos os movimentos possíveis do jogador —
  # se nenhum tirar o rei do xeque, é xeque-mate
  defp no_legal_moves?(board, player) do
    moves = all_possible_moves(board, player)
    drops = all_possible_drops(board, player)

    Enum.all?(moves ++ drops, fn move ->
      case move do
        {:move, from, to} ->
          case Board.move(board, from, to) do
            {:ok, new_board, _captured} -> in_check?(new_board, player)
            # movimento inválido, ignora
            _ -> true
          end

        {:drop, type, to} ->
          case Board.drop(board, type, to, player) do
            {:ok, new_board} -> in_check?(new_board, player)
            _ -> true
          end
      end
    end)
  end

  defp all_possible_moves(board, player) do
    for {from, piece} <- Board.pieces_of(board, player),
        piece.owner == player,
        {col, row} <- all_squares(),
        valid_move?(board, from, {col, row}, player) do
      {:move, from, {col, row}}
    end
  end

  defp all_possible_drops(board, player) do
    hand = board.hands[player]

    for type <- Enum.uniq(hand),
        {col, row} <- all_squares(),
        valid_drop?(board, type, {col, row}, player) do
      {:drop, type, {col, row}}
    end
  end

  defp all_squares do
    for col <- 1..9, row <- 1..9, do: {col, row}
  end

  defp opponent(:sente), do: :gote
  defp opponent(:gote), do: :sente
end
