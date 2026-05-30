defmodule Shogi.Game.Server do
  @moduledoc """
  GenServer responsável pelo estado e ciclo de vida de uma partida.
  """

  use GenServer

  alias Shogi.Game.{Board, Rules, TimeControl}
  alias Shogi.Games

  require Logger

  @idle_timeout 10 * 60 * 1_000

  defstruct [
    :game_id,
    :board,
    :turn,
    :phase,
    :winner,
    :result_reason,
    :resigned_by,
    :timed_out_side,
    :time_control,
    :clocks,
    :active_turn_started_at,
    :clock_timer_ref,
    :players,
    :move_count,
    :last_move
  ]

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, opts, name: via(game_id))
  end

  def join(game_id, player_id, side) when side in [:sente, :gote] do
    GenServer.call(via(game_id), {:join, player_id, side})
  end

  def move(game_id, player_id, from, to, opts \\ []) do
    GenServer.call(via(game_id), {:move, player_id, from, to, opts})
  end

  def drop(game_id, player_id, type, to) do
    GenServer.call(via(game_id), {:drop, player_id, type, to})
  end

  def state(game_id) do
    GenServer.call(via(game_id), :state)
  end

  def resign(game_id, player_id) do
    GenServer.call(via(game_id), {:resign, player_id})
  end

  @impl true
  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    time_control = Keyword.get(opts, :time_control, TimeControl.default())

    state =
      case Keyword.get(opts, :restored_state) || Games.restore_game_state(game_id) do
        {:ok, restored_state} ->
          %{
            restored_state
            | active_turn_started_at: turn_started_at(restored_state),
              clock_timer_ref: nil
          }
          |> restart_clock_timer()

        %__MODULE__{} = restored_state ->
          %{
            restored_state
            | active_turn_started_at: turn_started_at(restored_state),
              clock_timer_ref: nil
          }
          |> restart_clock_timer()

        _ ->
          new_state(game_id, time_control)
          |> tap(&persist_create/1)
      end

    {:ok, state, timeout_for(state)}
  end

  defp new_state(game_id, time_control) do
    initial_seconds = time_control.initial_seconds

    %__MODULE__{
      game_id: game_id,
      board: Board.new(),
      turn: :sente,
      phase: :waiting,
      winner: nil,
      result_reason: nil,
      resigned_by: nil,
      timed_out_side: nil,
      time_control: time_control,
      clocks: %{sente: initial_seconds, gote: initial_seconds},
      active_turn_started_at: nil,
      clock_timer_ref: nil,
      players: %{sente: nil, gote: nil},
      move_count: 0,
      last_move: nil
    }
  end

  defp turn_started_at(%{phase: :playing}), do: now_ms()
  defp turn_started_at(_state), do: nil

  defp persist_create(state) do
    case Games.create_game_record(state.game_id, state) do
      {:ok, _record} ->
        :ok

      {:error, reason} ->
        Logger.error("failed to create game record #{state.game_id}: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_call({:join, player_id, side}, _from, %{phase: :waiting} = state) do
    cond do
      state.players[side] != nil ->
        {:reply, {:error, :side_taken}, state, @idle_timeout}

      player_already_joined?(state, player_id) ->
        {:reply, {:error, :already_joined}, state, @idle_timeout}

      true ->
        new_players = Map.put(state.players, side, player_id)
        new_phase = if both_joined?(new_players), do: :playing, else: :waiting

        new_state =
          %{state | players: new_players, phase: new_phase}
          |> maybe_start_clock(new_phase)

        persist_player_and_state(new_state, player_id, side)

        if new_phase == :playing do
          broadcast(new_state, {:game_started, public_state(new_state)})
        end

        {:reply, {:ok, new_phase}, new_state, timeout_for(new_state)}
    end
  end

  def handle_call({:join, _player_id, _side}, _from, state) do
    {:reply, {:error, :game_not_waiting}, state, timeout_for(state)}
  end

  def handle_call({:move, _player_id, _from, _to, _opts}, _from_ref, %{phase: :waiting} = state) do
    {:reply, {:error, :game_not_started}, state, @idle_timeout}
  end

  def handle_call({:move, _, _, _, _}, _from, %{phase: :finished} = state) do
    {:reply, {:error, :game_finished}, state, @idle_timeout}
  end

  def handle_call({:move, player_id, from, to, opts}, _from, %{phase: :playing} = state) do
    piece = Board.get(state.board, from)
    promote = Keyword.get(opts, :promote, false) or Board.must_promote?(piece, to, state.turn)

    with :ok <- check_turn(state, player_id),
         true <- Rules.valid_move?(state.board, from, to, state.turn),
         {:ok, new_board, captured} <- Board.move(state.board, from, to, promote) do
      state = apply_elapsed_clock(state)

      new_state =
        if out_of_time?(state, state.turn) do
          finish_by_timeout(state, state.turn)
        else
          state
          |> add_increment(state.turn)
          |> then(fn state ->
            %{
              state
              | board: new_board,
                turn: next_turn(state.turn),
                move_count: state.move_count + 1,
                last_move: {:move, from, to, promote, captured},
                active_turn_started_at: now_ms()
            }
          end)
          |> restart_clock_timer()
          |> maybe_finish()
        end

      persist_move_event(
        state,
        new_state,
        player_id,
        move_attrs_for_move(new_state, player_id, state.turn, from, to, piece, captured, promote)
      )

      public = public_state(new_state)
      broadcast(new_state, {:game_updated, public})
      {:reply, {:ok, public}, new_state, timeout_for(new_state)}
    else
      false -> {:reply, {:error, :invalid_move}, state, timeout_for(state)}
      {:error, reason} -> {:reply, {:error, reason}, state, timeout_for(state)}
    end
  end

  def handle_call({:drop, _, _, _}, _from, %{phase: :waiting} = state) do
    {:reply, {:error, :game_not_started}, state, @idle_timeout}
  end

  def handle_call({:drop, _, _, _}, _from, %{phase: :finished} = state) do
    {:reply, {:error, :game_finished}, state, @idle_timeout}
  end

  def handle_call({:drop, player_id, type, to}, _from, %{phase: :playing} = state) do
    with :ok <- check_turn(state, player_id),
         true <- Rules.valid_drop?(state.board, type, to, state.turn),
         {:ok, new_board} <- Board.drop(state.board, type, to, state.turn) do
      state = apply_elapsed_clock(state)

      new_state =
        if out_of_time?(state, state.turn) do
          finish_by_timeout(state, state.turn)
        else
          state
          |> add_increment(state.turn)
          |> then(fn state ->
            %{
              state
              | board: new_board,
                turn: next_turn(state.turn),
                move_count: state.move_count + 1,
                last_move: {:drop, type, to},
                active_turn_started_at: now_ms()
            }
          end)
          |> restart_clock_timer()
          |> maybe_finish()
        end

      persist_move_event(
        state,
        new_state,
        player_id,
        move_attrs_for_drop(new_state, player_id, state.turn, type, to)
      )

      public = public_state(new_state)
      broadcast(new_state, {:game_updated, public})
      {:reply, {:ok, public}, new_state, timeout_for(new_state)}
    else
      false -> {:reply, {:error, :invalid_drop}, state, timeout_for(state)}
      {:error, reason} -> {:reply, {:error, reason}, state, timeout_for(state)}
    end
  end

  def handle_call(:state, _from, state) do
    {:reply, public_state(state), state, timeout_for(state)}
  end

  def handle_call({:resign, player_id}, _from, %{phase: :playing} = state) do
    case side_of(state, player_id) do
      {:ok, side} ->
        winner = other_side(side)

        new_state =
          state
          |> apply_elapsed_clock()
          |> cancel_clock_timer()
          |> then(fn state ->
            %{
              state
              | phase: :finished,
                winner: winner,
                result_reason: :resignation,
                resigned_by: side,
                move_count: state.move_count + 1,
                active_turn_started_at: nil,
                last_move: :resign
            }
          end)

        persist_move_event(
          state,
          new_state,
          player_id,
          move_attrs_for_terminal(new_state, player_id, side, :resign)
        )

        public = public_state(new_state)
        broadcast(new_state, {:game_updated, public})

        broadcast(
          new_state,
          {:game_over, %{winner: winner, reason: :resignation, resigned_by: side}}
        )

        {:reply, {:ok, public}, new_state, @idle_timeout}

      :error ->
        {:reply, {:error, :not_a_player}, state, timeout_for(state)}
    end
  end

  def handle_call({:resign, _player_id}, _from, %{phase: :finished} = state) do
    {:reply, {:error, :game_already_finished}, state, @idle_timeout}
  end

  def handle_call({:resign, _player_id}, _from, state) do
    {:reply, {:error, :cannot_resign}, state, timeout_for(state)}
  end

  @impl true
  def handle_info({:clock_timeout, side, move_count}, state) do
    if state.phase == :playing and state.turn == side and state.move_count == move_count do
      new_state = finish_by_timeout(state, side)
      player_id = player_id_for_side(new_state, side)

      persist_move_event(
        state,
        new_state,
        player_id,
        move_attrs_for_terminal(new_state, player_id, side, :timeout)
      )

      public = public_state(new_state)
      broadcast(new_state, {:game_updated, public})

      broadcast(
        new_state,
        {:game_over, %{winner: new_state.winner, reason: :timeout, timed_out_side: side}}
      )

      {:noreply, new_state, @idle_timeout}
    else
      {:noreply, state, timeout_for(state)}
    end
  end

  def handle_info(:timeout, %{phase: :playing} = state) do
    {:noreply, state, @idle_timeout}
  end

  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state, timeout_for(state)}
  end

  defp maybe_finish(%{phase: :finished} = state), do: state

  defp maybe_finish(state) do
    if Rules.checkmate?(state.board, state.turn) do
      winner = other_side(state.turn)

      state
      |> cancel_clock_timer()
      |> then(&%{&1 | phase: :finished, winner: winner, result_reason: :checkmate})
    else
      state
    end
  end

  defp check_turn(state, player_id) do
    if state.players[state.turn] == player_id,
      do: :ok,
      else: {:error, :not_your_turn}
  end

  defp both_joined?(%{sente: s, gote: g}), do: s != nil and g != nil

  defp player_already_joined?(state, player_id) do
    state.players.sente == player_id or state.players.gote == player_id
  end

  defp next_turn(:sente), do: :gote
  defp next_turn(:gote), do: :sente

  defp other_side(:sente), do: :gote
  defp other_side(:gote), do: :sente

  defp side_of(state, player_id) do
    cond do
      state.players.sente == player_id -> {:ok, :sente}
      state.players.gote == player_id -> {:ok, :gote}
      true -> :error
    end
  end

  defp maybe_start_clock(state, :playing) do
    %{state | active_turn_started_at: now_ms()}
    |> restart_clock_timer()
  end

  defp maybe_start_clock(state, _phase), do: state

  defp restart_clock_timer(state) do
    state
    |> cancel_clock_timer()
    |> start_clock_timer()
  end

  defp start_clock_timer(%{phase: :playing, turn: side} = state) do
    remaining_ms = max(Map.fetch!(state.clocks, side), 0) * 1000
    ref = Process.send_after(self(), {:clock_timeout, side, state.move_count}, remaining_ms)
    %{state | clock_timer_ref: ref}
  end

  defp start_clock_timer(state), do: state

  defp cancel_clock_timer(%{clock_timer_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | clock_timer_ref: nil}
  end

  defp cancel_clock_timer(state), do: %{state | clock_timer_ref: nil}

  defp apply_elapsed_clock(
         %{phase: :playing, active_turn_started_at: started_at, turn: side} = state
       )
       when is_integer(started_at) do
    elapsed = elapsed_seconds_since_turn_started(state)
    clocks = Map.update!(state.clocks, side, &max(&1 - elapsed, 0))
    %{state | clocks: clocks, active_turn_started_at: now_ms()}
  end

  defp apply_elapsed_clock(state), do: state

  defp elapsed_seconds_since_turn_started(%{active_turn_started_at: nil}), do: 0

  defp elapsed_seconds_since_turn_started(state) do
    max(0, div(now_ms() - state.active_turn_started_at, 1000))
  end

  defp current_clocks(%{phase: :playing, turn: side} = state) do
    elapsed = elapsed_seconds_since_turn_started(state)
    Map.update!(state.clocks, side, &max(&1 - elapsed, 0))
  end

  defp current_clocks(state), do: state.clocks

  defp add_increment(state, side) do
    increment = Map.get(state.time_control, :increment_seconds, 0)
    %{state | clocks: Map.update!(state.clocks, side, &(&1 + increment))}
  end

  defp out_of_time?(state, side), do: Map.fetch!(state.clocks, side) <= 0

  defp finish_by_timeout(state, side) do
    state
    |> cancel_clock_timer()
    |> then(fn state ->
      %{
        state
        | phase: :finished,
          winner: other_side(side),
          result_reason: :timeout,
          timed_out_side: side,
          clocks: Map.put(state.clocks, side, 0),
          active_turn_started_at: nil,
          move_count: state.move_count + 1,
          last_move: :timeout
      }
    end)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp persist_player_and_state(state, player_id, side) do
    case Games.add_or_update_player(state.game_id, player_id, side) do
      {:ok, _player} ->
        :ok

      {:error, reason} ->
        Logger.error("failed to persist player #{player_id}: #{inspect(reason)}")
    end

    case Games.save_game_state(state.game_id, state) do
      {:ok, _record} ->
        :ok

      {:error, reason} ->
        Logger.error("failed to persist game state #{state.game_id}: #{inspect(reason)}")
    end
  end

  defp persist_move_event(_old_state, _new_state, nil, %{kind: :timeout}) do
    Logger.error("cannot persist timeout move without player_id")
  end

  defp persist_move_event(_old_state, new_state, _player_id, move_attrs) do
    case Games.record_move_and_update_game(new_state.game_id, move_attrs, new_state) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.error("failed to persist move #{new_state.game_id}: #{inspect(reason)}")
    end
  end

  defp move_attrs_for_move(new_state, player_id, side, from, to, piece, captured, promote) do
    {from_row, from_col} = from
    {to_row, to_col} = to

    %{
      move_number: new_state.move_count,
      player_id: player_id,
      side: side,
      kind: move_kind(new_state, :move),
      from_row: from_row,
      from_col: from_col,
      to_row: to_row,
      to_col: to_col,
      piece_type: piece && piece.type,
      captured_piece_type: captured,
      promoted: promote,
      result_after: new_state.result_reason
    }
  end

  defp move_attrs_for_drop(new_state, player_id, side, type, to) do
    {to_row, to_col} = to

    %{
      move_number: new_state.move_count,
      player_id: player_id,
      side: side,
      kind: move_kind(new_state, :drop),
      to_row: to_row,
      to_col: to_col,
      piece_type: type,
      promoted: false,
      result_after: new_state.result_reason
    }
  end

  defp move_attrs_for_terminal(new_state, player_id, side, kind) do
    %{
      move_number: new_state.move_count,
      player_id: player_id,
      side: side,
      kind: kind,
      promoted: false,
      result_after: new_state.result_reason
    }
  end

  defp move_kind(%{result_reason: :timeout}, _kind), do: :timeout
  defp move_kind(_state, kind), do: kind

  defp player_id_for_side(state, side) do
    case Map.get(state.players, side) do
      nil ->
        Logger.error(
          "missing player_id for timed out side #{inspect(side)} in game #{state.game_id}"
        )

        nil

      player_id ->
        player_id
    end
  end

  defp public_state(state) do
    %{
      game_id: state.game_id,
      board: state.board,
      turn: state.turn,
      phase: state.phase,
      winner: state.winner,
      result_reason: state.result_reason,
      resigned_by: state.resigned_by,
      timed_out_side: state.timed_out_side,
      time_control: state.time_control,
      clocks: current_clocks(state),
      server_time_ms: now_ms(),
      players: state.players,
      move_count: state.move_count,
      last_move: state.last_move,
      time_left_seconds: clock_time_left(state.clock_timer_ref)
    }
  end

  defp clock_time_left(nil), do: nil

  defp clock_time_left(ref) do
    case Process.read_timer(ref) do
      false -> 0
      ms -> div(ms, 1_000)
    end
  end

  defp timeout_for(%{phase: :playing}), do: @idle_timeout
  defp timeout_for(_state), do: @idle_timeout

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(Shogi.PubSub, "game:#{state.game_id}", message)
  end

  defp via(game_id) do
    {:via, Registry, {Shogi.Game.Registry, game_id}}
  end
end
