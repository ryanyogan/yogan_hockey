defmodule YoganHockey.NHL.Parsers do
  @moduledoc """
  Parser functions for ESPN NHL API responses.

  This module handles all the data transformation from ESPN's JSON format
  to our internal data structures. All functions are pure and have no side effects.
  """

  # --- Scoreboard Parsing ---

  @doc """
  Parses the scoreboard response into a list of game maps.
  """
  @spec parse_scoreboard(map()) :: [map()]
  def parse_scoreboard(%{"events" => events}) when is_list(events) do
    Enum.map(events, &parse_game/1)
  end

  def parse_scoreboard(_), do: []

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
      broadcasts: parse_broadcasts(competition["broadcasts"] || competition["geoBroadcasts"])
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
      # Handle both "names" (scoreboard) and "market"/"media" (schedule) formats
      cond do
        is_list(b["names"]) -> b["names"]
        is_map(b["media"]) -> [b["media"]["shortName"] || b["media"]["name"]]
        is_binary(b["name"]) -> [b["name"]]
        true -> []
      end
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&String.contains?(&1, "FanDuel SN"))
    |> Enum.uniq()
  end

  # --- Teams Parsing ---

  @doc """
  Parses the teams list response.
  """
  @spec parse_teams(map()) :: [map()]
  def parse_teams(%{"sports" => [%{"leagues" => [%{"teams" => teams}]}]}) do
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

  def parse_teams(_), do: []

  defp parse_team_links(nil), do: %{}

  defp parse_team_links(links) when is_list(links) do
    Enum.reduce(links, %{}, fn link, acc ->
      Map.put(acc, link["rel"] |> List.first(), link["href"])
    end)
  end

  @doc """
  Parses detailed team info including roster.
  """
  @spec parse_team_details(map()) :: map()
  def parse_team_details(%{"team" => team}) do
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

  def parse_team_details(data), do: data

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

  # --- Standings Parsing ---

  @doc """
  Parses NHL standings from the API response.
  Handles both old format (with divisions) and new format (conference-level standings).
  """
  @spec parse_standings(map()) :: [map()]
  def parse_standings(%{"children" => conferences}) when is_list(conferences) do
    Enum.flat_map(conferences, fn conference ->
      conf_name = conference["name"] || ""

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
              division: conf_name,
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
  def parse_standings(%{"standings" => standings_data}) do
    parse_standings(standings_data)
  end

  def parse_standings(_), do: []

  defp get_logo_href([first | _]) when is_map(first), do: first["href"]
  defp get_logo_href(_), do: nil

  defp parse_standing_stats(nil), do: %{}

  defp parse_standing_stats(stats) when is_list(stats) do
    Enum.reduce(stats, %{}, fn stat, acc ->
      Map.put(acc, stat["name"], stat["value"])
    end)
  end

  # --- Schedule Parsing ---

  @doc """
  Parses a team's schedule into past and upcoming games.
  """
  @spec parse_team_schedule(map()) :: map()
  def parse_team_schedule(%{"events" => events, "team" => team}) when is_list(events) do
    team_id = to_string(team["id"])

    games = Enum.map(events, fn event -> parse_schedule_game(event, team_id) end)

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

  def parse_team_schedule(_), do: %{past_games: [], upcoming_games: [], record: nil, standing: nil}

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
      broadcasts: parse_broadcasts(competition["broadcasts"] || competition["geoBroadcasts"]),
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
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} ->
        dt

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

  @doc """
  Parses a player response from the ESPN API.
  """
  @spec parse_player(map()) :: map() | nil
  def parse_player(%{"athlete" => athlete}) do
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

  def parse_player(_), do: nil

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

  # --- Search Results Parsing ---

  @doc """
  Parses player search results.
  """
  @spec parse_search_results(map()) :: [map()]
  def parse_search_results(%{"items" => items}) when is_list(items) do
    items
    |> Enum.filter(fn item -> item["type"] == "player" end)
    |> Enum.map(&parse_search_item/1)
  end

  def parse_search_results(_), do: []

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

  @doc """
  Parses career season statistics from the ESPN stats API.

  ESPN stats API returns data in categories[].statistics[] format.
  Each category has "names" (stat keys) and "statistics" (season data with "stats" array).
  """
  @spec parse_career_seasons(map()) :: [map()]
  def parse_career_seasons(%{"categories" => categories}) when is_list(categories) do
    # Find regular season category (usually first one or named "Regular Season")
    category = List.first(categories)

    case category do
      %{"names" => names, "statistics" => statistics}
      when is_list(names) and is_list(statistics) ->
        statistics
        |> Enum.map(fn season_data -> parse_season_from_category(season_data, names) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.year, :desc)

      _ ->
        []
    end
  end

  def parse_career_seasons(_), do: []

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

  # --- Injuries Parsing ---

  @doc """
  Parses NHL injuries from the API response.
  Groups injuries by team, sorted alphabetically.
  """
  @spec parse_injuries(map()) :: [map()]
  def parse_injuries(%{"injuries" => injuries}) when is_list(injuries) do
    injuries
    |> Enum.flat_map(fn team_data ->
      # Team info is directly on team_data, not nested under "team"
      team_id = to_string(team_data["id"] || "")
      team_name = team_data["displayName"] || team_data["name"] || ""
      team_abbreviation = team_data["abbreviation"] || ""
      team_logo = get_logo_href(team_data["logos"])

      injured_players = team_data["injuries"] || []

      Enum.map(injured_players, fn injury ->
        athlete = injury["athlete"] || %{}

        %{
          player_id: extract_player_id(athlete),
          player_name: athlete["displayName"] || athlete["fullName"] || "",
          player_headshot: get_headshot(athlete),
          position: get_in(athlete, ["position", "abbreviation"]) || "",
          team_id: team_id,
          team_name: team_name,
          team_abbreviation: team_abbreviation,
          team_logo: team_logo,
          status: injury["status"] || "",
          return_date: format_injury_date(injury["date"]),
          description: injury["longComment"] || injury["shortComment"] || "",
          type: get_in(injury, ["type", "description"]) || get_in(injury, ["type", "name"]) || ""
        }
      end)
    end)
    |> Enum.sort_by(& &1.team_name)
  end

  def parse_injuries(_), do: []

  # Extract player ID from athlete links or directly
  defp extract_player_id(%{"id" => id}) when not is_nil(id), do: to_string(id)
  defp extract_player_id(%{"links" => [%{"href" => href} | _]}) do
    # Extract ID from URL like "https://www.espn.com/nhl/player/_/id/3942905"
    case Regex.run(~r/\/id\/(\d+)/, href) do
      [_, id] -> id
      _ -> ""
    end
  end
  defp extract_player_id(_), do: ""

  # Format injury date to a readable format
  defp format_injury_date(nil), do: nil
  defp format_injury_date(date_string) when is_binary(date_string) do
    # Try full ISO8601 first
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%b %d, %Y")

      _ ->
        # Handle format without seconds (e.g., "2026-01-08T19:31Z")
        normalized = Regex.replace(~r/T(\d{2}:\d{2})Z$/, date_string, "T\\1:00Z")

        case DateTime.from_iso8601(normalized) do
          {:ok, dt, _} ->
            Calendar.strftime(dt, "%b %d, %Y")

          _ ->
            # Try just date parsing as fallback
            case Date.from_iso8601(String.slice(date_string, 0, 10)) do
              {:ok, date} -> Calendar.strftime(date, "%b %d, %Y")
              _ -> date_string
            end
        end
    end
  end
  defp format_injury_date(date), do: date

  # --- Game Summary Parsing (Live Game Play) ---

  @doc """
  Parses ESPN game summary response into GamePlayData structure.
  Returns comprehensive game data including boxscore and play-by-play.
  """
  @spec parse_game_summary(map()) :: map()
  def parse_game_summary(%{"boxscore" => boxscore} = data) do
    header = data["header"] || %{}
    competitions = header["competitions"] || []
    competition = List.first(competitions) || %{}
    plays = data["plays"] || []

    # Parse teams from boxscore (stats)
    teams = boxscore["teams"] || []
    {home_team, away_team} = parse_boxscore_teams(teams)

    # Get scores from competitors (boxscore teams don't have scores)
    competitors = competition["competitors"] || []
    scores = extract_competitor_scores(competitors)

    # Merge scores into team data
    home_team = Map.put(home_team, :score, scores[:home] || 0)
    away_team = Map.put(away_team, :score, scores[:away] || 0)

    %{
      game_id: header["id"] || data["id"],
      status: parse_game_summary_status(competition["status"]),
      home_team: home_team,
      away_team: away_team,
      plays: parse_game_plays(plays, home_team, away_team),
      boxscore: parse_period_scores(competition),
      last_updated: DateTime.utc_now()
    }
  end

  def parse_game_summary(_), do: nil

  defp parse_game_summary_status(%{"type" => type} = status) do
    %{
      state: type["state"] || "pre",
      period: status["period"] || 0,
      clock: status["displayClock"] || "0:00",
      intermission: type["name"] == "STATUS_INTERMISSION",
      detail: type["shortDetail"] || type["detail"]
    }
  end

  defp parse_game_summary_status(_) do
    %{state: "pre", period: 0, clock: "0:00", intermission: false, detail: nil}
  end

  defp parse_boxscore_teams(teams) when is_list(teams) do
    home = Enum.find(teams, fn t -> t["homeAway"] == "home" end) || %{}
    away = Enum.find(teams, fn t -> t["homeAway"] == "away" end) || %{}

    {parse_boxscore_team(home), parse_boxscore_team(away)}
  end

  defp parse_boxscore_teams(_), do: {%{}, %{}}

  # Extract scores from header competitors (boxscore teams don't include scores)
  defp extract_competitor_scores(competitors) when is_list(competitors) do
    Enum.reduce(competitors, %{}, fn comp, acc ->
      home_away = comp["homeAway"]
      score = parse_competitor_score(comp["score"])

      case home_away do
        "home" -> Map.put(acc, :home, score)
        "away" -> Map.put(acc, :away, score)
        _ -> acc
      end
    end)
  end

  defp extract_competitor_scores(_), do: %{}

  defp parse_competitor_score(score) when is_integer(score), do: score
  defp parse_competitor_score(score) when is_binary(score) do
    case Integer.parse(score) do
      {i, _} -> i
      :error -> 0
    end
  end
  defp parse_competitor_score(_), do: 0

  defp parse_boxscore_team(team) do
    team_info = team["team"] || %{}
    stats = team["statistics"] || []

    %{
      id: to_string(team_info["id"] || ""),
      name: team_info["displayName"] || team_info["name"] || "",
      abbreviation: team_info["abbreviation"] || "",
      logo: team_info["logo"] || get_logo_href(team_info["logos"]),
      color: team_info["color"] || "333333",
      score: parse_boxscore_score(team["score"]) || 0,
      shots: get_team_stat(stats, "shotsTotal") || get_team_stat(stats, "shots") || 0,
      blocked: get_team_stat(stats, "blockedShots") || get_team_stat(stats, "blocked") || 0,
      hits: get_team_stat(stats, "hits") || 0,
      faceoff_pct: get_team_stat(stats, "faceOffWinPercentage"),
      takeaways: get_team_stat(stats, "takeaways") || 0,
      giveaways: get_team_stat(stats, "giveaways") || 0,
      penalty_minutes: get_team_stat(stats, "penaltyMinutes") || get_team_stat(stats, "pim") || 0,
      powerplay_goals: get_team_stat(stats, "powerPlayGoals"),
      powerplay_opportunities: get_team_stat(stats, "powerPlayOpportunities"),
      power_play: get_power_play_stat(stats)
    }
  end

  # Parse score from various formats ESPN uses
  defp parse_boxscore_score(nil), do: nil
  defp parse_boxscore_score(s) when is_integer(s), do: s
  defp parse_boxscore_score(s) when is_float(s), do: trunc(s)
  defp parse_boxscore_score(%{"value" => v}) when is_number(v), do: trunc(v)
  defp parse_boxscore_score(%{"displayValue" => v}) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end
  defp parse_boxscore_score(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, _} -> i
      :error -> nil
    end
  end
  defp parse_boxscore_score(_), do: nil

  defp get_team_stat(stats, name) when is_list(stats) do
    case Enum.find(stats, fn s -> s["name"] == name end) do
      %{"displayValue" => v} when is_binary(v) ->
        case Float.parse(v) do
          {f, _} -> f
          :error -> nil
        end
      %{"value" => v} when is_number(v) -> v
      _ -> nil
    end
  end

  defp get_team_stat(_, _), do: nil

  defp get_power_play_stat(stats) when is_list(stats) do
    case Enum.find(stats, fn s -> s["name"] == "powerPlayPct" end) do
      %{"displayValue" => v} -> v
      _ -> nil
    end
  end

  defp get_power_play_stat(_), do: nil

  defp parse_period_scores(competition) do
    linescores = competition["linescores"] || []

    period_scores =
      linescores
      |> Enum.with_index(1)
      |> Enum.map(fn {scores, period} ->
        %{
          period: period,
          home: scores["home"] || 0,
          away: scores["away"] || 0
        }
      end)

    %{period_scores: period_scores}
  end

  defp parse_game_plays(plays, home_team, away_team) when is_list(plays) do
    plays
    |> Enum.filter(&significant_play?/1)
    |> Enum.map(fn play -> parse_single_play(play, home_team, away_team) end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_game_plays(_, _, _), do: []

  @doc """
  Parses plays from the core API plays endpoint response.
  This endpoint returns all plays with coordinates, not limited to 100.
  """
  def parse_core_api_plays(%{"items" => items}, home_team, away_team) when is_list(items) do
    items
    |> Enum.filter(&significant_play_core?/1)
    |> Enum.map(fn play -> parse_single_play(play, home_team, away_team) end)
    |> Enum.reject(&is_nil/1)
  end

  def parse_core_api_plays(_, _, _), do: []

  # Filter for significant plays from summary API
  defp significant_play?(%{"type" => %{"id" => type_id}}) do
    # 505 = Goal, 506 = Shot on Goal, 509 = Penalty, 503 = Hit, 502 = Faceoff
    type_id in ["505", "506", "509", "503", "502"]
  end

  defp significant_play?(_), do: false

  # Filter for significant plays from core API (uses abbreviation)
  defp significant_play_core?(%{"type" => %{"abbreviation" => abbr}}) do
    abbr in ["goal", "shot-on-goal", "penalty", "hit", "faceoff"]
  end

  defp significant_play_core?(_), do: false

  defp parse_single_play(play, home_team, away_team) do
    type = play["type"] || %{}
    period = play["period"] || %{}
    clock = play["clock"] || %{}
    coordinate = play["coordinate"] || %{}
    team = play["team"] || %{}

    # Extract team_id from either direct "id" field or "$ref" URL
    team_id = extract_team_id(team)

    # Determine team color based on which team made the play
    team_color =
      cond do
        team_id == home_team.id -> home_team.color
        team_id == away_team.id -> away_team.color
        true -> "666666"
      end

    %{
      id: play["id"] || to_string(:erlang.unique_integer([:positive])),
      type: play_type_from_id(type["id"]) || play_type_from_abbr(type["abbreviation"]),
      period: period["number"] || 1,
      time: clock["displayValue"] || "0:00",
      team_id: team_id,
      team_color: team_color,
      description: play["text"] || type["text"] || "",
      x: normalize_coordinate(coordinate["x"], 100),
      y: normalize_coordinate(coordinate["y"], 42.5),
      scoring: play["scoringPlay"] == true
    }
  end

  # Extract team ID from team object - handles both formats
  defp extract_team_id(%{"id" => id}), do: to_string(id)
  defp extract_team_id(%{"$ref" => ref}) when is_binary(ref) do
    # Extract team ID from URL like ".../teams/13?..."
    case Regex.run(~r"/teams/(\d+)", ref) do
      [_, id] -> id
      _ -> ""
    end
  end
  defp extract_team_id(_), do: ""

  defp play_type_from_id("505"), do: :goal
  defp play_type_from_id("506"), do: :shot
  defp play_type_from_id("509"), do: :penalty
  defp play_type_from_id("503"), do: :hit
  defp play_type_from_id("502"), do: :faceoff
  defp play_type_from_id(_), do: nil

  defp play_type_from_abbr("goal"), do: :goal
  defp play_type_from_abbr("shot-on-goal"), do: :shot
  defp play_type_from_abbr("penalty"), do: :penalty
  defp play_type_from_abbr("hit"), do: :hit
  defp play_type_from_abbr("faceoff"), do: :faceoff
  defp play_type_from_abbr(_), do: :other

  # Normalize coordinates to 0-200 x 0-85 NHL rink system
  # ESPN coordinates are relative to center ice
  defp normalize_coordinate(nil, default), do: default
  defp normalize_coordinate(coord, offset) when is_number(coord), do: offset + coord
  defp normalize_coordinate(_, default), do: default

  # --- Shared Helpers ---

  defp parse_stat_value(value) when is_float(value), do: round(value)
  defp parse_stat_value(value) when is_integer(value), do: value

  defp parse_stat_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {i, _} ->
        i

      :error ->
        case Float.parse(value) do
          {f, _} -> round(f)
          :error -> nil
        end
    end
  end

  defp parse_stat_value(_), do: nil
end
