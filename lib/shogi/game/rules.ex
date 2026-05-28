defmodule Shogi.Game.Rules do
  alias Shogi.Game.Board

  def valid_move?(board, from, to, player) do
    with :ok <- valid_position?(from),
         :ok <- valid_position?(to),
         {:ok, piece} <- get_piece(board, from),
         :ok <- owns_piece?(piece, player),
         :ok <- valid_destination?(board, to, player),
         :ok <- piece_can_reach?(board, piece, from, to),
         :ok <- king_safe_after_move?(board, from, to, player) do
      true
    else
      _ -> false
    end
  end

  def valid_drop?(board, type, to, player) do
    with :ok <- valid_position?(to),
         :ok <- piece_in_hand?(board, type, player),
         :ok <- square_empty?(board, to),
         :ok <- no_nifu?(board, type, to, player),
         :ok <- not_stuck?(type, to, player),
         :ok <- king_safe_after_drop?(board, type, to, player) do
      # TODO: proibir uchifuzume (mate imediato por drop de peao).
      true
    else
      _ -> false
    end
  end

  def checkmate?(board, player) do
    in_check?(board, player) and no_legal_moves?(board, player)
  end

  def in_check?(board, player) do
    case Board.king_position(board, player) do
      {:ok, king_pos} -> square_attacked_by?(board, king_pos, Board.opponent(player))
      {:error, _} -> false
    end
  end

  defp valid_position?(pos) do
    if Board.inside?(pos), do: :ok, else: {:error, :invalid_position}
  end

  defp get_piece(board, pos) do
    case Board.get(board, pos) do
      nil -> {:error, :no_piece}
      piece -> {:ok, piece}
    end
  end

  defp owns_piece?(%{owner: owner}, player) when owner == player, do: :ok
  defp owns_piece?(_, _player), do: {:error, :not_your_piece}

  defp valid_destination?(board, to, player) do
    case Board.get(board, to) do
      %{owner: ^player} -> {:error, :blocked_by_own_piece}
      _ -> :ok
    end
  end

  defp square_empty?(board, to) do
    if Board.empty?(board, to), do: :ok, else: {:error, :square_occupied}
  end

  defp piece_in_hand?(board, type, player) do
    if type in board.hands[player], do: :ok, else: {:error, :piece_not_in_hand}
  end

  defp king_safe_after_move?(board, from, to, player) do
    case Board.move(board, from, to) do
      {:ok, new_board, _captured} ->
        if in_check?(new_board, player), do: {:error, :king_in_check}, else: :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp king_safe_after_drop?(board, type, to, player) do
    case Board.drop(board, type, to, player) do
      {:ok, new_board} ->
        if in_check?(new_board, player), do: {:error, :king_in_check}, else: :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp piece_can_reach?(_board, %{type: :pawn, owner: :sente}, {row, col}, {to_row, col})
       when to_row == row - 1,
       do: :ok

  defp piece_can_reach?(_board, %{type: :pawn, owner: :gote}, {row, col}, {to_row, col})
       when to_row == row + 1,
       do: :ok

  defp piece_can_reach?(board, %{type: :lance, owner: :sente}, {row, col}, {to_row, col})
       when to_row < row do
    clear_path?(board, {row, col}, {to_row, col})
  end

  defp piece_can_reach?(board, %{type: :lance, owner: :gote}, {row, col}, {to_row, col})
       when to_row > row do
    clear_path?(board, {row, col}, {to_row, col})
  end

  defp piece_can_reach?(_board, %{type: :knight, owner: :sente}, {row, col}, {to_row, to_col})
       when to_row == row - 2 and abs(to_col - col) == 1,
       do: :ok

  defp piece_can_reach?(_board, %{type: :knight, owner: :gote}, {row, col}, {to_row, to_col})
       when to_row == row + 2 and abs(to_col - col) == 1,
       do: :ok

  defp piece_can_reach?(_board, %{type: :silver, owner: :sente}, from, to) do
    if delta(from, to) in [{-1, 0}, {-1, -1}, {-1, 1}, {1, -1}, {1, 1}],
      do: :ok,
      else: {:error, :invalid_move}
  end

  defp piece_can_reach?(_board, %{type: :silver, owner: :gote}, from, to) do
    if delta(from, to) in [{1, 0}, {1, -1}, {1, 1}, {-1, -1}, {-1, 1}],
      do: :ok,
      else: {:error, :invalid_move}
  end

  defp piece_can_reach?(_board, %{type: type, owner: owner}, from, to)
       when type in [:gold, :promoted_pawn, :promoted_lance, :promoted_knight, :promoted_silver] do
    gold_move?(owner, from, to)
  end

  defp piece_can_reach?(board, %{type: :bishop}, from, to) do
    {dr, dc} = abs_delta(from, to)

    if dr == dc and dr > 0,
      do: clear_path?(board, from, to),
      else: {:error, :invalid_move}
  end

  defp piece_can_reach?(board, %{type: :rook}, from, to) do
    case delta(from, to) do
      {0, dc} when dc != 0 -> clear_path?(board, from, to)
      {dr, 0} when dr != 0 -> clear_path?(board, from, to)
      _ -> {:error, :invalid_move}
    end
  end

  defp piece_can_reach?(_board, %{type: :king}, from, to) do
    {dr, dc} = abs_delta(from, to)

    if dr <= 1 and dc <= 1 and {dr, dc} != {0, 0},
      do: :ok,
      else: {:error, :invalid_move}
  end

  defp piece_can_reach?(board, %{type: :promoted_bishop}, from, to) do
    {dr, dc} = abs_delta(from, to)

    cond do
      dr == dc and dr > 0 -> clear_path?(board, from, to)
      dr <= 1 and dc <= 1 and {dr, dc} != {0, 0} -> :ok
      true -> {:error, :invalid_move}
    end
  end

  defp piece_can_reach?(board, %{type: :promoted_rook}, from, to) do
    {dr, dc} = abs_delta(from, to)

    cond do
      elem(delta(from, to), 0) == 0 and dc > 0 -> clear_path?(board, from, to)
      elem(delta(from, to), 1) == 0 and dr > 0 -> clear_path?(board, from, to)
      dr == 1 and dc == 1 -> :ok
      true -> {:error, :invalid_move}
    end
  end

  defp piece_can_reach?(_board, _piece, _from, _to), do: {:error, :invalid_move}

  defp gold_move?(:sente, from, to) do
    if delta(from, to) in [{-1, 0}, {-1, -1}, {-1, 1}, {0, -1}, {0, 1}, {1, 0}],
      do: :ok,
      else: {:error, :invalid_move}
  end

  defp gold_move?(:gote, from, to) do
    if delta(from, to) in [{1, 0}, {1, -1}, {1, 1}, {0, -1}, {0, 1}, {-1, 0}],
      do: :ok,
      else: {:error, :invalid_move}
  end

  defp clear_path?(_board, from, to) when from == to, do: {:error, :invalid_move}

  defp clear_path?(board, {row, col}, {to_row, to_col}) do
    row_step = step(to_row - row)
    col_step = step(to_col - col)
    distance = max(abs(to_row - row), abs(to_col - col))

    blocked? =
      if distance <= 1 do
        false
      else
        1..(distance - 1)//1
        |> Enum.any?(fn index ->
          Board.get(board, {row + row_step * index, col + col_step * index}) != nil
        end)
      end

    if blocked?, do: {:error, :path_blocked}, else: :ok
  end

  defp step(value) when value > 0, do: 1
  defp step(value) when value < 0, do: -1
  defp step(_value), do: 0

  defp delta({row, col}, {to_row, to_col}), do: {to_row - row, to_col - col}

  defp abs_delta(from, to) do
    {dr, dc} = delta(from, to)
    {abs(dr), abs(dc)}
  end

  defp no_nifu?(board, :pawn, {_row, col}, player) do
    has_pawn? =
      Enum.any?(Board.rows(), fn row ->
        case Board.get(board, {row, col}) do
          %{type: :pawn, owner: ^player} -> true
          _ -> false
        end
      end)

    if has_pawn?, do: {:error, :nifu}, else: :ok
  end

  defp no_nifu?(_board, _type, _to, _player), do: :ok

  defp not_stuck?(:pawn, {0, _col}, :sente), do: {:error, :stuck_piece}
  defp not_stuck?(:pawn, {8, _col}, :gote), do: {:error, :stuck_piece}
  defp not_stuck?(:lance, {0, _col}, :sente), do: {:error, :stuck_piece}
  defp not_stuck?(:lance, {8, _col}, :gote), do: {:error, :stuck_piece}
  defp not_stuck?(:knight, {row, _col}, :sente) when row in 0..1, do: {:error, :stuck_piece}
  defp not_stuck?(:knight, {row, _col}, :gote) when row in 7..8, do: {:error, :stuck_piece}
  defp not_stuck?(_type, _to, _player), do: :ok

  defp square_attacked_by?(board, target_pos, attacker) do
    Board.pieces_of(board, attacker)
    |> Enum.any?(fn {from, piece} ->
      valid_destination?(board, target_pos, attacker) == :ok and
        piece_can_reach?(board, piece, from, target_pos) == :ok
    end)
  end

  defp no_legal_moves?(board, player) do
    moves = all_possible_moves(board, player)
    drops = all_possible_drops(board, player)

    Enum.empty?(moves ++ drops)
  end

  defp all_possible_moves(board, player) do
    for {from, piece} <- Board.pieces_of(board, player),
        piece.owner == player,
        to <- all_squares(),
        valid_move?(board, from, to, player) do
      {:move, from, to}
    end
  end

  defp all_possible_drops(board, player) do
    for type <- Enum.uniq(board.hands[player]),
        to <- all_squares(),
        valid_drop?(board, type, to, player) do
      {:drop, type, to}
    end
  end

  defp all_squares do
    for row <- Board.rows(), col <- Board.cols(), do: {row, col}
  end
end
