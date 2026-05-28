defmodule Shogi.Game.RulesTest do
  use ExUnit.Case, async: true

  alias Shogi.Game.{Board, Rules}

  test "sente pawn moves upward and gote pawn moves downward" do
    board = Board.new()

    assert Rules.valid_move?(board, {6, 4}, {5, 4}, :sente)
    refute Rules.valid_move?(board, {6, 4}, {7, 4}, :sente)

    assert Rules.valid_move?(board, {2, 4}, {3, 4}, :gote)
    refute Rules.valid_move?(board, {2, 4}, {1, 4}, :gote)
  end

  test "rook and bishop cannot pass through pieces" do
    board = Board.new()

    refute Rules.valid_move?(board, {1, 1}, {4, 1}, :gote)
    refute Rules.valid_move?(board, {1, 7}, {3, 5}, :gote)
  end

  test "cannot move opponent piece or capture own piece" do
    board = Board.new()

    refute Rules.valid_move?(board, {2, 4}, {3, 4}, :sente)
    refute Rules.valid_move?(board, {8, 3}, {8, 4}, :sente)
  end

  test "silver movement keeps direction-specific diagonals" do
    board = %{
      squares: %{
        {8, 4} => %{type: :king, owner: :sente},
        {0, 4} => %{type: :king, owner: :gote},
        {4, 4} => %{type: :silver, owner: :sente},
        {3, 6} => %{type: :silver, owner: :gote}
      },
      hands: %{sente: [], gote: []}
    }

    assert Rules.valid_move?(board, {4, 4}, {3, 4}, :sente)
    assert Rules.valid_move?(board, {4, 4}, {5, 3}, :sente)
    refute Rules.valid_move?(board, {4, 4}, {5, 4}, :sente)

    assert Rules.valid_move?(board, {3, 6}, {4, 6}, :gote)
    assert Rules.valid_move?(board, {3, 6}, {2, 5}, :gote)
    refute Rules.valid_move?(board, {3, 6}, {2, 6}, :gote)
  end

  test "movement that leaves own king in check is invalid" do
    board = %{
      squares: %{
        {8, 4} => %{type: :king, owner: :sente},
        {0, 0} => %{type: :king, owner: :gote},
        {0, 4} => %{type: :rook, owner: :gote},
        {7, 4} => %{type: :gold, owner: :sente}
      },
      hands: %{sente: [], gote: []}
    }

    refute Rules.valid_move?(board, {7, 4}, {7, 5}, :sente)
  end

  test "drop validation requires empty legal square and removes no-nifu columns" do
    board = %{Board.new() | hands: %{sente: [:pawn, :knight], gote: []}}

    refute Rules.valid_drop?(board, :pawn, {4, 4}, :sente)
    refute Rules.valid_drop?(board, :pawn, {0, 0}, :sente)
    refute Rules.valid_drop?(board, :knight, {1, 4}, :sente)

    board_without_file_pawn = %{board | squares: Map.delete(board.squares, {6, 4})}
    assert Rules.valid_drop?(board_without_file_pawn, :pawn, {4, 4}, :sente)
  end
end
