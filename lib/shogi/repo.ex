defmodule Shogi.Repo do
  use Ecto.Repo,
    otp_app: :shogi_com,
    adapter: Ecto.Adapters.Postgres
end
