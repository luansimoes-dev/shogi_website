defmodule Shogi.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Shogi.Repo,
      {Phoenix.PubSub, name: Shogi.PubSub},
      {Registry, keys: :unique, name: Shogi.Game.Registry},
      {DynamicSupervisor, name: Shogi.Game.Supervisor, strategy: :one_for_one},
      Shogi.Matchmaking.Server,
      ShogiWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Shogi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ShogiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
