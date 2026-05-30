defmodule Shogi.Matchmaking.Server do
  @moduledoc """
  GenServer que gerencia filas de matchmaking anonimo separadas por ritmo de tempo.
  """

  use GenServer

  alias Shogi.Game.Server, as: GameServer
  alias Shogi.Game.TimeControl
  alias Shogi.Matchmaking.Queue

  defstruct queues: %{}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  def join_queue(player_id), do: join_queue(player_id, TimeControl.default_id())

  def join_queue(player_id, time_control_id) do
    GenServer.call(__MODULE__, {:join_queue, player_id, time_control_id})
  end

  def leave_queue(player_id) do
    GenServer.call(__MODULE__, {:leave_queue, player_id})
  end

  def status(player_id) do
    GenServer.call(__MODULE__, {:status, player_id})
  end

  def queue_size, do: queue_size(TimeControl.default_id())

  def queue_size(time_control_id) do
    GenServer.call(__MODULE__, {:queue_size, time_control_id})
  end

  def join(player_id), do: join_queue(player_id)
  def leave(player_id), do: leave_queue(player_id)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:join_queue, player_id, time_control_id}, _from, state) do
    with {:ok, time_control} <- TimeControl.fetch(time_control_id) do
      if queued_anywhere?(state.queues, player_id) do
        {:reply, {:waiting}, state}
      else
        queue = queue_for(state, time_control_id)

        case Queue.enqueue(queue, player_id) do
          {:ok, queue} ->
            state
            |> put_queue(time_control_id, queue)
            |> match_or_wait(player_id, time_control_id, time_control)

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:leave_queue, player_id}, _from, state) do
    queues =
      Map.new(state.queues, fn {time_control_id, queue} ->
        {time_control_id, Queue.remove(queue, player_id)}
      end)

    {:reply, :ok, %{state | queues: queues}}
  end

  def handle_call({:status, player_id}, _from, state) do
    status = if queued_anywhere?(state.queues, player_id), do: :waiting, else: :idle
    {:reply, status, state}
  end

  def handle_call({:queue_size, time_control_id}, _from, state) do
    {:reply, Queue.size(queue_for(state, time_control_id)), state}
  end

  defp match_or_wait(state, joined_player_id, time_control_id, time_control) do
    case Queue.dequeue(queue_for(state, time_control_id)) do
      {:matched, player1, player2, rest} when player1 != player2 ->
        match = create_match(player1, player2, time_control_id, time_control)
        notify_player(match.sente.player_id, match.sente)
        notify_player(match.gote.player_id, match.gote)

        reply = if joined_player_id == match.sente.player_id, do: match.sente, else: match.gote
        {:reply, {:matched, reply}, put_queue(state, time_control_id, rest)}

      _ ->
        {:reply, {:waiting}, state}
    end
  end

  defp create_match(player1, player2, time_control_id, time_control) do
    game_id = generate_id()
    start_game(game_id, time_control)

    {sente_player, gote_player} = assign_random_sides(player1, player2)

    {:ok, _phase} = GameServer.join(game_id, sente_player, :sente)
    {:ok, _phase} = GameServer.join(game_id, gote_player, :gote)

    %{
      sente: %{
        event: :matched,
        game_id: game_id,
        side: :sente,
        player_id: sente_player,
        opponent: gote_player,
        time_control_id: time_control_id
      },
      gote: %{
        event: :matched,
        game_id: game_id,
        side: :gote,
        player_id: gote_player,
        opponent: sente_player,
        time_control_id: time_control_id
      }
    }
  end

  defp assign_random_sides(player1, player2) do
    case Enum.random([:normal, :swapped]) do
      :normal -> {player1, player2}
      :swapped -> {player2, player1}
    end
  end

  defp start_game(game_id, time_control) do
    child_spec = {GameServer, game_id: game_id, time_control: time_control}

    case DynamicSupervisor.start_child(Shogi.Game.Supervisor, child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp notify_player(player_id, match) do
    Phoenix.PubSub.broadcast(Shogi.PubSub, "matchmaking:#{player_id}", match)
  end

  defp queue_for(%{queues: queues}, time_control_id),
    do: Map.get(queues, time_control_id, Queue.new())

  defp put_queue(state, time_control_id, queue) do
    %{state | queues: Map.put(state.queues, time_control_id, queue)}
  end

  defp queued_anywhere?(queues, player_id) do
    Enum.any?(queues, fn {_time_control_id, queue} -> Queue.member?(queue, player_id) end)
  end

  defp generate_id do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
