defmodule ShogiWeb.PlayLiveTest do
  use ShogiWeb.ConnCase, async: false

  alias Shogi.Matchmaking.Server, as: Matchmaking

  setup do
    player_id = "player-live-" <> Integer.to_string(System.unique_integer([:positive]))

    on_exit(fn ->
      Matchmaking.leave_queue(player_id)
    end)

    {:ok, player_id: player_id}
  end

  test "shows play button and enters waiting state", %{conn: conn, player_id: player_id} do
    conn = init_test_session(conn, %{player_id: player_id})

    {:ok, view, html} = live(conn, ~p"/play?tc=5_0")
    assert html =~ "Procurar partida"
    assert html =~ "5 + 0"

    html = render_click(view, "find_match")
    assert html =~ "Procurando adversario"
  end

  test "cancel returns to idle state", %{conn: conn, player_id: player_id} do
    conn = init_test_session(conn, %{player_id: player_id})

    {:ok, view, _html} = live(conn, ~p"/play?tc=5_0")
    render_click(view, "find_match")
    html = render_click(view, "cancel_match")

    assert html =~ "Procurar partida"
  end

  test "redirects when receiving match", %{conn: conn, player_id: player_id} do
    conn = init_test_session(conn, %{player_id: player_id})

    {:ok, view, _html} = live(conn, ~p"/play?tc=5_0")
    render_click(view, "find_match")

    other_player = "player-live-" <> Integer.to_string(System.unique_integer([:positive]))
    assert {:matched, %{game_id: game_id}} = Matchmaking.join_queue(other_player, "5_0")

    assert_redirect(view, ~p"/game/#{game_id}")
  end
end
