defmodule Shogi.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Banco de dados
      Shogi.Repo,

      # PubSub — usado pelo Server e pelo LiveView
      {Phoenix.PubSub, name: Shogi.PubSub},

      # Registry — mapeia game_id => pid do Game.Server
      {Registry, keys: :unique, name: Shogi.Game.Registry},

      # Supervisor customizado (game + matchmaking)
      Shogi.Supervisor,

      # Endpoint Phoenix — deve ser o último
      ShogiWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Shogi.RootSupervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ShogiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
