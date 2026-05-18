import Config

config :shogi_com, :env, Mix.env()

config :shogi_com,
  ecto_repos: [Shogi.Repo]

config :shogi_com, ShogiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ShogiWeb.ErrorHTML, json: ShogiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Shogi.PubSub,
  live_view: [signing_salt: "shogi_lv_salt"]

config :esbuild,
  version: "0.17.11",
  shogi_com: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.0",
  shogi_com: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
