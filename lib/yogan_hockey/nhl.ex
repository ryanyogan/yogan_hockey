defmodule YoganHockey.NHL do
  @moduledoc """
  The NHL context.

  Provides the public API for NHL-related data including games, teams,
  standings, and live scores. Data is fetched from ESPN's API and
  cached in ETS for fast access.
  """

  alias YoganHockey.Cache
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
  """
  @spec get_team_details(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_team_details(team_id) do
    cache_key = {:team_details, to_string(team_id)}

    case Cache.get(:nhl_team_stats, cache_key) do
      nil ->
        fetch_and_cache_team_details(team_id, cache_key)

      cached ->
        {:ok, cached}
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
        Cache.put(:nhl_team_stats, cache_key, team)
        {:ok, team}

      {:error, reason} ->
        {:error, reason}
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
        case APIClient.get_team_schedule(team_id) do
          {:ok, data} ->
            schedule = Parsers.parse_team_schedule(data)
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
  """
  @spec search_players(String.t()) :: {:ok, [map()]} | {:error, term()}
  def search_players(query) when is_binary(query) and byte_size(query) >= 2 do
    case APIClient.search_players(query) do
      {:ok, data} ->
        players = Parsers.parse_search_results(data)
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
        standings = Parsers.parse_standings(data)
        Cache.put(:nhl_standings, :current, standings)
        Cache.put(:nhl_standings, :last_updated, DateTime.utc_now())
        {:ok, standings}

      {:error, reason} ->
        {:error, reason}
    end
  end

end
