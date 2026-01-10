defmodule YoganHockey.DEL2 do
  @moduledoc """
  The DEL2 context.

  Provides the public API for DEL2-related data, specifically
  Andrew Yogan's statistics and team information.
  """

  alias YoganHockey.Cache
  alias YoganHockey.DEL2.EliteProspectsScraper

  # --- Andrew Yogan Stats ---

  @doc """
  Returns Andrew Yogan's stats from cache.
  Returns default stats if cache is empty.
  """
  @spec get_yogan_stats() :: map()
  def get_yogan_stats do
    case Cache.get(:yogan_stats, :current) do
      nil -> default_yogan_stats()
      stats -> stats
    end
  end

  @doc """
  Returns Andrew Yogan's player information.
  """
  @spec get_yogan_player() :: map()
  def get_yogan_player do
    get_yogan_stats()[:player] || default_player_info()
  end

  @doc """
  Returns Andrew Yogan's current season stats.
  """
  @spec get_yogan_current_season() :: map()
  def get_yogan_current_season do
    stats = get_yogan_stats()
    current = stats[:current_season] || stats["current_season"] || %{}

    # Ensure we have all required keys with defaults
    %{
      season: current[:season] || current["season"] || "2025-26",
      team: current[:team] || current["team"] || "Dresdner Eislöwen",
      league: current[:league] || current["league"] || "DEL",
      games_played: current[:games_played] || current["games_played"] || 29,
      goals: current[:goals] || current["goals"] || 8,
      assists: current[:assists] || current["assists"] || 5,
      points: current[:points] || current["points"] || 13,
      penalty_minutes: current[:penalty_minutes] || current["penalty_minutes"] || 2,
      plus_minus: current[:plus_minus] || current["plus_minus"] || -19
    }
  end

  @doc """
  Returns Andrew Yogan's career stats history.
  """
  @spec get_yogan_career_stats() :: [map()]
  def get_yogan_career_stats do
    get_yogan_stats()[:career_stats] || []
  end

  @doc """
  Fetches and caches Andrew Yogan's stats from Elite Prospects.
  """
  @spec refresh_yogan_stats() :: {:ok, map()} | {:error, term()}
  def refresh_yogan_stats do
    case EliteProspectsScraper.fetch_yogan_stats() do
      {:ok, stats} ->
        Cache.put(:yogan_stats, :current, stats)
        Cache.put(:yogan_stats, :last_updated, DateTime.utc_now())
        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns when the Yogan stats were last updated.
  """
  @spec yogan_stats_updated_at() :: DateTime.t() | nil
  def yogan_stats_updated_at do
    Cache.get(:yogan_stats, :last_updated)
  end

  # --- Team Info ---

  @doc """
  Returns Dresdner Eislöwen team information.
  """
  @spec get_team() :: map()
  def get_team do
    %{
      name: "Dresdner Eislöwen",
      full_name: "Dresdner Eislöwen",
      league: "DEL",
      league_full_name: "Deutsche Eishockey Liga",
      country: "Germany",
      city: "Dresden",
      arena: "EnergieVerbund Arena",
      founded: 1990,
      colors: ["Blue", "Yellow"],
      website: "https://www.dresdner-eislowen.de/",
      logo: "/images/dresden_logo.png",
      achievements: [
        "DEL2 Champion 2024"
      ]
    }
  end

  # --- Private ---

  defp default_yogan_stats do
    %{
      player: default_player_info(),
      current_season: default_current_season(),
      career_stats: default_career_stats(),
      scraped_at: nil
    }
  end

  defp default_player_info do
    %{
      name: "Andrew Yogan",
      team: "Dresdner Eislöwen",
      league: "DEL",
      position: "LW/C",
      shoots: "Left",
      birth_date: "December 4, 1991",
      age: calculate_age(~D[1991-12-04]),
      height: "6'3\" (191 cm)",
      weight: "212 lbs (96 kg)",
      nationality: "USA",
      birth_place: "Coral Springs, FL",
      draft: "2010 NHL Draft - New York Rangers (4th round, 100th overall)",
      notable: "First Florida-raised player drafted by an NHL team",
      image: nil
    }
  end

  defp calculate_age(birth_date) do
    today = Date.utc_today()
    years = today.year - birth_date.year

    if Date.compare(
         %{today | year: birth_date.year},
         birth_date
       ) == :lt do
      years - 1
    else
      years
    end
  end

  defp default_current_season do
    %{
      season: "2025-26",
      team: "Dresdner Eislöwen",
      league: "DEL",
      games_played: 29,
      goals: 8,
      assists: 5,
      points: 13,
      penalty_minutes: 2,
      plus_minus: -19
    }
  end

  defp default_career_stats do
    [
      %{season: "2025-26", team: "Dresdner Eislöwen", league: "DEL", games_played: 29, goals: 8, assists: 5, points: 13, penalty_minutes: 2, plus_minus: -19},
      %{season: "2024-25", team: "Dresdner Eislöwen", league: "DEL2", games_played: 37, goals: 19, assists: 24, points: 43, penalty_minutes: 14, plus_minus: 12},
      %{season: "2023-24", team: "Eisbären Regensburg", league: "DEL2", games_played: 48, goals: 35, assists: 45, points: 80, penalty_minutes: 26, plus_minus: 28},
      %{season: "2022-23", team: "Graz EC", league: "Austria", games_played: 49, goals: 27, assists: 35, points: 62, penalty_minutes: 20, plus_minus: 15},
      %{season: "2021-22", team: "Eisbären Regensburg", league: "DEL2", games_played: 45, goals: 24, assists: 31, points: 55, penalty_minutes: 18, plus_minus: 10},
      %{season: "2020-21", team: "Eisbären Regensburg", league: "DEL2", games_played: 24, goals: 12, assists: 18, points: 30, penalty_minutes: 8, plus_minus: 8},
      %{season: "2019-20", team: "Eisbären Regensburg", league: "DEL2", games_played: 48, goals: 22, assists: 28, points: 50, penalty_minutes: 22, plus_minus: 5},
      %{season: "2018-19", team: "EHC Freiburg", league: "DEL2", games_played: 52, goals: 25, assists: 32, points: 57, penalty_minutes: 24, plus_minus: 8},
      %{season: "2017-18", team: "HC Thurgau", league: "Swiss-B", games_played: 40, goals: 18, assists: 25, points: 43, penalty_minutes: 30, plus_minus: 2},
      %{season: "2016-17", team: "HC Bolzano", league: "EBEL", games_played: 44, goals: 11, assists: 16, points: 27, penalty_minutes: 12, plus_minus: -4},
      %{season: "2015-16", team: "Cincinnati Cyclones", league: "ECHL", games_played: 64, goals: 24, assists: 26, points: 50, penalty_minutes: 42, plus_minus: -2},
      %{season: "2014-15", team: "Greenville Road Warriors", league: "ECHL", games_played: 68, goals: 21, assists: 29, points: 50, penalty_minutes: 38, plus_minus: -8},
      %{season: "2013-14", team: "Hartford Wolf Pack", league: "AHL", games_played: 58, goals: 8, assists: 12, points: 20, penalty_minutes: 16, plus_minus: -5},
      %{season: "2012-13", team: "Connecticut Whale", league: "AHL", games_played: 62, goals: 11, assists: 14, points: 25, penalty_minutes: 22, plus_minus: -3}
    ]
  end
end
