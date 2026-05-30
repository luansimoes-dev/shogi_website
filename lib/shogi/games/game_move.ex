defmodule Shogi.Games.GameMove do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_moves" do
    belongs_to(:game, Shogi.Games.GameRecord, foreign_key: :game_record_id)

    field(:move_number, :integer)
    field(:player_id, :string)
    field(:side, :string)
    field(:kind, :string)
    field(:from_row, :integer)
    field(:from_col, :integer)
    field(:to_row, :integer)
    field(:to_col, :integer)
    field(:piece_type, :string)
    field(:captured_piece_type, :string)
    field(:promoted, :boolean, default: false)
    field(:result_after, :string)
    field(:notation, :string)
    field(:clocks_after, :map)
    field(:board_after, :map)

    timestamps(updated_at: false, type: :utc_datetime)
  end

  def changeset(move, attrs) do
    move
    |> cast(attrs, [
      :game_record_id,
      :move_number,
      :player_id,
      :side,
      :kind,
      :from_row,
      :from_col,
      :to_row,
      :to_col,
      :piece_type,
      :captured_piece_type,
      :promoted,
      :result_after,
      :notation,
      :clocks_after,
      :board_after
    ])
    |> validate_required([:game_record_id, :move_number, :player_id, :side, :kind, :board_after])
    |> validate_inclusion(:side, ["sente", "gote"])
    |> validate_inclusion(:kind, ["move", "drop", "resign", "timeout"])
    |> unique_constraint([:game_record_id, :move_number])
  end
end
