defmodule YoganHockey.DEL2.EliteProspectsScraper do
  @moduledoc """
  Scrapes Andrew Yogan's statistics from HockeyDB.

  HockeyDB provides reliable, structured HTML tables for player stats.
  Falls back to Elite Prospects if HockeyDB fails.
  """

  # HockeyDB is more reliable for scraping - simpler HTML structure
  @hockeydb_url "https://www.hockeydb.com/ihdb/stats/pdisplay.php?pid=106875"
  @elite_prospects_url "https://www.eliteprospects.com/player/13839/andrew-yogan"

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
