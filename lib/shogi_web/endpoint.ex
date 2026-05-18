defmodule ShogiWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :shogi_com

  # Sessão — necessário para LiveView e autenticação
  @session_options [
    store: :cookie,
    key: "_shogi_key",
    signing_salt: "shogi_salt",
    same_site: "Lax"
  ]

  # LiveView socket
  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  # Arquivos estáticos (JS, CSS, imagens)
  plug(Plug.Static,
    at: "/",
    from: :shogi_com,
    gzip: false,
    only: ShogiWeb.static_paths()
  )

  # Live reload só em dev
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
    plug(Phoenix.Ecto.CheckRepoStatus, otp_app: :shogi_com)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(ShogiWeb.Router)
end
