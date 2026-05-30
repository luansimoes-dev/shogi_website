defmodule Shogi.Games do
  @moduledoc """
  Persistencia de partidas, jogadores e lances de shogi.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Shogi.Game.{Board, TimeControl}
  alias Shogi.Games.{GameMove, GamePlayer, GameRecord}
  alias Shogi.Repo

  require Logger

  def get_game_record_by_public_id(game_id) do
    Repo.get_by(GameRecord, game_id: game_id)
  end

  def get_game_record_by_public_id!(game_id) do
    Repo.get_by!(GameRecord, game_id: game_id)
  end

  def create_game_record(game_id, state) do
    attrs = game_attrs(game_id, state)

    %GameRecord{}
    |> GameRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :game_id
    )
  end

  def save_game_state(game_id, state) do
    case get_game_record_by_public_id(game_id) do
      nil -> create_game_record(game_id, state)
      record -> record |> GameRecord.changeset(game_attrs(game_id, state)) |> Repo.update()
    end
  end

  def add_or_update_player(game_id, player_id, side) do
    with %GameRecord{} = game <- get_game_record_by_public_id(game_id) do
      attrs = %{
        game_record_id: game.id,
        player_id: player_id,
        side: serialize_side(side),
        joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      %GamePlayer{}
      |> GamePlayer.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:player_id, :joined_at, :updated_at]},
        conflict_target: [:game_record_id, :side]
      )
    else
      nil -> {:error, :game_not_found}
    end
  end

  def record_move_and_update_game(game_id, move_attrs, new_state) do
    Multi.new()
    |> Multi.run(:game, fn repo, _changes ->
      case repo.get_by(GameRecord, game_id: game_id) do
        nil -> {:error, :game_not_found}
        game -> {:ok, game}
      end
    end)
    |> Multi.insert(:move, fn %{game: game} ->
      attrs =
        move_attrs
        |> stringify_move_attrs()
        |> Map.put(:game_record_id, game.id)
        |> Map.put(:clocks_after, serialize_clocks(new_state.clocks))
        |> Map.put(:board_after, serialize_board(new_state.board))

      GameMove.changeset(%GameMove{}, attrs)
    end)
    |> Multi.update(:game_update, fn %{game: game} ->
      GameRecord.changeset(game, game_attrs(game_id, new_state))
    end)
    |> maybe_update_player_results(new_state)
    |> Repo.transaction()
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, step, reason, _changes} ->
        Logger.error("failed to persist game #{game_id} at #{inspect(step)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def list_moves(game_id) do
    with %GameRecord{} = game <- get_game_record_by_public_id(game_id) do
      GameMove
      |> where([m], m.game_record_id == ^game.id)
      |> order_by([m], asc: m.move_number)
      |> Repo.all()
    else
      nil -> []
    end
  end

  def get_move(game_id, move_number) do
    with %GameRecord{} = game <- get_game_record_by_public_id(game_id) do
      Repo.get_by(GameMove, game_record_id: game.id, move_number: move_number)
    else
      nil -> nil
    end
  end

  def get_last_move(game_id) do
    with %GameRecord{} = game <- get_game_record_by_public_id(game_id),
         %GameMove{} = move <- last_move_record(game.id) do
      move_to_internal_last_move(move)
    else
      _ -> nil
    end
  end

  def restore_game_state(game_id) do
    with %GameRecord{} = game <- get_game_record_by_public_id(game_id),
         {:ok, state} <- deserialize_state(game.state) do
      {:ok, %{state | last_move: get_last_move(game_id)}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def serialize_state(state) do
    %{
      "schema_version" => 1,
      "game_id" => state.game_id,
      "board" => serialize_board(state.board),
      "turn" => serialize_side(state.turn),
      "phase" => serialize_atom(state.phase),
      "winner" => serialize_side(state.winner),
      "result_reason" => serialize_atom(state.result_reason),
      "resigned_by" => serialize_side(state.resigned_by),
      "timed_out_side" => serialize_side(state.timed_out_side),
      "time_control" => serialize_time_control(state.time_control),
      "clocks" => serialize_clocks(state.clocks),
      "players" => serialize_players(state.players),
      "move_count" => state.move_count
    }
  end

  def deserialize_state(map) when is_map(map) do
    with {:ok, board} <- deserialize_board(get_value(map, "board")),
         {:ok, turn} <- deserialize_side(get_value(map, "turn")),
         {:ok, phase} <- deserialize_phase(get_value(map, "phase")),
         {:ok, winner} <- deserialize_optional_side(get_value(map, "winner")),
         {:ok, resigned_by} <- deserialize_optional_side(get_value(map, "resigned_by")),
         {:ok, timed_out_side} <- deserialize_optional_side(get_value(map, "timed_out_side")),
         {:ok, result_reason} <-
           deserialize_optional_atom(get_value(map, "result_reason"), [
             nil,
             :checkmate,
             :resignation,
             :timeout
           ]),
         {:ok, players} <- deserialize_players(get_value(map, "players")),
         {:ok, clocks} <- deserialize_clocks(get_value(map, "clocks")) do
      {:ok,
       %Shogi.Game.Server{
         game_id: get_value(map, "game_id"),
         board: board,
         turn: turn,
         phase: phase,
         winner: winner,
         result_reason: result_reason,
         resigned_by: resigned_by,
         timed_out_side: timed_out_side,
         time_control: deserialize_time_control(get_value(map, "time_control")),
         clocks: clocks,
         active_turn_started_at: nil,
         clock_timer_ref: nil,
         players: players,
         move_count: get_value(map, "move_count") || 0,
         last_move: nil
       }}
    end
  end

  def deserialize_state(_map), do: {:error, :invalid_state}

  def serialize_board(board) do
    squares =
      board.squares
      |> Enum.map(fn {{row, col}, piece} ->
        %{
          "row" => row,
          "col" => col,
          "type" => serialize_atom(piece.type),
          "owner" => serialize_side(piece.owner),
          "promoted" => promoted_type?(piece.type)
        }
      end)
      |> Enum.sort_by(fn square -> {square["row"], square["col"]} end)

    %{
      "schema_version" => 1,
      "squares" => squares,
      "hands" => %{
        "sente" => Enum.map(board.hands.sente, &serialize_atom/1),
        "gote" => Enum.map(board.hands.gote, &serialize_atom/1)
      }
    }
  end

  def deserialize_board(%{} = map) do
    with {:ok, squares} <- deserialize_squares(get_value(map, "squares") || []),
         {:ok, hands} <- deserialize_hands(get_value(map, "hands") || %{}) do
      {:ok, %{squares: squares, hands: hands}}
    end
  end

  def deserialize_board(_map), do: {:error, :invalid_board}

  def serialize_side(nil), do: nil
  def serialize_side(side) when side in [:sente, :gote], do: Atom.to_string(side)

  def deserialize_side("sente"), do: {:ok, :sente}
  def deserialize_side("gote"), do: {:ok, :gote}
  def deserialize_side(:sente), do: {:ok, :sente}
  def deserialize_side(:gote), do: {:ok, :gote}
  def deserialize_side(_side), do: {:error, :invalid_side}

  def deserialize_optional_side(nil), do: {:ok, nil}
  def deserialize_optional_side(side), do: deserialize_side(side)

  defp game_attrs(game_id, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    finished? = state.phase == :finished

    %{
      game_id: game_id,
      status: serialize_atom(state.phase),
      winner_side: serialize_side(state.winner),
      result_reason: serialize_atom(state.result_reason),
      resigned_by: serialize_side(state.resigned_by),
      timed_out_side: serialize_side(state.timed_out_side),
      turn: serialize_side(state.turn),
      time_control: serialize_time_control(state.time_control),
      clocks: serialize_clocks(state.clocks),
      state: serialize_state(state),
      move_count: state.move_count,
      started_at: if(state.phase in [:playing, :finished], do: now),
      finished_at: if(finished?, do: now)
    }
  end

  defp stringify_move_attrs(attrs) do
    attrs
    |> Map.update(:side, nil, &serialize_side/1)
    |> Map.update(:kind, nil, &serialize_atom/1)
    |> Map.update(:piece_type, nil, &serialize_atom/1)
    |> Map.update(:captured_piece_type, nil, &serialize_atom/1)
    |> Map.update(:result_after, nil, &serialize_atom/1)
  end

  defp maybe_update_player_results(multi, %{phase: :finished, winner: winner})
       when winner in [:sente, :gote] do
    multi
    |> Multi.update_all(
      :winner_player,
      fn %{game: game} ->
        GamePlayer
        |> where([p], p.game_record_id == ^game.id and p.side == ^serialize_side(winner))
      end,
      set: [result: "win"]
    )
    |> Multi.update_all(
      :loser_player,
      fn %{game: game} ->
        GamePlayer
        |> where(
          [p],
          p.game_record_id == ^game.id and p.side == ^serialize_side(Board.opponent(winner))
        )
      end,
      set: [result: "loss"]
    )
  end

  defp maybe_update_player_results(multi, _state), do: multi

  defp last_move_record(game_record_id) do
    GameMove
    |> where([m], m.game_record_id == ^game_record_id)
    |> order_by([m], desc: m.move_number)
    |> limit(1)
    |> Repo.one()
  end

  defp move_to_internal_last_move(%GameMove{kind: "move"} = move) do
    {:move, {move.from_row, move.from_col}, {move.to_row, move.to_col}, move.promoted,
     deserialize_piece_type!(move.captured_piece_type)}
  end

  defp move_to_internal_last_move(%GameMove{kind: "drop"} = move) do
    {:drop, deserialize_piece_type!(move.piece_type), {move.to_row, move.to_col}}
  end

  defp move_to_internal_last_move(%GameMove{kind: kind}), do: String.to_atom(kind)

  defp serialize_atom(nil), do: nil
  defp serialize_atom(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp serialize_atom(value) when is_binary(value), do: value

  defp deserialize_phase("waiting"), do: {:ok, :waiting}
  defp deserialize_phase("playing"), do: {:ok, :playing}
  defp deserialize_phase("finished"), do: {:ok, :finished}
  defp deserialize_phase(:waiting), do: {:ok, :waiting}
  defp deserialize_phase(:playing), do: {:ok, :playing}
  defp deserialize_phase(:finished), do: {:ok, :finished}
  defp deserialize_phase(_phase), do: {:error, :invalid_phase}

  defp deserialize_optional_atom(nil, allowed),
    do: if(nil in allowed, do: {:ok, nil}, else: {:error, :invalid_atom})

  defp deserialize_optional_atom(value, allowed) do
    atom = deserialize_piece_type!(value)
    if atom in allowed, do: {:ok, atom}, else: {:error, :invalid_atom}
  end

  defp serialize_time_control(time_control) do
    %{
      "id" => time_control.id,
      "label" => time_control.label,
      "initial_seconds" => time_control.initial_seconds,
      "increment_seconds" => time_control.increment_seconds
    }
  end

  defp deserialize_time_control(nil), do: TimeControl.default()

  defp deserialize_time_control(map) do
    %{
      id: get_value(map, "id") || TimeControl.default_id(),
      label: get_value(map, "label") || TimeControl.default().label,
      initial_seconds: get_value(map, "initial_seconds") || TimeControl.default().initial_seconds,
      increment_seconds:
        get_value(map, "increment_seconds") || TimeControl.default().increment_seconds
    }
  end

  defp serialize_clocks(clocks) do
    %{"sente" => clocks.sente, "gote" => clocks.gote}
  end

  defp deserialize_clocks(map) when is_map(map) do
    {:ok, %{sente: get_value(map, "sente") || 0, gote: get_value(map, "gote") || 0}}
  end

  defp deserialize_clocks(_map), do: {:error, :invalid_clocks}

  defp serialize_players(players) do
    %{"sente" => players.sente, "gote" => players.gote}
  end

  defp deserialize_players(map) when is_map(map) do
    {:ok, %{sente: get_value(map, "sente"), gote: get_value(map, "gote")}}
  end

  defp deserialize_players(_map), do: {:error, :invalid_players}

  defp deserialize_squares(squares) when is_list(squares) do
    squares
    |> Enum.reduce_while({:ok, %{}}, fn square, {:ok, acc} ->
      with row when is_integer(row) <- get_value(square, "row"),
           col when is_integer(col) <- get_value(square, "col"),
           {:ok, owner} <- deserialize_side(get_value(square, "owner")),
           {:ok, type} <- deserialize_piece_type(get_value(square, "type")) do
        {:cont, {:ok, Map.put(acc, {row, col}, %{type: type, owner: owner})}}
      else
        _ -> {:halt, {:error, :invalid_square}}
      end
    end)
  end

  defp deserialize_squares(_squares), do: {:error, :invalid_squares}

  defp deserialize_hands(map) when is_map(map) do
    with {:ok, sente} <- deserialize_piece_list(get_value(map, "sente") || []),
         {:ok, gote} <- deserialize_piece_list(get_value(map, "gote") || []) do
      {:ok, %{sente: sente, gote: gote}}
    end
  end

  defp deserialize_hands(_map), do: {:error, :invalid_hands}

  defp deserialize_piece_list(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn type, {:ok, acc} ->
      case deserialize_piece_type(type) do
        {:ok, type} -> {:cont, {:ok, [type | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp deserialize_piece_type(type) do
    atom = deserialize_piece_type!(type)

    if atom in [
         :king,
         :rook,
         :bishop,
         :gold,
         :silver,
         :knight,
         :lance,
         :pawn,
         :promoted_rook,
         :promoted_bishop,
         :promoted_silver,
         :promoted_knight,
         :promoted_lance,
         :promoted_pawn
       ],
       do: {:ok, atom},
       else: {:error, :invalid_piece_type}
  end

  defp deserialize_piece_type!(nil), do: nil
  defp deserialize_piece_type!(type) when is_atom(type), do: type

  defp deserialize_piece_type!(type) when is_binary(type) do
    case type do
      "king" -> :king
      "rook" -> :rook
      "bishop" -> :bishop
      "gold" -> :gold
      "silver" -> :silver
      "knight" -> :knight
      "lance" -> :lance
      "pawn" -> :pawn
      "promoted_rook" -> :promoted_rook
      "promoted_bishop" -> :promoted_bishop
      "promoted_silver" -> :promoted_silver
      "promoted_knight" -> :promoted_knight
      "promoted_lance" -> :promoted_lance
      "promoted_pawn" -> :promoted_pawn
      "checkmate" -> :checkmate
      "resignation" -> :resignation
      "timeout" -> :timeout
      _ -> :invalid
    end
  end

  defp promoted_type?(type),
    do:
      type in [
        :promoted_rook,
        :promoted_bishop,
        :promoted_silver,
        :promoted_knight,
        :promoted_lance,
        :promoted_pawn
      ]

  defp get_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, String.to_atom(key))
end
