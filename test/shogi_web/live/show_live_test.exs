defmodule ShogiWeb.ShowLiveTest do
  use ShogiWeb.ConnCase, async: false

  alias Shogi.Game.Server, as: GameServer

  test "sente sees row 0 col 0 first and own pieces upright", %{conn: conn} do
    game_id = unique_game_id()
    sente_player = "player-sente-" <> unique_id()
    gote_player = "player-gote-" <> unique_id()

    start_joined_game(game_id, sente_player, gote_player)

    conn = init_test_session(conn, %{player_id: sente_player})
    {:ok, _view, html} = live(conn, ~p"/game/#{game_id}")

    assert first_square_attrs(html) == {"0", "0"}
    assert html =~ "piece gote opponent-piece"
    assert html =~ "piece sente own-piece"
  end

  test "gote sees row 8 col 8 first and keeps backend coordinates in click values", %{conn: conn} do
    game_id = unique_game_id()
    sente_player = "player-sente-" <> unique_id()
    gote_player = "player-gote-" <> unique_id()

    start_joined_game(game_id, sente_player, gote_player)

    conn = init_test_session(conn, %{player_id: gote_player})
    {:ok, _view, html} = live(conn, ~p"/game/#{game_id}")

    assert first_square_attrs(html) == {"8", "8"}
    assert html =~ "piece gote own-piece"
    assert html =~ "piece sente opponent-piece"
  end

  test "resign button shows confirmation and result", %{conn: conn} do
    game_id = unique_game_id()
    sente_player = "player-sente-" <> unique_id()
    gote_player = "player-gote-" <> unique_id()

    start_joined_game(game_id, sente_player, gote_player)

    conn = init_test_session(conn, %{player_id: sente_player})
    {:ok, view, html} = live(conn, ~p"/game/#{game_id}")

    assert html =~ "Desistir"

    html = render_click(view, "request_resign")
    assert html =~ "Tem certeza que deseja desistir?"

    html = render_click(view, "confirm_resign")
    assert html =~ "Voce perdeu."
    assert html =~ "Voce desistiu."
    refute html =~ ~s(phx-click="request_resign")
  end

  test "finished game shows result modal and hides resign button", %{conn: conn} do
    game_id = unique_game_id()
    sente_player = "player-sente-" <> unique_id()
    gote_player = "player-gote-" <> unique_id()

    start_joined_game(game_id, sente_player, gote_player)
    assert {:ok, _game} = GameServer.resign(game_id, gote_player)

    conn = init_test_session(conn, %{player_id: sente_player})
    {:ok, _view, html} = live(conn, ~p"/game/#{game_id}")

    assert html =~ "Voce venceu!"
    assert html =~ "O adversario desistiu."
    refute html =~ ~s(phx-click="request_resign")
  end

  defp start_joined_game(game_id, sente_player, gote_player) do
    assert {:ok, _pid} = GameServer.start_link(game_id: game_id)
    assert {:ok, :waiting} = GameServer.join(game_id, sente_player, :sente)
    assert {:ok, :playing} = GameServer.join(game_id, gote_player, :gote)
  end

  defp first_square_attrs(html) do
    {:ok, document} = Floki.parse_document(html)

    [square | _] = Floki.find(document, ".shogi-board .square")

    row = square |> Floki.attribute("phx-value-row") |> List.first()
    col = square |> Floki.attribute("phx-value-col") |> List.first()

    {row, col}
  end

  defp unique_game_id, do: "game-live-" <> unique_id()

  defp unique_id do
    System.unique_integer([:positive]) |> Integer.to_string()
  end
end
