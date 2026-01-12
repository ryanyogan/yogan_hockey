defmodule YoganHockey.Playoffs do
  @moduledoc """
  Context for NHL Playoffs data and AI predictions.

  Provides functions to fetch playoff bracket data and generate
  AI-powered predictions for each series matchup.
  """

  require Logger

  alias YoganHockey.{Cache, NHL, Anthropic}
  alias YoganHockey.NHL.APIClient

  @doc """
  Gets the playoff picture prediction (which teams make playoffs and advancement probabilities).
  Returns cached data if available.
  """
  @spec get_playoff_picture() :: {:ok, map()} | {:error, term()}
  def get_playoff_picture do
    case Cache.get(:playoffs, :playoff_picture) do
      nil ->
        generate_playoff_picture()

      cached ->
        {:ok, cached}
    end
  end

  @doc """
  Forces a regeneration of the playoff picture prediction.
  """
  @spec refresh_playoff_picture() :: {:ok, map()} | {:error, term()}
  def refresh_playoff_picture do
    Cache.delete(:playoffs, :playoff_picture)
    generate_playoff_picture()
  end

  @doc """
  Generates playoff picture predictions based on current standings.
  """
  @spec generate_playoff_picture() :: {:ok, map()} | {:error, term()}
  def generate_playoff_picture do
    standings = NHL.list_standings()

    if Enum.empty?(standings) do
      Logger.warning("No standings data available for playoff picture")
      {:error, :no_standings_data}
    else
      case Anthropic.predict_playoff_picture(standings) do
        {:ok, prediction} ->
          # Enrich with team logos and additional data
          enriched = enrich_playoff_picture(prediction)
          Cache.put(:playoffs, :playoff_picture, enriched)
          {:ok, enriched}

        {:error, reason} ->
          Logger.error("Failed to generate playoff picture: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp enrich_playoff_picture(prediction) do
    teams = NHL.list_teams()
    teams_by_id = Map.new(teams, fn t -> {to_string(t.id), t} end)

    %{
      prediction
      | eastern: enrich_conference_teams(prediction.eastern, teams_by_id),
        western: enrich_conference_teams(prediction.western, teams_by_id)
    }
  end

  defp enrich_conference_teams(teams, teams_by_id) do
    Enum.map(teams, fn team ->
      case Map.get(teams_by_id, team.team_id) do
        nil ->
          team

        team_data ->
          Map.merge(team, %{
            logo: team_data.logo,
            abbreviation: team_data.abbreviation,
            color: team_data[:color]
          })
      end
    end)
  end

  @doc """
  Gets the current playoff bracket.
  Returns cached data if available.
  """
  @spec get_bracket() :: {:ok, map()} | {:error, term()}
  def get_bracket do
    case Cache.get(:playoffs, :bracket) do
      nil ->
        refresh_bracket()

      cached ->
        {:ok, cached}
    end
  end

  @doc """
  Forces a refresh of the playoff bracket from the API.
  """
  @spec refresh_bracket() :: {:ok, map()} | {:error, term()}
  def refresh_bracket do
    case fetch_bracket_from_api() do
      {:ok, bracket} ->
        Cache.put(:playoffs, :bracket, bracket)
        Cache.put(:playoffs, :last_updated, DateTime.utc_now())
        {:ok, bracket}

      {:error, reason} ->
        Logger.warning("Failed to fetch playoff bracket: #{inspect(reason)}")
        # Return sample bracket if API fails
        {:ok, sample_bracket()}
    end
  end

  @doc """
  Gets a prediction for a specific series.
  Returns cached prediction if available and not stale.
  """
  @spec get_prediction(String.t()) :: {:ok, map()} | {:error, term()}
  def get_prediction(series_id) do
    case Cache.get(:playoffs_predictions, series_id) do
      nil ->
        generate_prediction(series_id)

      cached ->
        {:ok, cached}
    end
  end

  @doc """
  Gets all predictions for the current bracket.
  """
  @spec get_all_predictions() :: map()
  def get_all_predictions do
    {:ok, bracket} = get_bracket()

    bracket.rounds
    |> Enum.flat_map(& &1.matchups)
    |> Enum.filter(&(&1.home && &1.away))
    |> Enum.reduce(%{}, fn matchup, acc ->
      case Cache.get(:playoffs_predictions, matchup.id) do
        nil -> acc
        prediction -> Map.put(acc, matchup.id, prediction)
      end
    end)
  end

  @doc """
  Forces a refresh of a prediction (e.g., after a game completes).
  """
  @spec refresh_prediction(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh_prediction(series_id) do
    Cache.delete(:playoffs_predictions, series_id)
    generate_prediction(series_id)
  end

  @doc """
  Generates predictions for all active series in the bracket.
  """
  @spec generate_all_predictions() :: :ok
  def generate_all_predictions do
    {:ok, bracket} = get_bracket()

    bracket.rounds
    |> Enum.flat_map(& &1.matchups)
    |> Enum.filter(&(&1.home && &1.away && &1.status != :completed))
    |> Enum.each(fn matchup ->
      case get_prediction(matchup.id) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to generate prediction for #{matchup.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  # --- Private Functions ---

  defp fetch_bracket_from_api do
    # Try to get playoff data from ESPN
    # During playoffs, use seasontype=3 for postseason
    case APIClient.http_adapter().get_json("http://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?seasontype=3&limit=100") do
      {:ok, %{"events" => events}} when is_list(events) and length(events) > 0 ->
        bracket = parse_playoff_events(events)
        {:ok, bracket}

      {:ok, _} ->
        # No playoff games, return empty/sample bracket
        {:error, :no_playoff_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_playoff_events(events) do
    # Group events by round based on the series information
    # ESPN includes round info in the competition notes
    games_by_series =
      events
      |> Enum.group_by(fn event ->
        # Try to extract series ID from event
        get_in(event, ["competitions", Access.at(0), "series", "uid"]) ||
          get_in(event, ["uid"])
      end)

    # Build bracket structure from grouped games
    %{
      rounds: build_rounds_from_games(games_by_series),
      season: extract_season(events),
      last_updated: DateTime.utc_now()
    }
  end

  defp build_rounds_from_games(games_by_series) do
    # Try to categorize series by round number
    series_list =
      games_by_series
      |> Enum.map(fn {series_id, games} ->
        first_game = List.first(games)
        competition = get_in(first_game, ["competitions", Access.at(0)]) || %{}
        series_info = competition["series"] || %{}

        round_num = series_info["playoffRound"] || 1

        home_team = find_team_in_competition(competition, "home")
        away_team = find_team_in_competition(competition, "away")

        %{
          id: series_id || "series_#{:erlang.unique_integer([:positive])}",
          round: round_num,
          home: home_team,
          away: away_team,
          home_wins: count_wins(games, home_team),
          away_wins: count_wins(games, away_team),
          status: determine_series_status(series_info, games),
          games: length(games)
        }
      end)
      |> Enum.group_by(& &1.round)

    # Build standard 4-round structure
    [
      %{
        name: "First Round",
        round_num: 1,
        matchups: Map.get(series_list, 1, []) |> pad_matchups(8)
      },
      %{
        name: "Second Round",
        round_num: 2,
        matchups: Map.get(series_list, 2, []) |> pad_matchups(4)
      },
      %{
        name: "Conference Finals",
        round_num: 3,
        matchups: Map.get(series_list, 3, []) |> pad_matchups(2)
      },
      %{
        name: "Stanley Cup Final",
        round_num: 4,
        matchups: Map.get(series_list, 4, []) |> pad_matchups(1)
      }
    ]
  end

  defp find_team_in_competition(competition, home_away) do
    competitors = competition["competitors"] || []

    case Enum.find(competitors, &(&1["homeAway"] == home_away)) do
      nil ->
        nil

      competitor ->
        team = competitor["team"] || %{}

        %{
          id: team["id"],
          name: team["displayName"] || team["name"],
          abbreviation: team["abbreviation"],
          logo: team["logo"],
          seed: competitor["seed"]
        }
    end
  end

  defp count_wins(_games, nil), do: 0

  defp count_wins(games, team) do
    Enum.count(games, fn game ->
      competition = get_in(game, ["competitions", Access.at(0)]) || %{}

      Enum.any?(competition["competitors"] || [], fn c ->
        c["team"]["id"] == team.id && c["winner"] == true
      end)
    end)
  end

  defp determine_series_status(series_info, _games) do
    case series_info["completed"] do
      true -> :completed
      _ -> :in_progress
    end
  end

  defp extract_season(events) do
    case List.first(events) do
      nil -> "2024-25"
      event -> get_in(event, ["season", "displayName"]) || "2024-25"
    end
  end

  defp pad_matchups(matchups, target_count) do
    current_count = length(matchups)

    if current_count >= target_count do
      Enum.take(matchups, target_count)
    else
      empty_matchups =
        Enum.map(1..(target_count - current_count), fn i ->
          %{
            id: "tbd_#{:erlang.unique_integer([:positive])}_#{i}",
            home: nil,
            away: nil,
            home_wins: 0,
            away_wins: 0,
            status: :pending
          }
        end)

      matchups ++ empty_matchups
    end
  end

  defp generate_prediction(series_id) do
    with {:ok, bracket} <- get_bracket(),
         {:ok, matchup} <- find_matchup(bracket, series_id),
         {:ok, home_team_data} <- get_team_with_stats(matchup.home.id),
         {:ok, away_team_data} <- get_team_with_stats(matchup.away.id),
         {:ok, prediction} <- Anthropic.predict_series_outcome(home_team_data, away_team_data) do
      prediction = Map.put(prediction, :series_id, series_id)
      Cache.put(:playoffs_predictions, series_id, prediction)
      {:ok, prediction}
    else
      {:error, :matchup_not_found} ->
        {:error, :matchup_not_found}

      {:error, :teams_not_set} ->
        {:error, :teams_not_set}

      {:error, reason} ->
        Logger.warning("Failed to generate prediction for #{series_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_matchup(bracket, series_id) do
    matchup =
      bracket.rounds
      |> Enum.flat_map(& &1.matchups)
      |> Enum.find(&(&1.id == series_id))

    case matchup do
      nil -> {:error, :matchup_not_found}
      %{home: nil} -> {:error, :teams_not_set}
      %{away: nil} -> {:error, :teams_not_set}
      matchup -> {:ok, matchup}
    end
  end

  defp get_team_with_stats(team_id) do
    # Try to get team details with stats
    case NHL.get_team_details(team_id) do
      {:ok, team} ->
        # Also try to get standings data for more context
        standings_data = get_standings_for_team(team_id)
        {:ok, Map.merge(team, standings_data)}

      error ->
        error
    end
  end

  defp get_standings_for_team(team_id) do
    team_id_str = to_string(team_id)

    case NHL.list_standings() do
      standings when is_list(standings) ->
        team_standing =
          standings
          |> Enum.flat_map(fn group ->
            (group["entries"] || group[:entries] || [])
          end)
          |> Enum.find(fn entry ->
            team = entry["team"] || entry[:team] || %{}
            to_string(team["id"] || team[:id]) == team_id_str
          end)

        case team_standing do
          nil ->
            %{}

          standing ->
            stats = standing["stats"] || standing[:stats] || []

            %{
              stats: parse_standings_stats(stats),
              conference_rank: get_stat_value(stats, "playoffSeed"),
              division_rank: get_stat_value(stats, "divisionRank")
            }
        end

      _ ->
        %{}
    end
  end

  defp parse_standings_stats(stats) do
    %{
      wins: get_stat_value(stats, "wins"),
      losses: get_stat_value(stats, "losses"),
      ot_losses: get_stat_value(stats, "otLosses"),
      points: get_stat_value(stats, "points"),
      goals_for: get_stat_value(stats, "pointsFor"),
      goals_against: get_stat_value(stats, "pointsAgainst"),
      goal_diff: get_stat_value(stats, "differential")
    }
  end

  defp get_stat_value(stats, name) do
    case Enum.find(stats, &(&1["name"] == name || &1[:name] == name)) do
      nil -> nil
      stat -> stat["value"] || stat[:value]
    end
  end

  @doc """
  Returns a sample bracket for display when playoffs aren't active.
  """
  def sample_bracket do
    teams = NHL.list_teams()

    # Get top 16 teams or create placeholder data
    top_teams =
      if length(teams) >= 16 do
        teams
        |> Enum.take(16)
        |> Enum.map(fn team ->
          %{
            id: team.id,
            name: team.name,
            abbreviation: team.abbreviation,
            logo: team.logo,
            seed: nil
          }
        end)
      else
        create_sample_teams()
      end

    # Create bracket structure with sample matchups
    %{
      rounds: [
        %{
          name: "First Round",
          round_num: 1,
          matchups: create_matchups(top_teams, 0, 8, 1)
        },
        %{
          name: "Second Round",
          round_num: 2,
          matchups: create_empty_matchups(4, 2)
        },
        %{
          name: "Conference Finals",
          round_num: 3,
          matchups: create_empty_matchups(2, 3)
        },
        %{
          name: "Stanley Cup Final",
          round_num: 4,
          matchups: create_empty_matchups(1, 4)
        }
      ],
      season: "2024-25",
      last_updated: DateTime.utc_now(),
      is_sample: true
    }
  end

  defp create_sample_teams do
    sample_names = [
      {"1", "Florida Panthers", "FLA"},
      {"2", "Boston Bruins", "BOS"},
      {"3", "Toronto Maple Leafs", "TOR"},
      {"4", "Tampa Bay Lightning", "TBL"},
      {"5", "Carolina Hurricanes", "CAR"},
      {"6", "New York Rangers", "NYR"},
      {"7", "New Jersey Devils", "NJD"},
      {"8", "Washington Capitals", "WSH"},
      {"9", "Dallas Stars", "DAL"},
      {"10", "Colorado Avalanche", "COL"},
      {"11", "Winnipeg Jets", "WPG"},
      {"12", "Edmonton Oilers", "EDM"},
      {"13", "Vancouver Canucks", "VAN"},
      {"14", "Vegas Golden Knights", "VGK"},
      {"15", "Los Angeles Kings", "LAK"},
      {"16", "Nashville Predators", "NSH"}
    ]

    Enum.map(sample_names, fn {id, name, abbrev} ->
      %{
        id: id,
        name: name,
        abbreviation: abbrev,
        logo: nil,
        seed: String.to_integer(id)
      }
    end)
  end

  defp create_matchups(teams, start_idx, count, round_num) do
    Enum.map(0..(count - 1), fn i ->
      home_idx = start_idx + (i * 2)
      away_idx = start_idx + (i * 2) + 1

      home = Enum.at(teams, home_idx)
      away = Enum.at(teams, away_idx)

      %{
        id: "r#{round_num}m#{i + 1}",
        home: home,
        away: away,
        home_wins: 0,
        away_wins: 0,
        status: :scheduled
      }
    end)
  end

  defp create_empty_matchups(count, round_num) do
    Enum.map(1..count, fn i ->
      %{
        id: "r#{round_num}m#{i}",
        home: nil,
        away: nil,
        home_wins: 0,
        away_wins: 0,
        status: :pending
      }
    end)
  end
end
