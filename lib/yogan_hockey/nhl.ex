defmodule YoganHockey.NHL do
  @moduledoc """
  The NHL context.

  Provides the public API for NHL-related data including games, teams,
  standings, and live scores. Data is fetched from ESPN's API and
  cached in ETS for fast access.
  """

  alias YoganHockey.Cache
  alias YoganHockey.NHL.APIClient

  # --- Live Scores ---

  @doc """
  Returns the current live scores and today's games.
  Fetches from cache, or API if not cached.
  """
  @spec list_live_scores() :: [map()]
  def list_live_scores do
    case Cache.get(:nhl_live_scores, :current) do
      nil -> []
      scores -> scores
    end
  end

  @doc """
  Fetches and caches the latest scoreboard data.
  Returns the list of games.
  """
  @spec refresh_live_scores() :: {:ok, [map()]} | {:error, term()}
  def refresh_live_scores do
    case APIClient.get_scoreboard() do
      {:ok, data} ->
        games = parse_scoreboard(data)
        Cache.put(:nhl_live_scores, :current, games)
        Cache.put(:nhl_live_scores, :last_updated, DateTime.utc_now())
        {:ok, games}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns when the live scores were last updated.
  """
  @spec live_scores_updated_at() :: DateTime.t() | nil
  def live_scores_updated_at do
    Cache.get(:nhl_live_scores, :last_updated)
  end

  # --- Teams ---

  @doc """
  Returns all NHL teams from cache.
  """
  @spec list_teams() :: [map()]
  def list_teams do
    case Cache.get(:nhl_teams, :all) do
      nil -> []
      teams -> teams
    end
  end

  @doc """
  Gets a specific team by ID.
  """
  @spec get_team(String.t() | integer()) :: map() | nil
  def get_team(team_id) do
    team_id = to_string(team_id)

    list_teams()
    |> Enum.find(&(to_string(&1.id) == team_id))
  end

  @doc """
  Gets detailed team info including roster and stats.
  """
  @spec get_team_details(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_team_details(team_id) do
    cache_key = {:team_details, to_string(team_id)}

    case Cache.get(:nhl_team_stats, cache_key) do
      nil ->
        case APIClient.get_team(team_id) do
          {:ok, data} ->
            team = parse_team_details(data)
            Cache.put(:nhl_team_stats, cache_key, team)
            {:ok, team}

          {:error, reason} ->
            {:error, reason}
        end

      cached ->
        {:ok, cached}
    end
  end

  @doc """
  Fetches and caches all NHL teams.
  """
  @spec refresh_teams() :: {:ok, [map()]} | {:error, term()}
  def refresh_teams do
    case APIClient.get_teams() do
      {:ok, data} ->
        teams = parse_teams(data)
        Cache.put(:nhl_teams, :all, teams)
        Cache.put(:nhl_teams, :last_updated, DateTime.utc_now())
        {:ok, teams}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Team Schedule ---

  @doc """
  Gets a team's schedule (past and upcoming games).
  """
  @spec get_team_schedule(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_team_schedule(team_id) do
    cache_key = {:team_schedule, to_string(team_id)}

    case Cache.get(:nhl_team_stats, cache_key) do
      nil ->
        case APIClient.get_team_schedule(team_id) do
          {:ok, data} ->
            schedule = parse_team_schedule(data)
            Cache.put(:nhl_team_stats, cache_key, schedule)
            {:ok, schedule}

          {:error, reason} ->
            {:error, reason}
        end

      cached ->
        {:ok, cached}
    end
  end

  # --- Players ---

  @doc """
  Gets a player by ID, using cache if available.
  Returns {:ok, player} or {:error, reason}.
  """
  @spec get_player(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_player(player_id) do
    player_id = to_string(player_id)
    cache_key = {:player, player_id}

    cached = Cache.get(:player_cache, cache_key)

    # Only use cache if it's a full player record (has career_seasons)
    if cached && is_full_player_record?(cached) do
      {:ok, cached}
    else
      fetch_and_cache_player(player_id, cache_key)
    end
  end

  defp is_full_player_record?(player) do
    # Full player records have career_seasons from the stats API
    Map.has_key?(player, :career_seasons) && Map.has_key?(player, :birth_date)
  end

  defp fetch_and_cache_player(player_id, cache_key) do
    with {:ok, data} <- APIClient.get_player(player_id),
         {:ok, stats_data} <- APIClient.get_player_stats(player_id) do
      player = parse_player(data)
      career_seasons = parse_career_seasons(stats_data)
      player = Map.put(player, :career_seasons, career_seasons)
      Cache.put(:player_cache, cache_key, player)
      {:ok, player}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets multiple players by their IDs.
  Returns a list of players (skips any that fail to load).
  """
  @spec get_players([String.t() | integer()]) :: [map()]
  def get_players(player_ids) when is_list(player_ids) do
    player_ids
    |> Enum.map(&get_player/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, player} -> player end)
  end

  @doc """
  Searches for players by name.
  Returns search results (does not cache as full player data).
  """
  @spec search_players(String.t()) :: {:ok, [map()]} | {:error, term()}
  def search_players(query) when is_binary(query) and byte_size(query) >= 2 do
    case APIClient.search_players(query) do
      {:ok, data} ->
        players = parse_search_results(data)
        {:ok, players}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def search_players(_query), do: {:ok, []}

  # --- Standings ---

  @doc """
  Returns NHL standings from cache.
  """
  @spec list_standings() :: [map()]
  def list_standings do
    case Cache.get(:nhl_standings, :current) do
      nil -> []
      standings -> standings
    end
  end

  @doc """
  Fetches and caches NHL standings.
  """
  @spec refresh_standings() :: {:ok, [map()]} | {:error, term()}
  def refresh_standings do
    case APIClient.get_standings() do
      {:ok, data} ->
        standings = parse_standings(data)
        Cache.put(:nhl_standings, :current, standings)
        Cache.put(:nhl_standings, :last_updated, DateTime.utc_now())
        {:ok, standings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Parsers ---

  defp parse_scoreboard(%{"events" => events}) when is_list(events) do
    Enum.map(events, &parse_game/1)
  end

  defp parse_scoreboard(_), do: []

  defp parse_game(event) do
    competitions = event["competitions"] || []
    competition = List.first(competitions) || %{}
    competitors = competition["competitors"] || []

    [home, away] =
      case competitors do
        [c1, c2] ->
          if c1["homeAway"] == "home", do: [c1, c2], else: [c2, c1]

        _ ->
          [%{}, %{}]
      end

    status = competition["status"] || %{}
    status_type = status["type"] || %{}

    %{
      id: event["id"],
      name: event["name"],
      short_name: event["shortName"],
      date: event["date"],
      status: %{
        state: status_type["state"],
        detail: status_type["shortDetail"] || status_type["detail"],
        period: status["period"],
        display_clock: status["displayClock"],
        completed: status_type["completed"]
      },
      home_team: parse_competitor(home),
      away_team: parse_competitor(away),
      venue: parse_venue(competition["venue"]),
      broadcasts: parse_broadcasts(competition["broadcasts"])
    }
  end

  defp parse_competitor(competitor) do
    team = competitor["team"] || %{}

    %{
      id: team["id"],
      name: team["name"],
      abbreviation: team["abbreviation"],
      display_name: team["displayName"],
      logo: team["logo"],
      color: team["color"],
      score: competitor["score"],
      winner: competitor["winner"],
      records: parse_records(competitor["records"])
    }
  end

  defp parse_records(nil), do: nil

  defp parse_records(records) when is_list(records) do
    Enum.reduce(records, %{}, fn record, acc ->
      Map.put(acc, record["type"], record["summary"])
    end)
  end

  defp parse_venue(nil), do: nil

  defp parse_venue(venue) do
    %{
      name: venue["fullName"],
      city: venue["address"]["city"],
      state: venue["address"]["state"]
    }
  end

  defp parse_broadcasts(nil), do: []

  defp parse_broadcasts(broadcasts) when is_list(broadcasts) do
    Enum.flat_map(broadcasts, fn b ->
      (b["names"] || [])
    end)
  end

  defp parse_teams(%{"sports" => [%{"leagues" => [%{"teams" => teams}]}]}) do
    Enum.map(teams, fn %{"team" => team} ->
      %{
        id: team["id"],
        name: team["name"],
        abbreviation: team["abbreviation"],
        display_name: team["displayName"],
        short_display_name: team["shortDisplayName"],
        nickname: team["nickname"],
        location: team["location"],
        logo: team["logos"] |> List.first() |> Access.get("href"),
        color: team["color"],
        alternate_color: team["alternateColor"],
        links: parse_team_links(team["links"])
      }
    end)
  end

  defp parse_teams(_), do: []

  defp parse_team_links(nil), do: %{}

  defp parse_team_links(links) when is_list(links) do
    Enum.reduce(links, %{}, fn link, acc ->
      Map.put(acc, link["rel"] |> List.first(), link["href"])
    end)
  end

  defp parse_team_details(%{"team" => team}) do
    %{
      id: team["id"],
      name: team["name"],
      abbreviation: team["abbreviation"],
      display_name: team["displayName"],
      location: team["location"],
      logo: team["logos"] |> List.first() |> Access.get("href"),
      color: team["color"],
      record: parse_team_record(team["record"]),
      next_event: parse_next_event(team["nextEvent"]),
      roster: parse_roster(team["athletes"])
    }
  end

  defp parse_team_details(data), do: data

  defp parse_team_record(%{"items" => items}) when is_list(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      Map.put(acc, item["type"], item["summary"])
    end)
  end

  defp parse_team_record(_), do: %{}

  defp parse_next_event(nil), do: nil

  defp parse_next_event([event | _]) do
    %{
      id: event["id"],
      date: event["date"],
      name: event["name"],
      short_name: event["shortName"]
    }
  end

  defp parse_next_event(_), do: nil

  defp parse_roster(nil), do: []

  defp parse_roster(athletes) when is_list(athletes) do
    Enum.map(athletes, fn athlete ->
      %{
        id: athlete["id"],
        name: athlete["fullName"],
        display_name: athlete["displayName"],
        jersey: athlete["jersey"],
        position: get_in(athlete, ["position", "abbreviation"]),
        headshot: get_in(athlete, ["headshot", "href"])
      }
    end)
  end

  defp parse_standings(%{"children" => conferences}) when is_list(conferences) do
    Enum.flat_map(conferences, fn conference ->
      conf_name = conference["name"] || ""

      # Check if divisions exist (old format) or standings at conference level (new format)
      cond do
        # New format: standings at conference level
        conference["standings"] != nil ->
          standings = conference["standings"]
          entries = standings["entries"] || []

          Enum.map(entries, fn entry ->
            team = entry["team"] || %{}
            logos = team["logos"] || []

            %{
              conference: conf_name,
              division: conf_name,  # Use conference as division for display
              team: %{
                id: team["id"],
                name: team["name"],
                abbreviation: team["abbreviation"],
                display_name: team["displayName"],
                logo: get_logo_href(logos)
              },
              stats: parse_standing_stats(entry["stats"])
            }
          end)

        # Old format: divisions under conference
        conference["children"] != nil ->
          divisions = conference["children"] || []

          Enum.flat_map(divisions, fn division ->
            div_name = division["name"]
            standings = division["standings"] || %{}
            entries = standings["entries"] || []

            Enum.map(entries, fn entry ->
              team = entry["team"] || %{}
              logos = team["logos"] || []

              %{
                conference: conf_name,
                division: div_name,
                team: %{
                  id: team["id"],
                  name: team["name"],
                  abbreviation: team["abbreviation"],
                  display_name: team["displayName"],
                  logo: get_logo_href(logos)
                },
                stats: parse_standing_stats(entry["stats"])
              }
            end)
          end)

        true ->
          []
      end
    end)
  end

  # Handle alternative format where standings are at root level
  defp parse_standings(%{"standings" => standings_data}) do
    parse_standings(standings_data)
  end

  defp parse_standings(_), do: []

  defp get_logo_href([first | _]) when is_map(first), do: first["href"]
  defp get_logo_href(_), do: nil

  defp parse_standing_stats(nil), do: %{}

  defp parse_standing_stats(stats) when is_list(stats) do
    Enum.reduce(stats, %{}, fn stat, acc ->
      Map.put(acc, stat["name"], stat["value"])
    end)
  end

  # --- Schedule Parsing ---

  defp parse_team_schedule(%{"events" => events, "team" => team}) when is_list(events) do
    team_id = to_string(team["id"])

    games = Enum.map(events, fn event -> parse_schedule_game(event, team_id) end)

    # Sort by date and split into past/future
    now = DateTime.utc_now()

    # Filter out games with nil dates, then sort
    valid_games = Enum.filter(games, fn g -> g.date_raw != nil end)

    {past, upcoming} =
      valid_games
      |> Enum.sort_by(& &1.date_raw, DateTime)
      |> Enum.split_with(fn game ->
        DateTime.compare(game.date_raw, now) == :lt
      end)

    %{
      team_id: team_id,
      team_name: team["displayName"],
      record: team["recordSummary"],
      standing: team["standingSummary"],
      past_games: Enum.reverse(past),
      upcoming_games: upcoming
    }
  end

  defp parse_team_schedule(_), do: %{past_games: [], upcoming_games: [], record: nil, standing: nil}

  defp parse_schedule_game(event, team_id) do
    competition = List.first(event["competitions"] || []) || %{}
    competitors = competition["competitors"] || []
    status = competition["status"] || %{}
    status_type = status["type"] || %{}

    # Find our team and the opponent
    {our_team, opponent} =
      case competitors do
        [c1, c2] ->
          if to_string(c1["id"]) == team_id do
            {c1, c2}
          else
            {c2, c1}
          end
        _ ->
          {%{}, %{}}
      end

    date_raw = parse_date(event["date"])

    opponent_team = opponent["team"] || %{}
    opponent_logos = opponent_team["logos"] || []

    %{
      id: event["id"],
      date: event["date"],
      date_raw: date_raw,
      date_display: status_type["shortDetail"] || status_type["detail"],
      is_home: our_team["homeAway"] == "home",
      status: %{
        state: status_type["state"],
        detail: status_type["shortDetail"] || status_type["detail"],
        completed: status_type["completed"] || false
      },
      our_score: parse_score(our_team["score"]),
      opponent_score: parse_score(opponent["score"]),
      winner: our_team["winner"],
      opponent: %{
        id: opponent_team["id"],
        name: opponent_team["displayName"] || opponent_team["name"],
        abbreviation: opponent_team["abbreviation"],
        logo: get_logo_href(opponent_logos),
        color: opponent_team["color"]
      }
    }
  end

  defp parse_score(nil), do: nil
  defp parse_score(%{"value" => v}) when is_number(v), do: trunc(v)
  defp parse_score(%{"displayValue" => v}) when is_binary(v), do: String.to_integer(v)
  defp parse_score(s) when is_number(s), do: trunc(s)
  defp parse_score(_), do: nil

  # Parse dates that may be missing seconds (e.g., "2025-10-07T21:00Z")
  defp parse_date(nil), do: nil
  defp parse_date(date_string) when is_binary(date_string) do
    # Try standard ISO8601 first
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> dt
      _ ->
        # Try adding seconds if missing (2025-10-07T21:00Z -> 2025-10-07T21:00:00Z)
        fixed = Regex.replace(~r/T(\d{2}):(\d{2})Z$/, date_string, "T\\1:\\2:00Z")
        case DateTime.from_iso8601(fixed) do
          {:ok, dt, _} -> dt
          _ -> nil
        end
    end
  end
  defp parse_date(_), do: nil

  # --- Player Parsing ---

  defp parse_player(%{"athlete" => athlete}) do
    team = athlete["team"] || %{}
    position = athlete["position"] || %{}
    current_stats = parse_stats_summary(athlete["statsSummary"])

    %{
      id: to_string(athlete["id"]),
      name: athlete["displayName"] || athlete["fullName"],
      first_name: athlete["firstName"],
      last_name: athlete["lastName"],
      jersey: athlete["jersey"],
      position: position["abbreviation"] || position["name"],
      position_name: position["name"],
      team: %{
        id: to_string(team["id"] || ""),
        name: team["displayName"] || team["name"],
        abbreviation: team["abbreviation"],
        logo: get_team_logo(team)
      },
      headshot: get_headshot(athlete),
      birth_date: athlete["dateOfBirth"],
      birth_place: parse_birth_place(athlete["birthPlace"]),
      height: athlete["displayHeight"],
      weight: athlete["displayWeight"],
      shoots: get_in(athlete, ["hand", "displayValue"]),
      status: get_in(athlete, ["status", "type"]),
      current_season_stats: current_stats
    }
  end

  defp parse_player(_), do: nil

  # Parse statsSummary from main player API
  defp parse_stats_summary(%{"statistics" => stats}) when is_list(stats) do
    stats_map =
      stats
      |> Enum.map(fn stat -> {stat["name"], stat["value"]} end)
      |> Enum.into(%{})

    %{
      games_played: parse_stat_value(stats_map["gamesPlayed"]),
      goals: parse_stat_value(stats_map["goals"]),
      assists: parse_stat_value(stats_map["assists"]),
      points: parse_stat_value(stats_map["points"]),
      plus_minus: parse_stat_value(stats_map["plusMinus"]),
      penalty_minutes: parse_stat_value(stats_map["penaltyMinutes"]),
      shots: parse_stat_value(stats_map["shots"]),
      power_play_goals: parse_stat_value(stats_map["powerPlayGoals"]),
      power_play_assists: parse_stat_value(stats_map["powerPlayAssists"]),
      game_winning_goals: parse_stat_value(stats_map["gameWinningGoals"])
    }
  end
  defp parse_stats_summary(_), do: nil

  defp get_team_logo(%{"logos" => [%{"href" => url} | _]}), do: url
  defp get_team_logo(%{"logo" => url}) when is_binary(url), do: url
  defp get_team_logo(_), do: nil

  defp get_headshot(%{"headshot" => %{"href" => url}}), do: url
  defp get_headshot(%{"headshot" => url}) when is_binary(url), do: url
  defp get_headshot(_), do: nil

  defp parse_birth_place(%{"city" => city, "state" => state, "country" => country}) do
    [city, state, country]
    |> Enum.filter(&(&1 && &1 != ""))
    |> Enum.join(", ")
  end
  defp parse_birth_place(%{"city" => city, "country" => country}) do
    [city, country]
    |> Enum.filter(&(&1 && &1 != ""))
    |> Enum.join(", ")
  end
  defp parse_birth_place(_), do: nil

  defp parse_search_results(%{"items" => items}) when is_list(items) do
    items
    |> Enum.filter(fn item -> item["type"] == "player" end)
    |> Enum.map(&parse_search_item/1)
  end
  defp parse_search_results(_), do: []

  defp parse_search_item(item) do
    %{
      id: to_string(item["id"]),
      name: item["displayName"] || item["name"],
      position: item["position"],
      team: %{
        name: item["team"] || item["teamName"],
        abbreviation: item["teamAbbreviation"]
      },
      headshot: extract_headshot(item["headshot"])
    }
  end

  defp extract_headshot(%{"href" => url}) when is_binary(url), do: url
  defp extract_headshot(url) when is_binary(url), do: url
  defp extract_headshot(_), do: nil

  # --- Career Stats Parsing ---

  # ESPN stats API returns data in categories[].statistics[] format
  # Each category has "names" (stat keys) and "statistics" (season data with "stats" array)
  defp parse_career_seasons(%{"categories" => categories}) when is_list(categories) do
    # Find regular season category (usually first one or named "Regular Season")
    category = List.first(categories)

    case category do
      %{"names" => names, "statistics" => statistics} when is_list(names) and is_list(statistics) ->
        statistics
        |> Enum.map(fn season_data -> parse_season_from_category(season_data, names) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.year, :desc)

      _ ->
        []
    end
  end
  defp parse_career_seasons(_), do: []

  defp parse_season_from_category(%{"season" => season, "stats" => stats} = data, names)
       when is_list(stats) and is_list(names) do
    # Build a map from stat names to values
    stats_map =
      names
      |> Enum.zip(stats)
      |> Enum.into(%{})

    season_display = get_in(season, ["displayName"]) || ""
    season_year = get_in(season, ["year"])

    # Get team name from teamSlug or teamId
    team_name = get_team_name_from_stats(data)

    %{
      season: season_display,
      year: season_year,
      team: team_name,
      league: "NHL",
      games_played: parse_stat_value(stats_map["games"]),
      goals: parse_stat_value(stats_map["goals"]),
      assists: parse_stat_value(stats_map["assists"]),
      points: parse_stat_value(stats_map["points"]),
      plus_minus: parse_stat_value(stats_map["plusMinus"]),
      penalty_minutes: parse_stat_value(stats_map["penaltyMinutes"]),
      power_play_goals: parse_stat_value(stats_map["powerPlayGoals"]),
      power_play_assists: parse_stat_value(stats_map["powerPlayAssists"]),
      shots: parse_stat_value(stats_map["shootoutGoals"]),
      shooting_pct: stats_map["shootingPct"],
      game_winning_goals: parse_stat_value(stats_map["gameWinningGoals"])
    }
  end
  defp parse_season_from_category(_, _), do: nil

  defp get_team_name_from_stats(%{"teamSlug" => slug}) when is_binary(slug) do
    slug
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  defp get_team_name_from_stats(%{"teamName" => name}) when is_binary(name), do: name
  defp get_team_name_from_stats(_), do: "NHL"

  defp parse_stat_value(value) when is_float(value), do: round(value)
  defp parse_stat_value(value) when is_integer(value), do: value
  defp parse_stat_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {i, _} -> i
      :error ->
        case Float.parse(value) do
          {f, _} -> round(f)
          :error -> nil
        end
    end
  end
  defp parse_stat_value(_), do: nil
end
