defmodule ShogiWeb.Router do
  use ShogiWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
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
    live("/game/:game_id", GameLive.Show, :index)
  end

  if Application.compile_env(:shogi_com, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: ShogiWeb.Telemetry)
    end
  end
end
