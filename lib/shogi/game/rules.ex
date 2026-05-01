defmodule Shogi.Game.Rules do
  alias Shogi.Game.Board

  def valid_move?(board, from, to, player) do
    with {:ok, piece} <- get_piece(board, from),
         :ok <- owns_piece?(piece, player),
         :ok <- valid_destination?(board, to, player),
         :ok <- piece_can_reach?(piece, from, to) do
      true
    else
      _ -> false
    end
  end

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

  # Movimento do peão — só avança 1 casa
  defp piece_can_reach?(%{type: :pawn, owner: :sente}, {c, r}, {c, r2}),
    do: if(r2 == r - 1, do: :ok, else: {:error, :invalid_move})

  defp piece_can_reach?(%{type: :pawn, owner: :gote}, {c, r}, {c, r2}),
    do: if(r2 == r + 1, do: :ok, else: {:error, :invalid_move})

  defp piece_can_reach?(_, _, _), do: {:error, :invalid_move}
end