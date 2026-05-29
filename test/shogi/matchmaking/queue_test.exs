defmodule Shogi.Matchmaking.QueueTest do
  use ExUnit.Case, async: true

  alias Shogi.Matchmaking.Queue

  test "empty queue receives first player and waits" do
    assert {:ok, queue} = Queue.enqueue(Queue.new(), "player-1")
    assert Queue.member?(queue, "player-1")
    assert Queue.dequeue(queue) == :waiting
  end

  test "second player generates match" do
    {:ok, queue} = Queue.enqueue(Queue.new(), "player-1")
    {:ok, queue} = Queue.enqueue(queue, "player-2")

    assert {:matched, "player-1", "player-2", []} = Queue.dequeue(queue)
  end

  test "same player is not duplicated or matched with self" do
    {:ok, queue} = Queue.enqueue(Queue.new(), "player-1")

    assert {:error, :already_queued} = Queue.enqueue(queue, "player-1")
    assert Queue.dequeue(queue) == :waiting
  end

  test "cancel removes player from queue" do
    {:ok, queue} = Queue.enqueue(Queue.new(), "player-1")
    queue = Queue.remove(queue, "player-1")

    refute Queue.member?(queue, "player-1")
    assert Queue.size(queue) == 0
  end
end
