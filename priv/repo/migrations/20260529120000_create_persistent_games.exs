defmodule Shogi.Repo.Migrations.CreatePersistentGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :game_id, :string, null: false
      add :status, :string, null: false, default: "waiting"
      add :winner_side, :string
      add :result_reason, :string
      add :resigned_by, :string
      add :timed_out_side, :string
      add :turn, :string
      add :time_control, :map
      add :clocks, :map
      add :state, :map
      add :move_count, :integer, null: false, default: 0
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:games, [:game_id])

    create table(:game_players) do
      add :game_record_id, references(:games, on_delete: :delete_all), null: false
      add :player_id, :string, null: false
      add :user_id, :integer
      add :side, :string, null: false
      add :result, :string
      add :joined_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:game_players, [:game_record_id])
    create unique_index(:game_players, [:game_record_id, :side])
    create unique_index(:game_players, [:game_record_id, :player_id])

    create table(:game_moves) do
      add :game_record_id, references(:games, on_delete: :delete_all), null: false
      add :move_number, :integer, null: false
      add :player_id, :string, null: false
      add :side, :string, null: false
      add :kind, :string, null: false
      add :from_row, :integer
      add :from_col, :integer
      add :to_row, :integer
      add :to_col, :integer
      add :piece_type, :string
      add :captured_piece_type, :string
      add :promoted, :boolean, null: false, default: false
      add :result_after, :string
      add :notation, :string
      add :clocks_after, :map
      add :board_after, :map, null: false

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create index(:game_moves, [:game_record_id])
    create unique_index(:game_moves, [:game_record_id, :move_number])
  end
end
