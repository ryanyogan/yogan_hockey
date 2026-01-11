defmodule YoganHockey.DEL2.EliteProspectsScraper do
  @moduledoc """
  Scrapes Andrew Yogan's statistics from HockeyDB and team schedule from Elite Prospects.

  HockeyDB provides reliable, structured HTML tables for player stats.
  Elite Prospects provides team schedule data.
  """

  # HockeyDB is more reliable for scraping - simpler HTML structure
  @hockeydb_url "https://www.hockeydb.com/ihdb/stats/pdisplay.php?pid=106875"
  @elite_prospects_url "https://www.eliteprospects.com/player/13839/andrew-yogan"
  # Dresden Ice Lions full season schedule (completed games)
  @team_schedule_url "https://www.eliteprospects.com/games/2025-2026/del/983/dresdner-eislowen?from=&to="
  # Team stats page (has upcoming games)
  @team_stats_url "https://www.eliteprospects.com/team/983/dresdner-eislowen?tab=stats"

  require Logger

  @doc """
  Returns the configured HTTP adapter module.
  """
  def http_adapter do
    Application.get_env(:yogan_hockey, :http_adapter, YoganHockey.HTTP.ReqAdapter)
  end

  @doc """
  Scrapes Andrew Yogan's stats from HockeyDB (primary) or Elite Prospects (fallback).
  """
  @spec fetch_yogan_stats() :: {:ok, map()} | {:error, term()}
  def fetch_yogan_stats do
    case fetch_from_hockeydb() do
      {:ok, stats} ->
        {:ok, stats}

      {:error, _reason} ->
        Logger.info("HockeyDB failed, trying Elite Prospects")
        fetch_from_elite_prospects()
    end
  end

  @doc """
  Fetches the team schedule for Dresdner Eislöwen from Elite Prospects.
  Combines full schedule (past games) with team stats page (upcoming games).
  """
  @spec fetch_team_schedule() :: {:ok, map()} | {:error, term()}
  def fetch_team_schedule do
    # Fetch full schedule (past games)
    past_games = case http_adapter().get_html(@team_schedule_url) do
      {:ok, html} ->
        document = Floki.parse_document!(html)
        find_games_in_document(document)
      {:error, _} -> []
    end

    # Fetch team stats page (upcoming games)
    upcoming_games = case http_adapter().get_html(@team_stats_url) do
      {:ok, html} ->
        document = Floki.parse_document!(html)
        fallback_find_games(document)
        |> Enum.filter(fn g -> g.result == :upcoming end)
      {:error, _} -> []
    end

    now = DateTime.utc_now()

    # Split past games by date (in case some are actually upcoming)
    {past, additional_upcoming} =
      past_games
      |> Enum.split_with(fn game ->
        case game.date_raw do
          nil -> true
          dt -> DateTime.compare(dt, now) == :lt
        end
      end)

    all_upcoming = (additional_upcoming ++ upcoming_games)
      |> Enum.uniq_by(fn g -> {g.date, g.opponent} end)
      |> Enum.sort_by(& &1.date_raw, {:asc, DateTime})

    {:ok, %{
      team: "Dresdner Eislöwen",
      league: "DEL",
      past_games: past |> Enum.sort_by(& &1.date_raw, {:desc, DateTime}),
      upcoming_games: all_upcoming,
      scraped_at: DateTime.utc_now()
    }}
  rescue
    e ->
      Logger.warning("Failed to fetch team schedule: #{inspect(e)}")
      {:error, e}
  end

  defp find_games_in_document(document) do
    # Find the games table (contains td.date elements)
    all_tables = Floki.find(document, "table")

    games_table = Enum.find(all_tables, fn table ->
      Floki.find(table, "td.date") != []
    end)

    case games_table do
      nil ->
        # Fallback to old method for team stats page
        fallback_find_games(document)

      table ->
        # Parse the games table rows
        table
        |> Floki.find("tr")
        |> Enum.map(&parse_games_table_row/1)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp fallback_find_games(document) do
    # Fallback for the team stats page (5 most recent games)
    document
    |> Floki.find("table tbody tr")
    |> Enum.map(&parse_schedule_game_fallback/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_games_table_row(row) do
    # Full schedule page format:
    # td.date[data-date], td.team (home), td.team (away), td.result, td.league
    date_cell = Floki.find(row, "td.date") |> List.first()
    team_cells = Floki.find(row, "td.team")
    result_cell = Floki.find(row, "td.result") |> List.first()

    with date when not is_nil(date) <- date_cell,
         [home_cell, away_cell] <- team_cells,
         result when not is_nil(result) <- result_cell do

      # Get date from data-date attribute (ISO 8601 format)
      date_str = Floki.attribute(date, "data-date") |> List.first() || ""
      home_team = Floki.text(home_cell) |> String.trim()
      away_team = Floki.text(away_cell) |> String.trim()
      score = Floki.text(result) |> String.trim()

      build_game_from_iso(date_str, home_team, away_team, score)
    else
      _ -> nil
    end
  end

  defp build_game_from_iso(datetime_str, home_team, away_team, score) do
    # Parse ISO 8601 datetime like "2026-01-10T17:00:00+0100"
    date_raw = parse_iso_datetime(datetime_str)

    # Format date for display
    date_display = case date_raw do
      nil -> datetime_str
      dt -> Calendar.strftime(dt, "%b %d, %Y")
    end

    {our_score, opp_score, is_home, opponent} =
      determine_game_details(home_team, away_team, score)

    %{
      date: date_display,
      date_raw: date_raw,
      opponent: opponent,
      is_home: is_home,
      our_score: our_score,
      opponent_score: opp_score,
      result: determine_result(our_score, opp_score)
    }
  end

  defp parse_iso_datetime(datetime_str) do
    # Parse "2026-01-10T17:00:00+0100" format
    case DateTime.from_iso8601(datetime_str) do
      {:ok, dt, _offset} -> dt
      _ ->
        # Try without timezone
        case NaiveDateTime.from_iso8601(datetime_str) do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp parse_schedule_game_fallback(row) do
    cells =
      row
      |> Floki.find("td")
      |> Enum.map(fn td -> Floki.text(td) |> String.trim() end)

    # Team stats page format: [datetime, home, away, score, league]
    case cells do
      [datetime_str, home_team, away_team, score, _league | _]
      when byte_size(datetime_str) > 0 ->
        date_str = extract_date_from_datetime(datetime_str)
        build_game(date_str, home_team, away_team, score)

      _ ->
        nil
    end
  end

  defp extract_date_from_datetime(datetime_str) do
    # Extract MM/DD/YYYY from "01/18/202603:30 PM UTC"
    case Regex.run(~r/^(\d{2}\/\d{2}\/\d{4})/, datetime_str) do
      [_, date] -> date
      _ -> datetime_str
    end
  end

  defp build_game(date_str, home_team, away_team, score) do
    # Validate this looks like a date
    unless looks_like_date?(date_str), do: throw(:not_a_date)

    {our_score, opp_score, is_home, opponent} =
      determine_game_details(home_team, away_team, score)

    %{
      date: date_str,
      date_raw: parse_game_date(date_str),
      opponent: opponent,
      is_home: is_home,
      our_score: our_score,
      opponent_score: opp_score,
      result: determine_result(our_score, opp_score)
    }
  catch
    :not_a_date -> nil
  end

  defp looks_like_date?(str) do
    # Check for common date patterns: MM/DD/YYYY, YYYY-MM-DD, Mon DD, etc.
    Regex.match?(~r/^\d{1,2}\/\d{1,2}\/\d{4}$/, str) or
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, str) or
      Regex.match?(~r/^[A-Za-z]{3}\s+\d{1,2}/, str)
  end

  defp determine_game_details(home_team, away_team, score) do
    home_team_clean = String.trim(home_team)
    away_team_clean = String.trim(away_team)
    is_dresden_home = String.contains?(String.downcase(home_team_clean), "dresden") or
                      String.contains?(String.downcase(home_team_clean), "eislöwen") or
                      String.contains?(String.downcase(home_team_clean), "eislowen")

    # Handle score formats: "2 - 3", "2-3", "2 - 3(OT 60:14)", "-" (upcoming game)
    # Strip OT/SO info in parentheses first
    score_base = Regex.replace(~r/\(.*\)/, score, "")
    score_clean = String.replace(score_base, " ", "")

    [home_score, away_score] =
      case String.split(score_clean, "-") do
        [h, a] when h != "" and a != "" -> [parse_int(h), parse_int(a)]
        _ -> [nil, nil]  # Upcoming game or invalid score
      end

    if is_dresden_home do
      {home_score, away_score, true, away_team_clean}
    else
      {away_score, home_score, false, home_team_clean}
    end
  end

  defp determine_result(nil, _), do: :upcoming
  defp determine_result(_, nil), do: :upcoming
  defp determine_result(our_score, opp_score) do
    cond do
      our_score > opp_score -> :win
      our_score < opp_score -> :loss
      true -> :tie
    end
  end

  defp parse_game_date(date_str) do
    # Try various date formats
    date_str = String.trim(date_str)

    # Try "01/10/2026" MM/DD/YYYY format (Elite Prospects)
    with [m, d, y] <- String.split(date_str, "/"),
         {month, ""} <- Integer.parse(m),
         {day, ""} <- Integer.parse(d),
         {year, ""} <- Integer.parse(y),
         {:ok, date} <- Date.new(year, month, day) do
      DateTime.new!(date, ~T[19:00:00], "Etc/UTC")
    else
      _ ->
        # Try "Jan 10, 2026" format
        case Timex.parse(date_str, "{Mshort} {D}, {YYYY}") do
          {:ok, dt} ->
            DateTime.new!(Date.from_erl!(NaiveDateTime.to_erl(dt) |> elem(0)), ~T[19:00:00], "Etc/UTC")

          _ ->
            # Try "2026-01-10" ISO format
            case Date.from_iso8601(date_str) do
              {:ok, date} -> DateTime.new!(date, ~T[19:00:00], "Etc/UTC")
              _ -> nil
            end
        end
    end
  rescue
    _ -> nil
  end

  defp fetch_from_hockeydb do
    case http_adapter().get_html(@hockeydb_url) do
      {:ok, html} ->
        {:ok, parse_hockeydb_page(html)}

      {:error, reason} ->
        Logger.warning("Failed to fetch HockeyDB page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_from_elite_prospects do
    case http_adapter().get_html(@elite_prospects_url) do
      {:ok, html} ->
        {:ok, parse_elite_prospects_page(html)}

      {:error, reason} ->
        Logger.error("Failed to fetch Elite Prospects page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- HockeyDB Parser ---

  defp parse_hockeydb_page(html) do
    document = Floki.parse_document!(html)

    career_stats = parse_hockeydb_career_stats(document)
    current_season = List.first(career_stats) || default_current_season()

    %{
      player: parse_hockeydb_player_info(document, current_season),
      current_season: current_season,
      career_stats: career_stats,
      scraped_at: DateTime.utc_now()
    }
  end

  defp parse_hockeydb_player_info(document, current_season) do
    # HockeyDB has player name in title or h1
    name =
      document
      |> Floki.find("title")
      |> Floki.text()
      |> String.trim()
      |> String.replace(" Hockey Stats and Profile at hockeydb.com", "")
      |> case do
        "" -> "Andrew Yogan"
        n -> n
      end

    # Extract team from current season
    team = current_season[:team] || "Dresdner Eislöwen"
    league = current_season[:league] || "DEL"

    %{
      name: name,
      team: team,
      league: league,
      position: "LW/C",
      shoots: "Left",
      birth_date: "December 4, 1991",
      height: "6'3\" (191 cm)",
      weight: "212 lbs (96 kg)",
      nationality: "USA",
      birth_place: "Coral Springs, FL",
      draft: "2010 NHL Draft - New York Rangers (4th round, 100th overall)"
    }
  end

  defp parse_hockeydb_career_stats(document) do
    # HockeyDB uses tables with class "multitable" or standard tables
    # Find all stat rows - look for rows with season data
    document
    |> Floki.find("table tr")
    |> Enum.map(&parse_hockeydb_stat_row/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn row -> {row.season, row.team, row.league} end)
    |> Enum.sort_by(fn row -> row.season end, :desc)
  end

  defp parse_hockeydb_stat_row(row) do
    cells =
      row
      |> Floki.find("td")
      |> Enum.map(fn td -> Floki.text(td) |> String.trim() end)

    # HockeyDB format: Season, Team, League, GP, G, A, Pts, +/-, PIM
    # Sometimes has extra columns for playoffs
    case cells do
      [season, team, league, gp, g, a, pts | rest] when byte_size(season) >= 4 ->
        # Check if this looks like a valid season (e.g., "2025-26" or "2024-25")
        if Regex.match?(~r/^\d{4}-\d{2}$/, season) do
          # Find +/- and PIM from rest
          {plus_minus, pim} = extract_plus_minus_pim(rest)

          %{
            season: season,
            team: clean_team_name(team),
            league: clean_league_name(league),
            games_played: parse_int(gp),
            goals: parse_int(g),
            assists: parse_int(a),
            points: parse_int(pts),
            plus_minus: plus_minus,
            penalty_minutes: pim
          }
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp extract_plus_minus_pim(rest) do
    # HockeyDB format: Season, Team, Lge, GP, G, A, Pts, PIM, +/-
    # So after [season, team, league, gp, g, a, pts | rest], rest = [pim, +/-, ...]
    case rest do
      [pim_str, pm_str | _] ->
        {parse_int(pm_str), parse_int(pim_str)}

      [pim_str] ->
        {0, parse_int(pim_str)}

      [] ->
        {0, 0}
    end
  end

  defp clean_team_name(team) do
    team
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/[🏆🥇🥈🥉]/, "")
    |> String.trim()
  end

  defp clean_league_name(league) do
    league
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # --- Elite Prospects Parser (Fallback) ---

  defp parse_elite_prospects_page(html) do
    document = Floki.parse_document!(html)

    %{
      player: parse_ep_player_info(document),
      current_season: parse_ep_current_season(document),
      career_stats: parse_ep_career_stats(document),
      scraped_at: DateTime.utc_now()
    }
  end

  defp parse_ep_player_info(document) do
    name =
      document
      |> Floki.find("h1")
      |> Floki.text()
      |> String.trim()
      |> case do
        "" -> "Andrew Yogan"
        n -> n
      end

    team =
      document
      |> Floki.find(".plytitle a")
      |> Floki.text()
      |> String.trim()
      |> case do
        "" -> "Dresdner Eislöwen"
        t -> t
      end

    %{
      name: name,
      team: team,
      league: "DEL",
      position: "LW/C",
      shoots: "Left",
      birth_date: "December 4, 1991",
      height: "6'3\" (191 cm)",
      weight: "212 lbs (96 kg)",
      nationality: "USA",
      birth_place: "Coral Springs, FL",
      draft: "2010 NHL Draft - New York Rangers (4th round, 100th overall)"
    }
  end

  defp parse_ep_current_season(document) do
    document
    |> Floki.find("table tbody tr")
    |> List.first()
    |> parse_ep_stat_row()
    |> case do
      nil -> default_current_season()
      row -> row
    end
  end

  defp parse_ep_career_stats(document) do
    document
    |> Floki.find("table tbody tr")
    |> Enum.map(&parse_ep_stat_row/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_ep_stat_row(nil), do: nil

  defp parse_ep_stat_row(row) do
    cells =
      row
      |> Floki.find("td")
      |> Enum.map(fn td -> Floki.text(td) |> String.trim() end)

    case cells do
      [season, team, league, gp, g, a, pts, pm | rest] ->
        plus_minus = List.first(rest) || "0"

        %{
          season: season,
          team: team,
          league: league,
          games_played: parse_int(gp),
          goals: parse_int(g),
          assists: parse_int(a),
          points: parse_int(pts),
          penalty_minutes: parse_int(pm),
          plus_minus: parse_int(plus_minus)
        }

      _ ->
        nil
    end
  end

  # --- Helpers ---

  defp default_current_season do
    %{
      season: "2025-26",
      team: "Dresdner Eislöwen",
      league: "DEL",
      games_played: 0,
      goals: 0,
      assists: 0,
      points: 0,
      penalty_minutes: 0,
      plus_minus: 0
    }
  end

  defp parse_int(str) when is_binary(str) do
    str
    |> String.replace(~r/[^\d\-]/, "")
    |> case do
      "" -> 0
      "-" -> 0
      num -> String.to_integer(num)
    end
  rescue
    _ -> 0
  end

  defp parse_int(_), do: 0
end
