defmodule ShogiWeb.Router do
  use ShogiWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:ensure_player_id)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ShogiWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", ShogiWeb do
    pipe_through(:browser)

    live("/", LobbyLive, :index)
    live("/play", PlayLive, :index)
    live("/game/:game_id", GameLive.Show, :index)
  end

  defp ensure_player_id(conn, _opts) do
    case get_session(conn, :player_id) do
      nil -> put_session(conn, :player_id, anonymous_player_id())
      _player_id -> conn
    end
  end

  defp anonymous_player_id do
    "player-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end

  if Application.compile_env(:shogi_com, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: ShogiWeb.Telemetry)
    end
  end
end
