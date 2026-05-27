defmodule Shogi.Game.Server do
  @moduledoc """
  GenServer responsável pelo estado e ciclo de vida de uma partida.

  Timeouts:
  - @idle_timeout: encerra o processo se nenhuma mensagem chegar (jogadores abandonaram)
  - @turn_timeout: encerra o turno/partida se o jogador demorar demais para jogar

  ## Uso

      {:ok, pid} = Shogi.Game.Server.start_link(game_id: "abc123")

      Shogi.Game.Server.join(pid, "player1", :sente)
      Shogi.Game.Server.join(pid, "player2", :gote)

      Shogi.Game.Server.move(pid, "player1", {7, 7}, {7, 6})
      Shogi.Game.Server.move(pid, "player1", {7, 7}, {7, 6}, promote: true)
      Shogi.Game.Server.drop(pid, "player2", :pawn, {5, 5})
  """

  use GenServer

  alias Shogi.Game.{Board, Rules}

  # Encerra o processo se ficar 10 min sem nenhuma mensagem (processo zumbi)
  @idle_timeout 10 * 60 * 1_000

  # Tempo máximo por turno — perde quem deixar estourar
  @turn_timeout 5 * 60 * 1_000

  # ---------------------------------------------------------------------------
  # Estado interno
  # ---------------------------------------------------------------------------

  defstruct [
    :game_id,
    :board,
    :turn,
    :phase,
    :winner,
    :players,
    :move_count,
    :last_move,
    :turn_timer_ref
  ]

  # ---------------------------------------------------------------------------
  # API pública
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, game_id, name: via(game_id))
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

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(game_id) do
    state = %__MODULE__{
      game_id: game_id,
      board: Board.new(),
      turn: :sente,
      phase: :waiting,
      winner: nil,
      players: %{sente: nil, gote: nil},
      move_count: 0,
      last_move: nil,
      turn_timer_ref: nil
    }

    {:ok, state, @idle_timeout}
  end

  # ---------------------------------------------------------------------------
  # join
  # ---------------------------------------------------------------------------

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
          |> maybe_start_turn_timer(new_phase)

        if new_phase == :playing do
          broadcast(new_state, {:game_started, public_state(new_state)})
        end

        {:reply, {:ok, new_phase}, new_state, @idle_timeout}
    end
  end

  def handle_call({:join, _player_id, _side}, _from, state) do
    {:reply, {:error, :game_not_waiting}, state, @idle_timeout}
  end

  # ---------------------------------------------------------------------------
  # move
  # ---------------------------------------------------------------------------

  def handle_call({:move, player_id, from, to, opts}, _from, %{phase: :waiting} = state) do
    piece = Board.get(state.board, from)
    promote = Keyword.get(opts, :promote, false) or Board.must_promote?(piece, to, state.turn)

    with true <- player_id != nil,
         :ok <- check_turn(state, player_id),
         true <- state.players.sente == player_id and state.turn == :sente,
         true <- Rules.valid_move?(state.board, from, to, state.turn),
         {:ok, new_board, captured} <- Board.move(state.board, from, to, promote) do
      new_state = %{
        state
        | board: new_board,
          turn: next_turn(state.turn),
          move_count: state.move_count + 1,
          last_move: {:move, from, to, promote, captured}
      }

      broadcast(new_state, {:game_updated, public_state(new_state)})

      {:reply, {:ok, public_state(new_state)}, new_state, @idle_timeout}
    else
      false -> {:reply, {:error, :game_not_started}, state, @idle_timeout}
      {:error, reason} -> {:reply, {:error, reason}, state, @idle_timeout}
    end
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
      new_state =
        %{
          state
          | board: new_board,
            turn: next_turn(state.turn),
            move_count: state.move_count + 1,
            last_move: {:move, from, to, promote, captured}
        }
        |> restart_turn_timer()
        |> maybe_finish()

      broadcast(new_state, {:game_updated, public_state(new_state)})

      {:reply, {:ok, public_state(new_state)}, new_state, @idle_timeout}
    else
      false -> {:reply, {:error, :invalid_move}, state, @idle_timeout}
      {:error, reason} -> {:reply, {:error, reason}, state, @idle_timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # drop
  # ---------------------------------------------------------------------------

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
      new_state =
        %{
          state
          | board: new_board,
            turn: next_turn(state.turn),
            move_count: state.move_count + 1,
            last_move: {:drop, type, to}
        }
        |> restart_turn_timer()
        |> maybe_finish()

      broadcast(new_state, {:game_updated, public_state(new_state)})

      {:reply, {:ok, public_state(new_state)}, new_state, @idle_timeout}
    else
      false -> {:reply, {:error, :invalid_drop}, state, @idle_timeout}
      {:error, reason} -> {:reply, {:error, reason}, state, @idle_timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # state
  # ---------------------------------------------------------------------------

  def handle_call(:state, _from, state) do
    {:reply, public_state(state), state, @idle_timeout}
  end

  # ---------------------------------------------------------------------------
  # resign
  # ---------------------------------------------------------------------------

  def handle_call({:resign, player_id}, _from, %{phase: :playing} = state) do
    case side_of(state, player_id) do
      {:ok, side} ->
        winner = other_side(side)

        new_state =
          state
          |> cancel_turn_timer()
          |> then(&%{&1 | phase: :finished, winner: winner})

        broadcast(new_state, {:game_over, %{winner: winner, reason: :resignation}})
        {:reply, {:ok, winner}, new_state}

      :error ->
        {:reply, {:error, :not_a_player}, state, @idle_timeout}
    end
  end

  def handle_call({:resign, _player_id}, _from, state) do
    {:reply, {:error, :cannot_resign}, state, @idle_timeout}
  end

  # ---------------------------------------------------------------------------
  # handle_info
  # ---------------------------------------------------------------------------

  # Turno estourou — quem estava jogando perde
  @impl true
  def handle_info(:turn_timeout, %{phase: :playing} = state) do
    winner = other_side(state.turn)

    new_state = %{state | phase: :finished, winner: winner, turn_timer_ref: nil}

    broadcast(new_state, {:game_over, %{winner: winner, reason: :timeout}})
    {:noreply, new_state}
  end

  # Processo zumbi — nenhuma mensagem por @idle_timeout ms
  # Pode acontecer em :waiting (ninguém entrou) ou :finished (já acabou)
  def handle_info(:timeout, state) do
    if state.phase == :playing do
      # Segurança: não deveria chegar aqui com turn_timer ativo,
      # mas encerra limpo se chegar
      broadcast(state, {:game_over, %{winner: nil, reason: :abandoned}})
    end

    {:stop, :normal, state}
  end

  # Ignora mensagens de timer cancelado que chegam tarde
  def handle_info(_msg, state) do
    {:noreply, state, @idle_timeout}
  end

  # ---------------------------------------------------------------------------
  # Helpers privados — lógica de negócio
  # ---------------------------------------------------------------------------

  defp maybe_finish(state) do
    if Rules.checkmate?(state.board, state.turn) do
      winner = other_side(state.turn)

      state
      |> cancel_turn_timer()
      |> then(&%{&1 | phase: :finished, winner: winner})
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

  # ---------------------------------------------------------------------------
  # Helpers privados — timers
  # ---------------------------------------------------------------------------

  defp maybe_start_turn_timer(state, :playing), do: start_turn_timer(state)
  defp maybe_start_turn_timer(state, _phase), do: state

  defp start_turn_timer(state) do
    ref = Process.send_after(self(), :turn_timeout, @turn_timeout)
    %{state | turn_timer_ref: ref}
  end

  defp restart_turn_timer(state) do
    if state.turn_timer_ref, do: Process.cancel_timer(state.turn_timer_ref)
    start_turn_timer(state)
  end

  defp cancel_turn_timer(state) do
    if state.turn_timer_ref, do: Process.cancel_timer(state.turn_timer_ref)
    %{state | turn_timer_ref: nil}
  end

  # ---------------------------------------------------------------------------
  # Helpers privados — estado público
  # ---------------------------------------------------------------------------

  defp public_state(state) do
    %{
      game_id: state.game_id,
      board: state.board,
      turn: state.turn,
      phase: state.phase,
      winner: state.winner,
      move_count: state.move_count,
      last_move: state.last_move,
      time_left_seconds: time_left(state.turn_timer_ref)
    }
  end

  defp time_left(nil), do: nil

  defp time_left(ref) do
    case Process.read_timer(ref) do
      false -> 0
      ms -> div(ms, 1_000)
    end
  end

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(Shogi.PubSub, "game:#{state.game_id}", message)
  end

  defp via(game_id) do
    {:via, Registry, {Shogi.Game.Registry, game_id}}
  end
end
