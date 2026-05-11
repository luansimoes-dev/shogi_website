defmodule Shogi.Game.Server do
  @moduledoc """
  GenServer responsável pelo estado e ciclo de vida de uma partida.

  Cada partida roda em um processo isolado, identificado por um `game_id`.
  A lógica pura (validação, movimentos) fica em Rules e Board —
  este módulo só gerencia estado e transições de fase.

  ## Uso

      {:ok, pid} = Shogi.Game.Server.start_link(game_id: "abc123")

      Shogi.Game.Server.join(pid, "player1", :sente)
      Shogi.Game.Server.join(pid, "player2", :gote)

      Shogi.Game.Server.move(pid, "player1", {7, 7}, {7, 6})
  """

  use GenServer

  alias Shogi.Game.{Board, Rules}

  # Tempo máximo de inatividade antes de encerrar o processo (10 minutos)
  @idle_timeout 10 * 60 * 1_000

  # ---------------------------------------------------------------------------
  # Estado interno
  # ---------------------------------------------------------------------------

  defstruct [
    :game_id,
    :board,
    :turn,          # :sente | :gote — quem joga agora
    :phase,         # :waiting | :playing | :finished
    :winner,        # :sente | :gote | nil
    :players,       # %{sente: player_id, gote: player_id}
    :move_count,
    :last_move      # {from, to} | nil
  ]

  # ---------------------------------------------------------------------------
  # API pública
  # ---------------------------------------------------------------------------

  @doc "Inicia um processo de partida. Passa `game_id:` como opção."
  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, game_id, name: via(game_id))
  end

  @doc "Um jogador entra na partida escolhendo seu lado (:sente ou :gote)."
  def join(game_id, player_id, side) when side in [:sente, :gote] do
    GenServer.call(via(game_id), {:join, player_id, side})
  end

  @doc "Realiza um movimento. Retorna :ok ou {:error, motivo}."
  def move(game_id, player_id, from, to) do
    GenServer.call(via(game_id), {:move, player_id, from, to})
  end

  @doc "Retorna o estado atual da partida (para LiveView ou debug)."
  def state(game_id) do
    GenServer.call(via(game_id), :state)
  end

  @doc "Encerra a partida explicitamente (abandono, timeout externo, etc)."
  def resign(game_id, player_id) do
    GenServer.call(via(game_id), {:resign, player_id})
  end

  # ---------------------------------------------------------------------------
  # Callbacks do GenServer
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
      last_move: nil
    }

    {:ok, state, @idle_timeout}
  end

  # --- join ---

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
        new_state = %{state | players: new_players, phase: new_phase}
        {:reply, {:ok, new_phase}, new_state, @idle_timeout}
    end
  end

  def handle_call({:join, _player_id, _side}, _from, state) do
    {:reply, {:error, :game_not_waiting}, state, @idle_timeout}
  end

  # --- move ---

  def handle_call({:move, _player_id, _from, _to}, _from, %{phase: :waiting} = state) do
    {:reply, {:error, :game_not_started}, state, @idle_timeout}
  end

  def handle_call({:move, _player_id, _from, _to}, _from, %{phase: :finished} = state) do
    {:reply, {:error, :game_finished}, state, @idle_timeout}
  end

  def handle_call({:move, player_id, from, to}, _from, %{phase: :playing} = state) do
    with :ok <- check_turn(state, player_id),
         true <- Rules.valid_move?(state.board, from, to, state.turn),
         {:ok, new_board} <- Board.move(state.board, from, to) do

      new_state =
        state
        |> Map.put(:board, new_board)
        |> Map.put(:turn, next_turn(state.turn))
        |> Map.put(:move_count, state.move_count + 1)
        |> Map.put(:last_move, {from, to})
        |> maybe_finish()

      {:reply, {:ok, new_state}, new_state, @idle_timeout}
    else
      false -> {:reply, {:error, :invalid_move}, state, @idle_timeout}
      {:error, reason} -> {:reply, {:error, reason}, state, @idle_timeout}
    end
  end

  # --- state ---

  def handle_call(:state, _from, state) do
    {:reply, state, state, @idle_timeout}
  end

  # --- resign ---

  def handle_call({:resign, player_id}, _from, %{phase: :playing} = state) do
    case side_of(state, player_id) do
      {:ok, side} ->
        winner = other_side(side)
        new_state = %{state | phase: :finished, winner: winner}
        {:reply, {:ok, winner}, new_state}

      :error ->
        {:reply, {:error, :not_a_player}, state, @idle_timeout}
    end
  end

  def handle_call({:resign, _player_id}, _from, state) do
    {:reply, {:error, :cannot_resign}, state, @idle_timeout}
  end

  # --- timeout de inatividade ---

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  # ---------------------------------------------------------------------------
  # Helpers privados
  # ---------------------------------------------------------------------------

  defp via(game_id) do
    {:via, Registry, {Shogi.Game.Registry, game_id}}
  end

  defp both_joined?(%{sente: s, gote: g}), do: s != nil and g != nil

  defp player_already_joined?(state, player_id) do
    state.players.sente == player_id or state.players.gote == player_id
  end

  defp check_turn(state, player_id) do
    if state.players[state.turn] == player_id do
      :ok
    else
      {:error, :not_your_turn}
    end
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

  # Ponto de extensão: detectar xeque-mate e encerrar a partida.
  # Por enquanto retorna o estado sem modificação —
  # adicione aqui a chamada para Rules.checkmate?/2 quando implementar.
  defp maybe_finish(state) do
    state
    # Exemplo futuro:
    # if Rules.checkmate?(state.board, state.turn) do
    #   %{state | phase: :finished, winner: other_side(state.turn)}
    # else
    #   state
    # end
  end
end
