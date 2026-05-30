defmodule Shogi.Matchmaking.ServerTest do
  use ExUnit.Case, async: false

  alias Shogi.Game.Server, as: GameServer
  alias Shogi.Matchmaking.Server, as: Matchmaking

  setup do
    player1 = "player-" <> unique_id()
    player2 = "player-" <> unique_id()

    Matchmaking.leave_queue(player1)
    Matchmaking.leave_queue(player2)

    on_exit(fn ->
      Matchmaking.leave_queue(player1)
      Matchmaking.leave_queue(player2)
    end)

    {:ok, player1: player1, player2: player2}
  end

  test "join_queue returns waiting for first player", %{player1: player1} do
    assert {:waiting} = Matchmaking.join_queue(player1, "10_2")
    assert Matchmaking.status(player1) == :waiting
  end

  test "join_queue returns matched for second player and creates game", %{
    player1: player1,
    player2: player2
  } do
    Phoenix.PubSub.subscribe(Shogi.PubSub, "matchmaking:#{player1}")

    assert {:waiting} = Matchmaking.join_queue(player1, "10_2")

    assert {:matched,
            %{game_id: game_id, side: second_side, opponent: ^player1, time_control_id: "10_2"}} =
             Matchmaking.join_queue(player2, "10_2")

    assert second_side in [:sente, :gote]

    first_side = other_side(second_side)
    assert_receive %{event: :matched, game_id: ^game_id, side: ^first_side, opponent: ^player2}

    game = GameServer.state(game_id)
    assert game.players.sente in [player1, player2]
    assert game.players.gote in [player1, player2]
    assert game.players.sente != game.players.gote
    assert Enum.sort([game.players.sente, game.players.gote]) == Enum.sort([player1, player2])
    assert game.phase == :playing
    assert game.time_control.id == "10_2"
  end

  test "players in different time control queues are not matched", %{
    player1: player1,
    player2: player2
  } do
    assert {:waiting} = Matchmaking.join_queue(player1, "3_0")
    assert {:waiting} = Matchmaking.join_queue(player2, "5_0")

    assert Matchmaking.queue_size("3_0") == 1
    assert Matchmaking.queue_size("5_0") == 1
  end

  test "same time control players are matched and game receives time control", %{
    player1: player1,
    player2: player2
  } do
    assert {:waiting} = Matchmaking.join_queue(player1, "15_10")

    assert {:matched, %{game_id: game_id, time_control_id: "15_10"}} =
             Matchmaking.join_queue(player2, "15_10")

    assert GameServer.state(game_id).time_control.id == "15_10"
  end

  test "random side assignment can choose either player as sente" do
    sente_players =
      for _ <- 1..40 do
        player1 = "player-random-a-" <> unique_id()
        player2 = "player-random-b-" <> unique_id()

        Matchmaking.leave_queue(player1)
        Matchmaking.leave_queue(player2)

        assert {:waiting} = Matchmaking.join_queue(player1, "10_2")
        assert {:matched, %{game_id: game_id}} = Matchmaking.join_queue(player2, "10_2")

        game = GameServer.state(game_id)
        assert game.players.sente != game.players.gote
        assert Enum.sort([game.players.sente, game.players.gote]) == Enum.sort([player1, player2])

        game.players.sente
      end

    assert Enum.any?(sente_players, &String.contains?(&1, "player-random-a-"))
    assert Enum.any?(sente_players, &String.contains?(&1, "player-random-b-"))
  end

  test "entering twice does not duplicate queue entry", %{player1: player1} do
    assert {:waiting} = Matchmaking.join_queue(player1, "10_2")
    assert {:waiting} = Matchmaking.join_queue(player1, "10_2")
    assert Matchmaking.queue_size("10_2") == 1
  end

  test "leave_queue removes waiting player", %{player1: player1} do
    assert {:waiting} = Matchmaking.join_queue(player1, "10_2")
    assert :ok = Matchmaking.leave_queue(player1)
    assert Matchmaking.status(player1) == :idle
  end

  defp other_side(:sente), do: :gote
  defp other_side(:gote), do: :sente

  defp unique_id do
    System.unique_integer([:positive]) |> Integer.to_string()
  end
end
