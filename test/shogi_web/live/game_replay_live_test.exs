defmodule ShogiWeb.GameReplayLiveTest do
  use ShogiWeb.ConnCase, async: false

  alias Shogi.Game.Server, as: GameServer

  test "renders replay from persisted board snapshots and navigates moves", %{conn: conn} do
    game_id = unique_game_id()
    {sente, gote} = start_finished_game(game_id)

    conn = init_test_session(conn, %{player_id: sente})
    {:ok, view, html} = live(conn, ~p"/game/#{game_id}/replay")

    assert html =~ "Replay"
    assert html =~ "Lance 0 / 2"
    assert html =~ sente
    assert html =~ gote
    assert html =~ "10 + 2"
    assert html =~ "Posição inicial."

    html = render_click(view, "go_next")
    assert html =~ "Lance 1 / 2"
    assert html =~ "move"
    assert html =~ "6,4"
    assert html =~ "5,4"
    assert html =~ "pawn"
    assert html =~ "10:02"

    html = render_click(view, "go_end")
    assert html =~ "Lance 2 / 2"
    assert html =~ "resign"
    assert html =~ "Desistência"
  end

  test "can invert replay perspective", %{conn: conn} do
    game_id = unique_game_id()
    {sente, _gote} = start_finished_game(game_id)

    conn = init_test_session(conn, %{player_id: sente})
    {:ok, view, html} = live(conn, ~p"/game/#{game_id}/replay")

    assert first_square_attrs(html) == {"0", "0"}

    html = render_click(view, "toggle_perspective")
    assert first_square_attrs(html) == {"8", "8"}
  end

  test "finished game modal links to replay", %{conn: conn} do
    game_id = unique_game_id()
    {sente, _gote} = start_finished_game(game_id)

    conn = init_test_session(conn, %{player_id: sente})
    {:ok, _view, html} = live(conn, ~p"/game/#{game_id}")

    assert html =~ "Ver replay"
    assert html =~ "/game/#{game_id}/replay"
  end

  defp start_finished_game(game_id) do
    sente = "replay-sente-" <> unique_id()
    gote = "replay-gote-" <> unique_id()

    assert {:ok, _pid} = GameServer.start_link(game_id: game_id)
    assert {:ok, :waiting} = GameServer.join(game_id, sente, :sente)
    assert {:ok, :playing} = GameServer.join(game_id, gote, :gote)
    assert {:ok, _game} = GameServer.move(game_id, sente, {6, 4}, {5, 4})
    assert {:ok, _game} = GameServer.resign(game_id, gote)

    {sente, gote}
  end

  defp first_square_attrs(html) do
    {:ok, document} = Floki.parse_document(html)
    [square | _] = Floki.find(document, ".shogi-board .square")

    row = square |> Floki.attribute("data-row") |> List.first()
    col = square |> Floki.attribute("data-col") |> List.first()

    {row, col}
  end

  defp unique_game_id, do: "replay-game-" <> unique_id()

  defp unique_id do
    System.unique_integer([:positive]) |> Integer.to_string()
  end
end
