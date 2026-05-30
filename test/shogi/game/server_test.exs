defmodule Shogi.Game.ServerTest do
  use ExUnit.Case, async: false

  alias Shogi.Game.Server, as: GameServer
  alias Shogi.Game.TimeControl

  test "initial clocks use selected time control" do
    game_id = unique_game_id()
    {_sente, _gote} = start_joined_game(game_id, TimeControl.get("5_0"))

    game = GameServer.state(game_id)
    assert game.time_control.id == "5_0"
    assert game.clocks.sente == 300
    assert game.clocks.gote == 300
  end

  test "valid move subtracts elapsed time and adds increment" do
    game_id = unique_game_id()
    {sente, _gote} = start_joined_game(game_id, TimeControl.get("10_2"))
    shift_turn_start(game_id, 5)

    assert {:ok, game} = GameServer.move(game_id, sente, {6, 4}, {5, 4})
    assert game.clocks.sente == 597
    assert game.clocks.gote == 600
    assert game.turn == :gote
    assert active_turn_started_at(game_id) != nil
  end

  test "valid move without increment only subtracts elapsed time" do
    game_id = unique_game_id()
    {sente, _gote} = start_joined_game(game_id, TimeControl.get("5_0"))
    shift_turn_start(game_id, 5)

    assert {:ok, game} = GameServer.move(game_id, sente, {6, 4}, {5, 4})
    assert game.clocks.sente == 295
    assert game.turn == :gote
  end

  test "timeout finishes game with opponent winner" do
    game_id = unique_game_id()
    start_joined_game(game_id, %{TimeControl.get("5_0") | initial_seconds: 1})

    Process.sleep(1_100)

    game = GameServer.state(game_id)
    assert game.phase == :finished
    assert game.winner == :gote
    assert game.result_reason == :timeout
    assert game.timed_out_side == :sente
    assert game.clocks.sente == 0
  end

  test "drop also subtracts elapsed time and adds increment" do
    game_id = unique_game_id()
    {_sente, gote} = start_joined_game(game_id, TimeControl.get("10_2"))

    replace_board(game_id, drop_fixture_board(), :gote)
    shift_turn_start(game_id, 5)

    assert {:ok, game} = GameServer.drop(game_id, gote, :pawn, {4, 4})
    assert game.clocks.gote == 597
    assert game.turn == :sente
  end

  test "sente resignation finishes game with gote winner" do
    game_id = unique_game_id()
    {sente, _gote} = start_joined_game(game_id)

    assert {:ok, game} = GameServer.resign(game_id, sente)
    assert game.phase == :finished
    assert game.winner == :gote
    assert game.result_reason == :resignation
    assert game.resigned_by == :sente
  end

  test "gote resignation finishes game with sente winner" do
    game_id = unique_game_id()
    {_sente, gote} = start_joined_game(game_id)

    assert {:ok, game} = GameServer.resign(game_id, gote)
    assert game.phase == :finished
    assert game.winner == :sente
    assert game.result_reason == :resignation
    assert game.resigned_by == :gote
  end

  test "spectator cannot resign" do
    game_id = unique_game_id()
    start_joined_game(game_id)

    assert {:error, :not_a_player} = GameServer.resign(game_id, "spectator")
  end

  test "cannot resign after game has finished" do
    game_id = unique_game_id()
    {sente, gote} = start_joined_game(game_id)

    assert {:ok, _game} = GameServer.resign(game_id, sente)
    assert {:error, :game_already_finished} = GameServer.resign(game_id, gote)
  end

  test "move and drop are blocked after game has finished" do
    game_id = unique_game_id()
    {sente, gote} = start_joined_game(game_id)

    assert {:ok, _game} = GameServer.resign(game_id, sente)
    assert {:error, :game_finished} = GameServer.move(game_id, gote, {2, 4}, {3, 4})
    assert {:error, :game_finished} = GameServer.drop(game_id, gote, :pawn, {4, 4})
  end

  test "checkmate after a move finishes game" do
    game_id = unique_game_id()
    {sente, _gote} = start_joined_game(game_id)

    replace_board(game_id, checkmate_fixture_board(), :sente)

    assert {:ok, game} = GameServer.move(game_id, sente, {2, 1}, {2, 0})
    assert game.phase == :finished
    assert game.winner == :sente
    assert game.result_reason == :checkmate
  end

  defp start_joined_game(game_id, time_control \\ TimeControl.default()) do
    sente = "sente-" <> unique_id()
    gote = "gote-" <> unique_id()

    assert {:ok, _pid} = GameServer.start_link(game_id: game_id, time_control: time_control)
    assert {:ok, :waiting} = GameServer.join(game_id, sente, :sente)
    assert {:ok, :playing} = GameServer.join(game_id, gote, :gote)

    {sente, gote}
  end

  defp replace_board(game_id, board, turn) do
    [{pid, _}] = Registry.lookup(Shogi.Game.Registry, game_id)

    :sys.replace_state(pid, fn state ->
      %{
        state
        | board: board,
          turn: turn,
          active_turn_started_at: System.monotonic_time(:millisecond)
      }
    end)
  end

  defp shift_turn_start(game_id, seconds_ago) do
    [{pid, _}] = Registry.lookup(Shogi.Game.Registry, game_id)

    :sys.replace_state(pid, fn state ->
      %{state | active_turn_started_at: System.monotonic_time(:millisecond) - seconds_ago * 1000}
    end)
  end

  defp active_turn_started_at(game_id) do
    [{pid, _}] = Registry.lookup(Shogi.Game.Registry, game_id)
    :sys.get_state(pid).active_turn_started_at
  end

  defp drop_fixture_board do
    %{
      squares: %{
        {8, 8} => %{type: :king, owner: :sente},
        {0, 0} => %{type: :king, owner: :gote}
      },
      hands: %{sente: [], gote: [:pawn]}
    }
  end

  defp checkmate_fixture_board do
    %{
      squares: %{
        {0, 0} => %{type: :king, owner: :gote},
        {1, 2} => %{type: :gold, owner: :sente},
        {2, 1} => %{type: :rook, owner: :sente},
        {8, 8} => %{type: :king, owner: :sente}
      },
      hands: %{sente: [], gote: []}
    }
  end

  defp unique_game_id, do: "server-game-" <> unique_id()

  defp unique_id do
    System.unique_integer([:positive]) |> Integer.to_string()
  end
end
