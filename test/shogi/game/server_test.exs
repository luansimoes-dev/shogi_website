defmodule Shogi.Game.ServerTest do
  use ExUnit.Case, async: false

  alias Shogi.Game.Server, as: GameServer

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

  defp start_joined_game(game_id) do
    sente = "sente-" <> unique_id()
    gote = "gote-" <> unique_id()

    assert {:ok, _pid} = GameServer.start_link(game_id: game_id)
    assert {:ok, :waiting} = GameServer.join(game_id, sente, :sente)
    assert {:ok, :playing} = GameServer.join(game_id, gote, :gote)

    {sente, gote}
  end

  defp replace_board(game_id, board, turn) do
    [{pid, _}] = Registry.lookup(Shogi.Game.Registry, game_id)

    :sys.replace_state(pid, fn state ->
      %{state | board: board, turn: turn}
    end)
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
