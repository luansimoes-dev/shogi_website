defmodule Shogi.Game.BoardTest do
  use ExUnit.Case, async: true

  alias Shogi.Game.Board

  test "initial board uses 9x9 coordinates and has 40 pieces" do
    board = Board.new()

    assert Enum.count(board.squares) == 40

    assert Enum.all?(Map.keys(board.squares), fn {row, col} ->
             row in 0..8 and col in 0..8
           end)

    assert Board.get_piece(board, {4, 4}) == nil
  end

  test "initial major pieces are in correct shogi positions" do
    board = Board.new()

    assert Board.get_piece(board, {1, 1}) == %{type: :rook, owner: :gote}
    assert Board.get_piece(board, {1, 7}) == %{type: :bishop, owner: :gote}
    assert Board.get_piece(board, {7, 1}) == %{type: :bishop, owner: :sente}
    assert Board.get_piece(board, {7, 7}) == %{type: :rook, owner: :sente}
    assert Board.get_piece(board, {0, 4}) == %{type: :king, owner: :gote}
    assert Board.get_piece(board, {8, 4}) == %{type: :king, owner: :sente}
  end

  test "initial pawns fill gote and sente pawn rows" do
    board = Board.new()

    for col <- 0..8 do
      assert Board.get_piece(board, {2, col}) == %{type: :pawn, owner: :gote}
      assert Board.get_piece(board, {6, col}) == %{type: :pawn, owner: :sente}
    end
  end

  test "capture adds an unpromoted piece to captor hand" do
    board = %{
      squares: %{
        {8, 4} => %{type: :king, owner: :sente},
        {0, 4} => %{type: :king, owner: :gote},
        {4, 4} => %{type: :rook, owner: :sente},
        {4, 6} => %{type: :promoted_pawn, owner: :gote}
      },
      hands: %{sente: [], gote: []}
    }

    assert {:ok, new_board, :pawn} = Board.move(board, {4, 4}, {4, 6})
    assert Board.get_piece(new_board, {4, 6}) == %{type: :rook, owner: :sente}
    assert :pawn in new_board.hands.sente
  end

  test "drop removes piece from hand" do
    board = %{Board.new() | hands: %{sente: [:pawn], gote: []}}

    assert {:ok, new_board} = Board.drop(board, :pawn, {4, 4}, :sente)
    assert Board.get_piece(new_board, {4, 4}) == %{type: :pawn, owner: :sente}
    assert new_board.hands.sente == []
  end

  test "optional promotion is only allowed when moving from or into promotion zone" do
    board = %{
      squares: %{
        {8, 4} => %{type: :king, owner: :sente},
        {0, 4} => %{type: :king, owner: :gote},
        {5, 4} => %{type: :pawn, owner: :sente},
        {3, 6} => %{type: :pawn, owner: :sente}
      },
      hands: %{sente: [], gote: []}
    }

    assert {:error, :invalid_promotion} = Board.move(board, {5, 4}, {4, 4}, true)
    assert {:ok, promoted_board, nil} = Board.move(board, {3, 6}, {2, 6}, true)
    assert Board.get_piece(promoted_board, {2, 6}) == %{type: :promoted_pawn, owner: :sente}
  end
end
