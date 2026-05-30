ExUnit.start()

try do
  Ecto.Adapters.SQL.query!(
    Shogi.Repo,
    "TRUNCATE game_moves, game_players, games RESTART IDENTITY CASCADE",
    []
  )
rescue
  _ -> :ok
end
