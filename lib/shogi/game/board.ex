defmodule Shogi.Game.Board do
  @size 9

  @type position :: {1..9, 1..9}
  @type piece :: %{type: atom(), owner: :sente | :gote}
  @type t :: %{position() => piece()}

  def new do
    %{}
    |> place_back_rank(:gote, 1)
    |> place_pawns(:gote, 3)
    |> place_pawns(:sente, 7)
    |> place_back_rank(:sente, 9)
  end

  def get(board, pos), do: Map.get(board, pos)

  def move(board, from, to) do
    case Map.get(board, from) do
      nil -> {:error, :no_piece}
      piece ->
        board
        |> Map.delete(from)
        |> Map.put(to, piece)
        |> then(&{:ok, &1})
    end
  end

  defp place_pawns(board, owner, row) do
    Enum.reduce(1..@size, board, fn col, acc ->
      Map.put(acc, {col, row}, %{type: :pawn, owner: owner})
    end)
  end

  defp place_back_rank(board, owner, row) do
    pieces = [:lance, :knight, :silver, :gold, :king, :gold, :silver, :knight, :lance]
    pieces
    |> Enum.with_index(1)
    |> Enum.reduce(board, fn {type, col}, acc ->
      Map.put(acc, {col, row}, %{type: type, owner: owner})
    end)
  end
end
