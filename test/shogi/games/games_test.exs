defmodule Shogi.GamesTest do
  use Shogi.DataCase, async: false

  alias Shogi.Game.{Board, Server, TimeControl}
  alias Shogi.Games
  alias Shogi.Games.{GameMove, GamePlayer, GameRecord}
  alias Shogi.Repo

  test "creates valid game record and enforces public game_id uniqueness" do
    game_id = unique_game_id()
    state = new_state(game_id)

    assert {:ok, %GameRecord{} = record} = Games.create_game_record(game_id, state)
    assert record.game_id == game_id

    assert {:error, changeset} =
             %GameRecord{}
             |> GameRecord.changeset(%{game_id: game_id, status: "waiting", move_count: 0})
             |> Repo.insert()

    assert %{game_id: _} = errors_on(changeset)
  end

  test "creates players and enforces unique side and player per game" do
    game_id = unique_game_id()
    assert {:ok, game} = Games.create_game_record(game_id, new_state(game_id))

    assert {:ok, %GamePlayer{}} = Games.add_or_update_player(game_id, "p1", :sente)
    assert {:ok, %GamePlayer{}} = Games.add_or_update_player(game_id, "p2", :gote)

    assert {:error, changeset} =
             %GamePlayer{}
             |> GamePlayer.changeset(%{game_record_id: game.id, player_id: "p3", side: "sente"})
             |> Repo.insert()

    assert %{game_record_id: _} = errors_on(changeset)

    assert {:error, changeset} =
             %GamePlayer{}
             |> GamePlayer.changeset(%{game_record_id: game.id, player_id: "p1", side: "gote"})
             |> Repo.insert()

    assert %{game_record_id: _} = errors_on(changeset)
  end

  test "game move requires player_id and board_after" do
    game_id = unique_game_id()
    assert {:ok, game} = Games.create_game_record(game_id, new_state(game_id))

    changeset =
      GameMove.changeset(%GameMove{}, %{
        game_record_id: game.id,
        move_number: 1,
        side: "sente",
        kind: "move"
      })

    refute changeset.valid?
    assert %{player_id: _, board_after: _} = errors_on(changeset)
  end

  test "serialize and deserialize board preserves pieces, hands and promotion" do
    board = %{
      squares: %{
        {8, 4} => %{type: :king, owner: :sente},
        {0, 4} => %{type: :promoted_pawn, owner: :gote}
      },
      hands: %{sente: [:pawn, :silver], gote: [:rook]}
    }

    serialized = Games.serialize_board(board)

    assert serialized["schema_version"] == 1
    assert length(serialized["squares"]) == 2
    assert Enum.any?(serialized["squares"], &(&1["type"] == "promoted_pawn" and &1["promoted"]))
    assert serialized["hands"]["sente"] == ["pawn", "silver"]

    assert {:ok, restored} = Games.deserialize_board(serialized)
    assert restored.squares[{0, 4}] == %{type: :promoted_pawn, owner: :gote}
    assert restored.hands.sente == [:pawn, :silver]
  end

  test "record_move_and_update_game inserts move and updates game in one transaction" do
    game_id = unique_game_id()
    state = %{new_state(game_id) | phase: :playing, players: %{sente: "p1", gote: "p2"}}
    assert {:ok, _game} = Games.create_game_record(game_id, state)

    new_board = %{
      state.board
      | squares:
          state.board.squares
          |> Map.delete({6, 4})
          |> Map.put({5, 4}, %{type: :pawn, owner: :sente})
    }

    new_state = %{
      state
      | board: new_board,
        turn: :gote,
        move_count: 1,
        last_move: {:move, {6, 4}, {5, 4}, false, nil}
    }

    move_attrs = %{
      move_number: 1,
      player_id: "p1",
      side: :sente,
      kind: :move,
      from_row: 6,
      from_col: 4,
      to_row: 5,
      to_col: 4,
      piece_type: :pawn,
      promoted: false
    }

    assert {:ok, _result} = Games.record_move_and_update_game(game_id, move_attrs, new_state)

    record = Games.get_game_record_by_public_id(game_id)
    assert record.move_count == 1
    assert record.turn == "gote"

    [move] = Games.list_moves(game_id)
    assert move.move_number == 1
    assert move.board_after["schema_version"] == 1
    assert length(move.board_after["squares"]) == 40
    assert move.clocks_after == %{"sente" => 600, "gote" => 600}
  end

  test "rollback prevents game update when move insert is invalid" do
    game_id = unique_game_id()
    state = new_state(game_id)
    assert {:ok, _game} = Games.create_game_record(game_id, state)

    invalid_move_attrs = %{move_number: 1, player_id: nil, side: :sente, kind: :move}
    new_state = %{state | move_count: 1}

    assert {:error, _reason} =
             Games.record_move_and_update_game(game_id, invalid_move_attrs, new_state)

    assert Games.get_game_record_by_public_id(game_id).move_count == 0
    assert Games.list_moves(game_id) == []
  end

  test "server persists moves, resign and can restore finished game" do
    game_id = unique_game_id()
    {:ok, _pid} = Server.start_link(game_id: game_id, time_control: TimeControl.default())
    assert {:ok, :waiting} = Server.join(game_id, "p1", :sente)
    assert {:ok, :playing} = Server.join(game_id, "p2", :gote)

    assert {:ok, _game} = Server.move(game_id, "p1", {6, 4}, {5, 4})
    assert {:ok, resigned} = Server.resign(game_id, "p2")

    moves = Games.list_moves(game_id)
    assert Enum.map(moves, & &1.move_number) == [1, 2]
    assert Enum.map(moves, & &1.kind) == ["move", "resign"]
    assert List.last(moves).player_id == "p2"

    record = Games.get_game_record_by_public_id(game_id) |> Repo.preload(:players)
    assert record.status == "finished"
    assert record.result_reason == "resignation"
    assert Enum.find(record.players, &(&1.side == "sente")).result == "win"
    assert Enum.find(record.players, &(&1.side == "gote")).result == "loss"

    assert {:ok, restored} = Games.restore_game_state(game_id)
    assert restored.phase == :finished
    assert restored.move_count == resigned.move_count
    assert restored.last_move == :resign
    assert Server.move(game_id, "p1", {5, 4}, {4, 4}) == {:error, :game_finished}
  end

  test "timeout persists player_id of timed out side" do
    game_id = unique_game_id()

    {:ok, _pid} =
      Server.start_link(
        game_id: game_id,
        time_control: %{TimeControl.get("5_0") | initial_seconds: 1}
      )

    assert {:ok, :waiting} = Server.join(game_id, "p1", :sente)
    assert {:ok, :playing} = Server.join(game_id, "p2", :gote)

    Process.sleep(1_100)

    move = Games.list_moves(game_id) |> List.last()
    assert move.kind == "timeout"
    assert move.player_id == "p1"
    assert move.side == "sente"
    assert move.result_after == "timeout"
  end

  defp new_state(game_id) do
    %Server{
      game_id: game_id,
      board: Board.new(),
      turn: :sente,
      phase: :waiting,
      winner: nil,
      result_reason: nil,
      resigned_by: nil,
      timed_out_side: nil,
      time_control: TimeControl.default(),
      clocks: %{sente: 600, gote: 600},
      players: %{sente: nil, gote: nil},
      move_count: 0,
      last_move: nil
    }
  end

  defp unique_game_id do
    "persist-#{System.unique_integer([:positive])}-#{System.system_time(:millisecond)}"
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
