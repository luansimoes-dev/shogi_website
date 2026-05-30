defmodule Shogi.Games.GamePlayer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_players" do
    belongs_to(:game, Shogi.Games.GameRecord, foreign_key: :game_record_id)

    field(:player_id, :string)
    field(:user_id, :integer)
    field(:side, :string)
    field(:result, :string)
    field(:joined_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:game_record_id, :player_id, :user_id, :side, :result, :joined_at])
    |> validate_required([:game_record_id, :player_id, :side])
    |> validate_inclusion(:side, ["sente", "gote"])
    |> unique_constraint([:game_record_id, :side])
    |> unique_constraint([:game_record_id, :player_id])
  end
end
