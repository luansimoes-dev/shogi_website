defmodule Shogi.Game.TimeControlTest do
  use ExUnit.Case, async: true

  alias Shogi.Game.TimeControl

  test "3_0 returns 180 seconds and no increment" do
    assert {:ok, time_control} = TimeControl.fetch("3_0")
    assert time_control.initial_seconds == 180
    assert time_control.increment_seconds == 0
  end

  test "10_2 returns 600 seconds and 2 second increment" do
    assert {:ok, time_control} = TimeControl.fetch("10_2")
    assert time_control.initial_seconds == 600
    assert time_control.increment_seconds == 2
  end

  test "invalid id returns error" do
    assert {:error, :invalid_time_control} = TimeControl.fetch("bullet_freeform")
  end
end
