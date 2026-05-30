defmodule ShogiWeb.HomeLiveTest do
  use ShogiWeb.ConnCase, async: false

  test "renders time control options", %{conn: conn} do
    conn = init_test_session(conn, %{})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Shogi Online"
    assert html =~ "3 + 0"
    assert html =~ "10 + 2"
    assert html =~ "15 + 10"
  end

  test "selects online time and redirects to play with tc", %{conn: conn} do
    conn = init_test_session(conn, %{})

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "select_online_time_control", %{"time-control" => "3_0"})
    render_click(view, "find_match")

    assert_redirect(view, ~p"/play?tc=3_0")
  end

  test "selects private time and creates game with that time control", %{conn: conn} do
    conn = init_test_session(conn, %{})

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "select_private_time_control", %{"time-control" => "5_0"})
    render_click(view, "create_private_game")

    {to, _flash} = assert_redirect(view)
    assert String.starts_with?(to, "/game/")

    game_id = String.replace_prefix(to, "/game/", "")
    assert Shogi.Game.Server.state(game_id).time_control.id == "5_0"
  end

  test "full private link extracts game id", %{conn: conn} do
    conn = init_test_session(conn, %{})

    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "update_join_code", %{
      "join" => %{"code" => "http://localhost:4000/game/abc123"}
    })

    render_submit(view, "join_private_game", %{
      "join" => %{"code" => "http://localhost:4000/game/abc123"}
    })

    assert_redirect(view, ~p"/game/abc123")
  end
end
