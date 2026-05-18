defmodule Shogi.Supervisor do
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      # Sobe as partidas dinamicamente conforme o matchmaking cria
      {DynamicSupervisor, name: Shogi.Game.Supervisor, strategy: :one_for_one},

      # Fila de matchmaking
      Shogi.Matchmaking.Server
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
