defmodule YoganHockey.NHL do
  @moduledoc """
  The NHL context.

  Provides the public API for NHL-related data including games, teams,
  standings, and live scores. Data is fetched from ESPN's API and
  cached in ETS for fast access.
  """

  require Logger

  alias YoganHockey.Cache
  alias YoganHockey.EasterEggs
  alias YoganHockey.NHL.APIClient
  alias YoganHockey.NHL.Parsers

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
  Gets a specific game by ID from the live scores cache.
  """
  @spec get_game(String.t()) :: map() | nil
  def get_game(game_id) do
    game_id = to_string(game_id)

    list_live_scores()
    |> Enum.find(&(to_string(&1.id) == game_id))
  end

  @doc """
  Fetches and caches the latest scoreboard data.
  Returns the list of games.
  """
  @spec refresh_live_scores() :: {:ok, [map()]} | {:error, term()}
  def refresh_live_scores do
    case APIClient.get_scoreboard() do
      {:ok, data} ->
        games = Parsers.parse_scoreboard(data)
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
  Returns cached data if available for fast access.
  Always injects easter egg players into the roster.
  """
  @spec get_team_details(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_team_details(team_id) do
    cache_key = {:team_details, to_string(team_id)}

    result = case Cache.get(:nhl_team_stats, cache_key) do
      nil ->
        Logger.debug("[NHL] Cache MISS for team_details #{team_id} - fetching from API")
        fetch_and_cache_team_details(team_id, cache_key)

      cached ->
        Logger.debug("[NHL] Cache HIT for team_details #{team_id}")
        {:ok, cached}
    end

    # Always inject easter egg players (in case cache was populated without them)
    case result do
      {:ok, team} -> {:ok, inject_easter_egg_players(team, team_id)}
      error -> error
    end
  end

  @doc """
  Forces a fresh fetch of team details, bypassing cache.
  Updates the cache with new data.
  """
  @spec refresh_team_details(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def refresh_team_details(team_id) do
    cache_key = {:team_details, to_string(team_id)}
    fetch_and_cache_team_details(team_id, cache_key)
  end

  defp fetch_and_cache_team_details(team_id, cache_key) do
    case APIClient.get_team(team_id) do
      {:ok, data} ->
        team = Parsers.parse_team_details(data)
        # Add easter egg players to roster
        team = inject_easter_egg_players(team, team_id)
        Cache.put(:nhl_team_stats, cache_key, team)
        {:ok, team}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inject_easter_egg_players(team, team_id) do
    easter_egg_players = EasterEggs.players_for_team(to_string(team_id))

    if easter_egg_players == [] do
      team
    else
      existing_roster = Map.get(team, :roster, [])
      easter_egg_ids = Enum.map(easter_egg_players, & &1.id)

      # Remove any existing easter egg players to avoid duplicates
      filtered_roster = Enum.reject(existing_roster, fn player ->
        player.id in easter_egg_ids
      end)

      # Add easter egg players at the top of the roster
      updated_roster = easter_egg_players ++ filtered_roster
      Map.put(team, :roster, updated_roster)
    end
  end

  @doc """
  Fetches and caches all NHL teams.
  """
  @spec refresh_teams() :: {:ok, [map()]} | {:error, term()}
  def refresh_teams do
    case APIClient.get_teams() do
      {:ok, data} ->
        teams = Parsers.parse_teams(data)
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
        Logger.debug("[NHL] Cache MISS for team_schedule #{team_id} - fetching from API")
        case APIClient.get_team_schedule(team_id) do
          {:ok, data} ->
            schedule = Parsers.parse_team_schedule(data)
            Cache.put(:nhl_team_stats, cache_key, schedule)
            {:ok, schedule}

          {:error, reason} ->
            {:error, reason}
        end

      cached ->
        Logger.debug("[NHL] Cache HIT for team_schedule #{team_id}")
        {:ok, cached}
    end
  end

  @doc """
  Force refreshes a team's schedule from the API, bypassing cache.
  """
  @spec refresh_team_schedule(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def refresh_team_schedule(team_id) do
    cache_key = {:team_schedule, to_string(team_id)}

    case APIClient.get_team_schedule(team_id) do
      {:ok, data} ->
        schedule = Parsers.parse_team_schedule(data)
        Cache.put(:nhl_team_stats, cache_key, schedule)
        {:ok, schedule}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Players ---

  @doc """
  Gets a player by ID, using cache if available.
  Returns {:ok, player} or {:error, reason}.
  Also checks for easter egg players first.
  """
  @spec get_player(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_player(player_id) do
    player_id = to_string(player_id)

    # Check for easter egg players first
    case EasterEggs.get_player(player_id) do
      {:ok, player} ->
        {:ok, player}

      nil ->
        cache_key = {:player, player_id}
        cached = Cache.get(:player_cache, cache_key)

        # Only use cache if it's a full player record (has career_seasons)
        if cached && is_full_player_record?(cached) do
          {:ok, cached}
        else
          fetch_and_cache_player(player_id, cache_key)
        end
    end
  end

  defp is_full_player_record?(player) do
    # Full player records have career_seasons from the stats API
    Map.has_key?(player, :career_seasons) && Map.has_key?(player, :birth_date)
  end

  defp fetch_and_cache_player(player_id, cache_key) do
    with {:ok, data} <- APIClient.get_player(player_id),
         {:ok, stats_data} <- APIClient.get_player_stats(player_id) do
      player = Parsers.parse_player(data)
      career_seasons = Parsers.parse_career_seasons(stats_data)
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
  Also includes matching easter egg players.
  """
  @spec search_players(String.t()) :: {:ok, [map()]} | {:error, term()}
  def search_players(query) when is_binary(query) and byte_size(query) >= 2 do
    # Get easter egg players that match
    easter_egg_players =
      EasterEggs.search_players(query)
      |> Enum.map(&easter_egg_to_search_result/1)

    case APIClient.search_players(query) do
      {:ok, data} ->
        api_players = Parsers.parse_search_results(data)
        # Easter egg players appear first
        {:ok, easter_egg_players ++ api_players}

      {:error, _reason} ->
        # Even if API fails, return easter egg matches
        {:ok, easter_egg_players}
    end
  end

  def search_players(_query), do: {:ok, []}

  defp easter_egg_to_search_result(player) do
    %{
      id: player.id,
      name: player.name,
      position: player.position,
      team: player.team.display_name,
      headshot: player.headshot
    }
  end

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
        standings = Parsers.parse_standings(data)
        Cache.put(:nhl_standings, :current, standings)
        Cache.put(:nhl_standings, :last_updated, DateTime.utc_now())
        {:ok, standings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Injuries ---

  @doc """
  Returns all NHL injuries from cache.
  """
  @spec list_injuries() :: [map()]
  def list_injuries do
    case Cache.get(:nhl_injuries, :all) do
      nil -> []
      injuries -> injuries
    end
  end

  @doc """
  Returns injuries grouped by team (sorted alphabetically by team name).
  """
  @spec list_injuries_by_team() :: [%{team_id: String.t(), team_name: String.t(), team_abbreviation: String.t(), team_logo: String.t() | nil, injuries: [map()]}]
  def list_injuries_by_team do
    list_injuries()
    |> Enum.group_by(& &1.team_id)
    |> Enum.map(fn {_team_id, injuries} ->
      first = List.first(injuries)
      %{
        team_id: first.team_id,
        team_name: first.team_name,
        team_abbreviation: first.team_abbreviation,
        team_logo: first.team_logo,
        injuries: injuries
      }
    end)
    |> Enum.sort_by(& &1.team_name)
  end

  @doc """
  Returns injuries for a specific team by team ID.
  """
  @spec get_injuries_for_team(String.t() | integer()) :: [map()]
  def get_injuries_for_team(team_id) do
    team_id = to_string(team_id)

    list_injuries()
    |> Enum.filter(&(&1.team_id == team_id))
  end

  @doc """
  Returns injury count for a specific team by team ID.
  """
  @spec injury_count_for_team(String.t() | integer()) :: non_neg_integer()
  def injury_count_for_team(team_id) do
    get_injuries_for_team(team_id) |> length()
  end

  @doc """
  Returns injury info for a specific player by player ID.
  Returns nil if player is not injured.
  """
  @spec get_player_injury(String.t() | integer()) :: map() | nil
  def get_player_injury(player_id) do
    player_id = to_string(player_id)

    list_injuries()
    |> Enum.find(&(&1.player_id == player_id))
  end

  @doc """
  Fetches and caches NHL injuries.
  """
  @spec refresh_injuries() :: {:ok, [map()]} | {:error, term()}
  def refresh_injuries do
    case APIClient.get_injuries() do
      {:ok, data} ->
        injuries = Parsers.parse_injuries(data)
        Cache.put(:nhl_injuries, :all, injuries)
        Cache.put(:nhl_injuries, :last_updated, DateTime.utc_now())
        {:ok, injuries}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns when injuries were last updated.
  """
  @spec injuries_updated_at() :: DateTime.t() | nil
  def injuries_updated_at do
    Cache.get(:nhl_injuries, :last_updated)
  end

end
