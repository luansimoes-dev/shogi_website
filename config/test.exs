import Config

config :shogi_com, Shogi.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "shogi_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool_size: 10

config :shogi_com, ShogiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_must_be_at_least_64_chars_long_xxxxxxxxxxxxxxxxx",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
