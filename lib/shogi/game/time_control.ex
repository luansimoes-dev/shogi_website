defmodule Shogi.Game.TimeControl do
  @moduledoc """
  Whitelist dos ritmos de tempo disponiveis para partidas.
  """

  @default_id "10_2"

  @time_controls %{
    "3_0" => %{id: "3_0", label: "3 + 0", initial_seconds: 180, increment_seconds: 0},
    "5_0" => %{id: "5_0", label: "5 + 0", initial_seconds: 300, increment_seconds: 0},
    "10_2" => %{id: "10_2", label: "10 + 2", initial_seconds: 600, increment_seconds: 2},
    "15_10" => %{id: "15_10", label: "15 + 10", initial_seconds: 900, increment_seconds: 10}
  }

  def default_id, do: @default_id

  def default, do: Map.fetch!(@time_controls, @default_id)

  def all do
    ["3_0", "5_0", "10_2", "15_10"]
    |> Enum.map(&Map.fetch!(@time_controls, &1))
  end

  def fetch(id) when is_binary(id) do
    case Map.fetch(@time_controls, id) do
      {:ok, time_control} -> {:ok, time_control}
      :error -> {:error, :invalid_time_control}
    end
  end

  def fetch(_id), do: {:error, :invalid_time_control}

  def get(id) do
    case fetch(id) do
      {:ok, time_control} -> time_control
      {:error, _reason} -> default()
    end
  end
end
