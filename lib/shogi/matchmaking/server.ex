defmodule Shogi.Matchmaking.Server do
  @moduledoc """
  GenServer que gerencia a fila de matchmaking anonimo.
  """

  use GenServer

  alias Shogi.Game.Server, as: GameServer
  alias Shogi.Matchmaking.Queue

  defstruct queue: Queue.new()

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  def join_queue(player_id) do
    GenServer.call(__MODULE__, {:join_queue, player_id})
  end

  def leave_queue(player_id) do
    GenServer.call(__MODULE__, {:leave_queue, player_id})
  end

  def status(player_id) do
    GenServer.call(__MODULE__, {:status, player_id})
  end

  def queue_size do
    GenServer.call(__MODULE__, :queue_size)
  end

  def join(player_id), do: join_queue(player_id)
  def leave(player_id), do: leave_queue(player_id)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:join_queue, player_id}, _from, state) do
    cond do
      Queue.member?(state.queue, player_id) ->
        {:reply, {:waiting}, state}

      true ->
        state.queue
        |> Queue.enqueue(player_id)
        |> case do
          {:ok, queue} -> match_or_wait(%{state | queue: queue}, player_id)
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:leave_queue, player_id}, _from, state) do
    {:reply, :ok, %{state | queue: Queue.remove(state.queue, player_id)}}
  end

  def handle_call({:status, player_id}, _from, state) do
    status = if Queue.member?(state.queue, player_id), do: :waiting, else: :idle
    {:reply, status, state}
  end

  def handle_call(:queue_size, _from, state) do
    {:reply, Queue.size(state.queue), state}
  end

  defp match_or_wait(state, joined_player_id) do
    case Queue.dequeue(state.queue) do
      {:matched, player1, player2, rest} when player1 != player2 ->
        match = create_match(player1, player2)
        notify_player(match.sente.player_id, match.sente)
        notify_player(match.gote.player_id, match.gote)

        reply = if joined_player_id == match.sente.player_id, do: match.sente, else: match.gote
        {:reply, {:matched, reply}, %{state | queue: rest}}

      _ ->
        {:reply, {:waiting}, state}
    end
  end

  defp create_match(player1, player2) do
    game_id = generate_id()
    start_game(game_id)

    {sente_player, gote_player} = assign_random_sides(player1, player2)

    {:ok, _phase} = GameServer.join(game_id, sente_player, :sente)
    {:ok, _phase} = GameServer.join(game_id, gote_player, :gote)

    %{
      sente: %{
        event: :matched,
        game_id: game_id,
        side: :sente,
        player_id: sente_player,
        opponent: gote_player
      },
      gote: %{
        event: :matched,
        game_id: game_id,
        side: :gote,
        player_id: gote_player,
        opponent: sente_player
      }
    }
  end

  defp assign_random_sides(player1, player2) do
    case Enum.random([:normal, :swapped]) do
      :normal -> {player1, player2}
      :swapped -> {player2, player1}
    end
  end

  defp start_game(game_id) do
    case DynamicSupervisor.start_child(Shogi.Game.Supervisor, {GameServer, game_id: game_id}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp notify_player(player_id, match) do
    Phoenix.PubSub.broadcast(Shogi.PubSub, "matchmaking:#{player_id}", match)
  end

  defp generate_id do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
