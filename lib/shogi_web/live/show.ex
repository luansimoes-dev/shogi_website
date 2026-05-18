defmodule ShogiWeb.GameLive.Show do
  use ShogiWeb, :live_view

  alias Shogi.Game.Server

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Shogi.PubSub, "game:#{game_id}")
    end

    case Server.start_link(game_id: game_id) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok,
     socket
     |> assign(:game_id, game_id)
     |> assign(:player_id, nil)
     |> assign(:side, nil)
     |> assign(:selected, nil)
     |> assign(:game, Server.state(game_id))}
  end

  @impl true
  def handle_event("join", %{"side" => side}, socket) do
    side = String.to_existing_atom(side)
    player_id = "player-" <> Integer.to_string(System.unique_integer([:positive]))

    case Server.join(socket.assigns.game_id, player_id, side) do
      {:ok, _phase} ->
        {:noreply,
         socket
         |> assign(:player_id, player_id)
         |> assign(:side, side)
         |> assign(:game, Server.state(socket.assigns.game_id))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  @impl true
  def handle_event("square", %{"col" => col, "row" => row}, socket) do
    pos = {String.to_integer(col), String.to_integer(row)}

    case socket.assigns.selected do
      nil ->
        {:noreply, assign(socket, :selected, pos)}

      from ->
        Server.move(socket.assigns.game_id, socket.assigns.player_id, from, pos)

        {:noreply,
         socket
         |> assign(:selected, nil)
         |> assign(:game, Server.state(socket.assigns.game_id))}
    end
  end

  @impl true
  def handle_info({:game_updated, game}, socket) do
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info({:game_started, game}, socket) do
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info({:game_over, _info}, socket) do
    {:noreply, assign(socket, :game, Server.state(socket.assigns.game_id))}
  end

  defp piece_symbol(%{type: :king}), do: "王"
  defp piece_symbol(%{type: :rook}), do: "飛"
  defp piece_symbol(%{type: :bishop}), do: "角"
  defp piece_symbol(%{type: :gold}), do: "金"
  defp piece_symbol(%{type: :silver}), do: "銀"
  defp piece_symbol(%{type: :knight}), do: "桂"
  defp piece_symbol(%{type: :lance}), do: "香"
  defp piece_symbol(%{type: :pawn}), do: "歩"

  defp piece_symbol(%{type: :promoted_rook}), do: "龍"
  defp piece_symbol(%{type: :promoted_bishop}), do: "馬"
  defp piece_symbol(%{type: :promoted_silver}), do: "全"
  defp piece_symbol(%{type: :promoted_knight}), do: "圭"
  defp piece_symbol(%{type: :promoted_lance}), do: "杏"
  defp piece_symbol(%{type: :promoted_pawn}), do: "と"

  defp piece_symbol(_), do: "?"
end
