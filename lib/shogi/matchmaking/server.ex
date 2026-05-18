defmodule Shogi.Matchmaking.Server do
  @moduledoc """
  GenServer que gerencia a fila de matchmaking.
  Usa Queue para lógica pura e dispara a criação de partidas
  via DynamicSupervisor quando dois jogadores são pareados.
  """

  use GenServer

  alias Shogi.Matchmaking.Queue
  alias Shogi.Game.Server, as: GameServer

  # ---------------------------------------------------------------------------
  # API pública
  # ---------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, Queue.new(), name: __MODULE__)
  end

  @doc "Entra na fila. Retorna :waiting ou {:matched, game_id, side}."
  def join(player_id) do
    GenServer.call(__MODULE__, {:join, player_id})
  end

  @doc "Sai da fila (ex: jogador fechou a aba na tela de espera)."
  def leave(player_id) do
    GenServer.call(__MODULE__, {:leave, player_id})
  end

  @doc "Retorna quantos jogadores estão aguardando."
  def queue_size do
    GenServer.call(__MODULE__, :size)
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(queue), do: {:ok, queue}

  @impl true
  def handle_call({:join, player_id}, _from, queue) do
    case Queue.enqueue(queue, player_id) do
      {:error, :already_queued} ->
        {:reply, {:error, :already_queued}, queue}

      {:ok, new_queue} ->
        case Queue.dequeue(new_queue) do
          {:matched, player1, player2, rest} ->
            game_id = start_game(player1, player2)
            {:reply, {:matched, game_id, :sente}, rest}

          :waiting ->
            notify_waiting(player_id)
            {:reply, :waiting, new_queue}
        end
    end
  end

  def handle_call({:leave, player_id}, _from, queue) do
    {:reply, :ok, Queue.remove(queue, player_id)}
  end

  def handle_call(:size, _from, queue) do
    {:reply, Queue.size(queue), queue}
  end

  # ---------------------------------------------------------------------------
  # Privado
  # ---------------------------------------------------------------------------

  defp start_game(player1, player2) do
    game_id = generate_id()

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Shogi.Game.Supervisor,
        {GameServer, game_id: game_id}
      )

    GameServer.join(game_id, player1, :sente)
    GameServer.join(game_id, player2, :gote)

    # Notifica cada jogador no canal individual deles
    broadcast_player(player1, {:matched, game_id, :sente})
    broadcast_player(player2, {:matched, game_id, :gote})

    game_id
  end

  defp notify_waiting(player_id) do
    broadcast_player(player_id, :waiting)
  end

  defp broadcast_player(player_id, message) do
    Phoenix.PubSub.broadcast(Shogi.PubSub, "player:#{player_id}", message)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8)
    |> Base.url_encode64(padding: false)
  end
end
