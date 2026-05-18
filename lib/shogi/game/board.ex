defmodule Shogi.Game.Board do
  @size 9

  @type player :: :sente | :gote
  @type position :: {1..9, 1..9}

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

  # =====================================================================
  # Inicialização
  # =====================================================================

  def new do
    squares =
      %{}
      |> place_back_rank(:gote, 1)
      |> place_special(:gote, 2)
      |> place_pawns(:gote, 3)
      |> place_pawns(:sente, 7)
      |> place_special(:sente, 8)
      |> place_back_rank(:sente, 9)

    %{
      squares: squares,
      hands: %{sente: [], gote: []}
    }
  end

  # =====================================================================
  # API pública
  # =====================================================================

  def get(%{squares: squares}, pos), do: Map.get(squares, pos)

  def empty?(board, pos), do: is_nil(get(board, pos))

  def occupied?(board, pos), do: not empty?(board, pos)

  def inside?({col, row}) do
    col in 1..@size and row in 1..@size
  end

  def move(board, from, to, promote? \\ false) do
    with :ok <- validate_position(from),
         :ok <- validate_position(to),
         {:ok, piece} <- fetch_piece(board, from),
         :ok <- validate_destination(board, to, piece.owner) do
      {board_after_capture, captured} = maybe_capture(board, to)

      must_promote? = must_promote?(piece, to, piece.owner)

      moved_piece =
        if promote? or must_promote? do
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

      new_squares =
        Map.put(board.squares, to, %{
          type: type,
          owner: player
        })

      new_hands = Map.put(board.hands, player, new_hand)

      {:ok, %{board | squares: new_squares, hands: new_hands}}
    end
  end

  def pieces_of(board, player) do
    Enum.filter(board.squares, fn {_pos, piece} ->
      piece.owner == player
    end)
  end

  def king_position(board, player) do
    case Enum.find(board.squares, fn {_pos, piece} ->
           piece.type == :king and piece.owner == player
         end) do
      {pos, _piece} -> {:ok, pos}
      nil -> {:error, :king_not_found}
    end
  end

  # =====================================================================
  # Regras de promoção
  # =====================================================================

  def in_promotion_zone?({_col, row}, :sente), do: row <= 3
  def in_promotion_zone?({_col, row}, :gote), do: row >= 7

  def must_promote?(%{type: :pawn}, {_col, 1}, :sente), do: true
  def must_promote?(%{type: :lance}, {_col, 1}, :sente), do: true
  def must_promote?(%{type: :knight}, {_col, row}, :sente) when row <= 2, do: true

  def must_promote?(%{type: :pawn}, {_col, 9}, :gote), do: true
  def must_promote?(%{type: :lance}, {_col, 9}, :gote), do: true
  def must_promote?(%{type: :knight}, {_col, row}, :gote) when row >= 8, do: true

  def must_promote?(_piece, _to, _player), do: false

  def promotable?(%{type: type}) do
    type in [:pawn, :lance, :knight, :silver, :bishop, :rook]
  end

  def opponent(:sente), do: :gote
  def opponent(:gote), do: :sente

  # =====================================================================
  # Validações internas
  # =====================================================================

  defp fetch_piece(board, pos) do
    case get(board, pos) do
      nil -> {:error, :no_piece}
      piece -> {:ok, piece}
    end
  end

  defp validate_position(pos) do
    if inside?(pos) do
      :ok
    else
      {:error, :invalid_position}
    end
  end

  defp validate_empty(board, pos) do
    if empty?(board, pos) do
      :ok
    else
      {:error, :square_occupied}
    end
  end

  defp validate_destination(board, to, player) do
    case get(board, to) do
      nil -> :ok
      %{owner: ^player} -> {:error, :own_piece_on_destination}
      %{owner: _enemy} -> :ok
    end
  end

  defp validate_piece_in_hand(board, type, player) do
    if type in board.hands[player] do
      :ok
    else
      {:error, :piece_not_in_hand}
    end
  end

  # =====================================================================
  # Captura e promoção
  # =====================================================================

  defp maybe_capture(board, to) do
    case get(board, to) do
      nil ->
        {board, nil}

      %{type: type, owner: enemy} ->
        player = opponent(enemy)
        base_type = unpromote(type)

        new_hand = [base_type | board.hands[player]]
        new_hands = Map.put(board.hands, player, new_hand)

        {%{board | hands: new_hands}, base_type}
    end
  end

  defp promote(%{type: type, owner: owner}) do
    %{
      type: promoted_type(type),
      owner: owner
    }
  end

  defp promoted_type(:pawn), do: :promoted_pawn
  defp promoted_type(:lance), do: :promoted_lance
  defp promoted_type(:knight), do: :promoted_knight
  defp promoted_type(:silver), do: :promoted_silver
  defp promoted_type(:bishop), do: :promoted_bishop
  defp promoted_type(:rook), do: :promoted_rook
  defp promoted_type(type), do: type

  defp unpromote(:promoted_pawn), do: :pawn
  defp unpromote(:promoted_lance), do: :lance
  defp unpromote(:promoted_knight), do: :knight
  defp unpromote(:promoted_silver), do: :silver
  defp unpromote(:promoted_bishop), do: :bishop
  defp unpromote(:promoted_rook), do: :rook
  defp unpromote(type), do: type

  # =====================================================================
  # Setup inicial
  # =====================================================================

  defp place_pawns(squares, owner, row) do
    Enum.reduce(1..@size, squares, fn col, acc ->
      Map.put(acc, {col, row}, %{type: :pawn, owner: owner})
    end)
  end

  defp place_back_rank(squares, owner, row) do
    [:lance, :knight, :silver, :gold, :king, :gold, :silver, :knight, :lance]
    |> Enum.with_index(1)
    |> Enum.reduce(squares, fn {type, col}, acc ->
      Map.put(acc, {col, row}, %{type: type, owner: owner})
    end)
  end

  defp place_special(squares, :gote, row) do
    squares
    |> Map.put({2, row}, %{type: :bishop, owner: :gote})
    |> Map.put({8, row}, %{type: :rook, owner: :gote})
  end

  defp place_special(squares, :sente, row) do
    squares
    |> Map.put({2, row}, %{type: :rook, owner: :sente})
    |> Map.put({8, row}, %{type: :bishop, owner: :sente})
  end
end
