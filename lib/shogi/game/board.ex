defmodule Shogi.Game.Board do
  @size 9

  @type position :: {1..9, 1..9}
  @type piece :: %{type: atom(), owner: :sente | :gote}
  @type t :: %{
          squares: %{position() => piece()},
          hands: %{sente: [atom()], gote: [atom()]}
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

    %{squares: squares, hands: %{sente: [], gote: []}}
  end

  # =====================================================================
  # API pública
  # =====================================================================

  def get(%{squares: squares}, pos), do: Map.get(squares, pos)

  def move(board, from, to, promote \\ false) do
    case Map.get(board.squares, from) do
      nil ->
        {:error, :no_piece}

      piece ->
        {board, captured} = maybe_capture(board, to)

        moved_piece = if promote, do: promote(piece), else: piece

        new_squares =
          board.squares
          |> Map.delete(from)
          |> Map.put(to, moved_piece)

        {:ok, %{board | squares: new_squares}, captured}
    end
  end

  def drop(board, type, to, player) do
    hand = board.hands[player]

    if type in hand do
      new_hand = List.delete(hand, type)

      new_squares = Map.put(board.squares, to, %{type: type, owner: player})

      new_board = %{board | squares: new_squares, hands: Map.put(board.hands, player, new_hand)}

      {:ok, new_board}
    else
      {:error, :piece_not_in_hand}
    end
  end

  def pieces_of(board, player) do
    Enum.filter(board.squares, fn {_pos, piece} -> piece.owner == player end)
  end

  def king_position(board, player) do
    result =
      Enum.find(board.squares, fn {_pos, piece} ->
        piece.type == :king and piece.owner == player
      end)

    case result do
      {pos, _piece} -> {:ok, pos}
      nil -> {:error, :king_not_found}
    end
  end

  def in_promotion_zone?({_col, row}, :sente), do: row <= 3
  def in_promotion_zone?({_col, row}, :gote), do: row >= 7

  def must_promote?(%{type: :pawn}, {_c, 1}, :sente), do: true
  def must_promote?(%{type: :lance}, {_c, 1}, :sente), do: true
  def must_promote?(%{type: :knight}, {_c, r}, :sente) when r <= 2, do: true
  def must_promote?(%{type: :pawn}, {_c, 9}, :gote), do: true
  def must_promote?(%{type: :lance}, {_c, 9}, :gote), do: true
  def must_promote?(%{type: :knight}, {_c, r}, :gote) when r >= 8, do: true
  def must_promote?(_piece, _to, _player), do: false

  # =====================================================================
  # Privado — setup inicial
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

  # =====================================================================
  # Privado — captura e promoção
  # =====================================================================

  defp maybe_capture(board, to) do
    case Map.get(board.squares, to) do
      nil ->
        {board, nil}

      %{type: type, owner: enemy} ->
        owner = opponent(enemy)
        base_type = unpromote(type)
        new_hand = [base_type | board.hands[owner]]
        new_board = %{board | hands: Map.put(board.hands, owner, new_hand)}
        {new_board, base_type}
    end
  end

  defp opponent(:sente), do: :gote
  defp opponent(:gote), do: :sente

  defp promote(%{type: type, owner: owner}),
    do: %{type: promoted_type(type), owner: owner}

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
end
