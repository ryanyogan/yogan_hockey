defmodule YoganHockey.Games do
  @moduledoc """
  Context module for managing completed game data.

  Provides functions to save and retrieve completed NHL games from the database.
  Game data is stored as JSON for flexibility with the complex nested structure.
  """

  import Ecto.Query, warn: false
  require Logger

  alias YoganHockey.Repo
  alias YoganHockey.Games.CompletedGame

  @doc """
  Gets a completed game by its ID.

  Returns nil if the game doesn't exist.
  """
  def get_completed_game(game_id) do
    Repo.get(CompletedGame, to_string(game_id))
  end

  @doc """
  Saves completed game data to the database.

  If a game with the same ID already exists, it will be replaced.
  """
  def save_completed_game(game_data) when is_map(game_data) do
    attrs = %{
      game_id: to_string(game_data.game_id),
      home_team_id: to_string(game_data.home_team.id),
      away_team_id: to_string(game_data.away_team.id),
      home_team_name: game_data.home_team.name,
      away_team_name: game_data.away_team.name,
      home_score: game_data.home_team.score,
      away_score: game_data.away_team.score,
      game_date: game_data.last_updated,
      game_data: game_data_to_map(game_data)
    }

    result =
      %CompletedGame{}
      |> CompletedGame.changeset(attrs)
      |> Repo.insert(on_conflict: :replace_all, conflict_target: :game_id)

    case result do
      {:ok, _game} ->
        Logger.info("Saved completed game #{attrs.game_id}")
        result

      {:error, changeset} ->
        Logger.error("Failed to save game #{attrs.game_id}: #{inspect(changeset.errors)}")
        result
    end
  end

  @doc """
  Returns a MapSet of game IDs where the given team played.

  Used to determine which past games in a team's schedule have data available.
  """
  def game_ids_for_team(team_id) do
    team_id_str = to_string(team_id)

    CompletedGame
    |> where([g], g.home_team_id == ^team_id_str or g.away_team_id == ^team_id_str)
    |> select([g], g.game_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns the count of completed games in the database.
  """
  def count_completed_games do
    Repo.aggregate(CompletedGame, :count)
  end

  @doc """
  Converts stored map data back to the game_data structure.

  Used when loading historical games to reconstruct the original format.
  """
  def map_to_game_data(%{"game_id" => _} = map) do
    %{
      game_id: map["game_id"],
      status: atomize_status(map["status"]),
      home_team: atomize_team(map["home_team"]),
      away_team: atomize_team(map["away_team"]),
      plays: Enum.map(map["plays"] || [], &atomize_play/1),
      boxscore: atomize_boxscore(map["boxscore"]),
      last_updated: parse_datetime(map["last_updated"])
    }
  end

  def map_to_game_data(_), do: nil

  # Private functions

  # Convert game_data struct/map to a plain map suitable for JSON storage
  defp game_data_to_map(game_data) do
    %{
      "game_id" => to_string(game_data.game_id),
      "status" => stringify_map(game_data.status),
      "home_team" => stringify_map(game_data.home_team),
      "away_team" => stringify_map(game_data.away_team),
      "plays" => Enum.map(game_data.plays || [], &stringify_map/1),
      "boxscore" => stringify_boxscore(game_data.boxscore),
      "last_updated" => DateTime.to_iso8601(game_data.last_updated)
    }
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {k, stringify_value(v)}
    end)
  end

  defp stringify_map(other), do: other

  defp stringify_value(v) when is_map(v), do: stringify_map(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v) when is_atom(v) and not is_nil(v) and not is_boolean(v), do: Atom.to_string(v)
  defp stringify_value(v), do: v

  defp stringify_boxscore(%{period_scores: scores} = boxscore) when is_map(boxscore) do
    %{
      "period_scores" => Enum.map(scores || [], &stringify_map/1)
    }
  end

  defp stringify_boxscore(boxscore), do: stringify_map(boxscore)

  defp atomize_status(nil), do: %{state: "post", period: 3, clock: "0:00", intermission: false, detail: "Final"}

  defp atomize_status(status) when is_map(status) do
    %{
      state: status["state"] || status[:state] || "post",
      period: status["period"] || status[:period] || 3,
      clock: status["clock"] || status[:clock] || "0:00",
      intermission: status["intermission"] || status[:intermission] || false,
      detail: status["detail"] || status[:detail] || "Final"
    }
  end

  defp atomize_team(nil), do: %{}

  defp atomize_team(team) when is_map(team) do
    %{
      id: team["id"] || team[:id],
      name: team["name"] || team[:name],
      abbreviation: team["abbreviation"] || team[:abbreviation],
      logo: team["logo"] || team[:logo],
      color: team["color"] || team[:color],
      score: team["score"] || team[:score] || 0,
      shots: team["shots"] || team[:shots] || 0,
      blocked: team["blocked"] || team[:blocked] || 0,
      hits: team["hits"] || team[:hits] || 0,
      faceoff_pct: team["faceoff_pct"] || team[:faceoff_pct],
      takeaways: team["takeaways"] || team[:takeaways] || 0,
      giveaways: team["giveaways"] || team[:giveaways] || 0,
      penalty_minutes: team["penalty_minutes"] || team[:penalty_minutes] || 0,
      powerplay_goals: team["powerplay_goals"] || team[:powerplay_goals],
      powerplay_opportunities: team["powerplay_opportunities"] || team[:powerplay_opportunities],
      power_play: team["power_play"] || team[:power_play]
    }
  end

  defp atomize_boxscore(nil), do: %{period_scores: []}

  defp atomize_boxscore(boxscore) when is_map(boxscore) do
    period_scores = boxscore["period_scores"] || boxscore[:period_scores] || []

    %{
      period_scores: Enum.map(period_scores, fn ps ->
        %{
          period: ps["period"] || ps[:period],
          home: ps["home"] || ps[:home] || 0,
          away: ps["away"] || ps[:away] || 0
        }
      end)
    }
  end

  defp atomize_play(play) when is_map(play) do
    # Explicitly convert play map keys - don't rely on atomize_keys which can fail
    # Access with both string and atom keys for robustness
    type_raw = play["type"] || play[:type]
    type =
      case type_raw do
        "goal" -> :goal
        "shot" -> :shot
        "penalty" -> :penalty
        "hit" -> :hit
        "faceoff" -> :faceoff
        :goal -> :goal
        :shot -> :shot
        :penalty -> :penalty
        :hit -> :hit
        :faceoff -> :faceoff
        other -> other
      end

    %{
      id: play["id"] || play[:id],
      type: type,
      period: play["period"] || play[:period],
      time: play["time"] || play[:time],
      team_id: play["team_id"] || play[:team_id],
      team_color: play["team_color"] || play[:team_color],
      description: play["description"] || play[:description],
      x: play["x"] || play[:x],
      y: play["y"] || play[:y],
      scoring: play["scoring"] || play[:scoring]
    }
  end

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(_), do: DateTime.utc_now()
end
