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
      b["names"] || []
    end)
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
