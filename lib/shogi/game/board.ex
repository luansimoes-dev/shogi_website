defmodule Shogi.Game.Board do
  @size 9
  @range 0..8

  @type player :: :sente | :gote
  @type position :: {0..8, 0..8}

  @type piece_type ::
          :king
          | :rook
          | :bishop
          | :gold
          | :silver
          | :knight
          | :lance
          | :pawn
          | :promoted_rook
          | :promoted_bishop
          | :promoted_silver
          | :promoted_knight
          | :promoted_lance
          | :promoted_pawn

  @type piece :: %{
          type: piece_type(),
          owner: player()
        }

  @type t :: %{
          squares: %{position() => piece()},
          hands: %{sente: [piece_type()], gote: [piece_type()]}
        }

  def new do
    squares =
      %{}
      |> place_back_rank(:gote, 0)
      |> place_special(:gote, 1)
      |> place_pawns(:gote, 2)
      |> place_pawns(:sente, 6)
      |> place_special(:sente, 7)
      |> place_back_rank(:sente, 8)

    %{
      squares: squares,
      hands: %{sente: [], gote: []}
    }
  end

  def size, do: @size
  def rows, do: @range
  def cols, do: @range

  def get(%{squares: squares}, pos), do: Map.get(squares, pos)
  def get_piece(board, pos), do: get(board, pos)

  def empty?(board, pos), do: is_nil(get(board, pos))
  def occupied?(board, pos), do: not empty?(board, pos)

  def inside?({row, col}) do
    row in @range and col in @range
  end

  def inside?(_pos), do: false

  def move(board, from, to, promote? \\ false) do
    with :ok <- validate_position(from),
         :ok <- validate_position(to),
         {:ok, piece} <- fetch_piece(board, from),
         :ok <- validate_destination(board, to, piece.owner),
         :ok <- validate_promotion(piece, from, to, promote?) do
      {board_after_capture, captured} = maybe_capture(board, to, piece.owner)

      moved_piece =
        if promote? or must_promote?(piece, to, piece.owner) do
          promote(piece)
        else
          piece
        end

      new_squares =
        board_after_capture.squares
        |> Map.delete(from)
        |> Map.put(to, moved_piece)

      {:ok, %{board_after_capture | squares: new_squares}, captured}
    end
  end

  def drop(board, type, to, player) do
    with :ok <- validate_position(to),
         :ok <- validate_empty(board, to),
         :ok <- validate_piece_in_hand(board, type, player) do
      new_hand = List.delete(board.hands[player], type)
      new_squares = Map.put(board.squares, to, %{type: type, owner: player})
      new_hands = Map.put(board.hands, player, new_hand)

      {:ok, %{board | squares: new_squares, hands: new_hands}}
    end
  end

  def pieces_of(board, player) do
    Enum.filter(board.squares, fn {_pos, piece} -> piece.owner == player end)
  end

  def king_position(board, player) do
    case Enum.find(board.squares, fn {_pos, piece} ->
           piece.type == :king and piece.owner == player
         end) do
      {pos, _piece} -> {:ok, pos}
      nil -> {:error, :king_not_found}
    end
  end

  def in_promotion_zone?({row, _col}, :sente), do: row in 0..2
  def in_promotion_zone?({row, _col}, :gote), do: row in 6..8

  def must_promote?(%{type: type}, {0, _col}, :sente) when type in [:pawn, :lance], do: true
  def must_promote?(%{type: :knight}, {row, _col}, :sente) when row in 0..1, do: true
  def must_promote?(%{type: type}, {8, _col}, :gote) when type in [:pawn, :lance], do: true
  def must_promote?(%{type: :knight}, {row, _col}, :gote) when row in 7..8, do: true
  def must_promote?(_piece, _to, _player), do: false

  def promotable?(%{type: type}), do: promotable?(type)
  def promotable?(type), do: type in [:pawn, :lance, :knight, :silver, :bishop, :rook]

  def can_promote?(piece, from, to) do
    promotable?(piece) and
      (in_promotion_zone?(from, piece.owner) or in_promotion_zone?(to, piece.owner))
  end

  def opponent(:sente), do: :gote
  def opponent(:gote), do: :sente

  def unpromote(:promoted_pawn), do: :pawn
  def unpromote(:promoted_lance), do: :lance
  def unpromote(:promoted_knight), do: :knight
  def unpromote(:promoted_silver), do: :silver
  def unpromote(:promoted_bishop), do: :bishop
  def unpromote(:promoted_rook), do: :rook
  def unpromote(type), do: type

  def promote(%{type: type, owner: owner}) do
    %{type: promoted_type(type), owner: owner}
  end

  defp fetch_piece(board, pos) do
    case get(board, pos) do
      nil -> {:error, :no_piece}
      piece -> {:ok, piece}
    end
  end

  defp validate_position(pos) do
    if inside?(pos), do: :ok, else: {:error, :invalid_position}
  end

  defp validate_empty(board, pos) do
    if empty?(board, pos), do: :ok, else: {:error, :square_occupied}
  end

  defp validate_destination(board, to, player) do
    case get(board, to) do
      nil -> :ok
      %{owner: ^player} -> {:error, :own_piece_on_destination}
      %{owner: _enemy} -> :ok
    end
  end

  defp validate_promotion(_piece, _from, _to, false), do: :ok

  defp validate_promotion(piece, from, to, true) do
    if can_promote?(piece, from, to), do: :ok, else: {:error, :invalid_promotion}
  end

  defp validate_piece_in_hand(board, type, player) do
    if type in board.hands[player], do: :ok, else: {:error, :piece_not_in_hand}
  end

  defp maybe_capture(board, to, captor) do
    case get(board, to) do
      nil ->
        {board, nil}

      %{type: type} ->
        base_type = unpromote(type)
        new_hands = Map.update!(board.hands, captor, &[base_type | &1])
        {%{board | hands: new_hands}, base_type}
    end
  end

  defp promoted_type(:pawn), do: :promoted_pawn
  defp promoted_type(:lance), do: :promoted_lance
  defp promoted_type(:knight), do: :promoted_knight
  defp promoted_type(:silver), do: :promoted_silver
  defp promoted_type(:bishop), do: :promoted_bishop
  defp promoted_type(:rook), do: :promoted_rook
  defp promoted_type(type), do: type

  defp place_pawns(squares, owner, row) do
    Enum.reduce(@range, squares, fn col, acc ->
      Map.put(acc, {row, col}, %{type: :pawn, owner: owner})
    end)
  end

  defp place_back_rank(squares, owner, row) do
    [:lance, :knight, :silver, :gold, :king, :gold, :silver, :knight, :lance]
    |> Enum.with_index(0)
    |> Enum.reduce(squares, fn {type, col}, acc ->
      Map.put(acc, {row, col}, %{type: type, owner: owner})
    end)
  end

  defp place_special(squares, :gote, row) do
    squares
    |> Map.put({row, 1}, %{type: :rook, owner: :gote})
    |> Map.put({row, 7}, %{type: :bishop, owner: :gote})
  end

  defp place_special(squares, :sente, row) do
    squares
    |> Map.put({row, 1}, %{type: :bishop, owner: :sente})
    |> Map.put({row, 7}, %{type: :rook, owner: :sente})
  end
end
