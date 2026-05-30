defmodule Shogi.Games.GameRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "games" do
    field(:game_id, :string)
    field(:status, :string)
    field(:winner_side, :string)
    field(:result_reason, :string)
    field(:resigned_by, :string)
    field(:timed_out_side, :string)
    field(:turn, :string)
    field(:time_control, :map)
    field(:clocks, :map)
    field(:state, :map)
    field(:move_count, :integer, default: 0)
    field(:started_at, :utc_datetime)
    field(:finished_at, :utc_datetime)

    has_many(:players, Shogi.Games.GamePlayer, foreign_key: :game_record_id)
    has_many(:moves, Shogi.Games.GameMove, foreign_key: :game_record_id)

    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :game_id,
      :status,
      :winner_side,
      :result_reason,
      :resigned_by,
      :timed_out_side,
      :turn,
      :time_control,
      :clocks,
      :state,
      :move_count,
      :started_at,
      :finished_at
    ])
    |> validate_required([:game_id, :status, :move_count])
    |> unique_constraint(:game_id)
  end
end
