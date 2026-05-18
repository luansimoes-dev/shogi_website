defmodule Shogi.Matchmaking.Queue do
  @moduledoc """
  Lógica pura da fila de matchmaking.
  Não tem estado próprio — é chamada pelo Server.
  """

  @type player_id :: String.t()
  @type t :: [player_id()]

  def new, do: []

  def enqueue(queue, player_id) do
    if player_id in queue do
      {:error, :already_queued}
    else
      {:ok, queue ++ [player_id]}
    end
  end

  def dequeue([player1, player2 | rest]), do: {:matched, player1, player2, rest}
  def dequeue(_), do: :waiting

  def remove(queue, player_id), do: List.delete(queue, player_id)

  def size(queue), do: length(queue)

  def member?(queue, player_id), do: player_id in queue
end
