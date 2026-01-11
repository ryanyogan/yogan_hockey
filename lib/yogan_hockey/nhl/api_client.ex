defmodule YoganHockey.NHL.APIClient do
  @moduledoc """
  Client for ESPN's NHL API.

  Uses the adapter pattern for HTTP requests, making it easy to test
  and swap implementations.
  """

  @base_url "http://site.api.espn.com/apis/site/v2/sports/hockey/nhl"
  @core_url "https://sports.core.api.espn.com/v2/sports/hockey/leagues/nhl"

  @doc """
  Returns the configured HTTP adapter module.
  Defaults to ReqAdapter, can be overridden for testing.
  """
  def http_adapter do
    Application.get_env(:yogan_hockey, :http_adapter, YoganHockey.HTTP.ReqAdapter)
  end

  @doc """
  Fetches the current scoreboard with live and recent games.
  """
  @spec get_scoreboard() :: {:ok, map()} | {:error, term()}
  def get_scoreboard do
    http_adapter().get_json("#{@base_url}/scoreboard")
  end

  @doc """
  Fetches the scoreboard for a specific date (YYYYMMDD format).
  """
  @spec get_scoreboard(String.t()) :: {:ok, map()} | {:error, term()}
  def get_scoreboard(date) do
    http_adapter().get_json("#{@base_url}/scoreboard?dates=#{date}")
  end

  @doc """
  Fetches all NHL teams.
  """
  @spec get_teams() :: {:ok, map()} | {:error, term()}
  def get_teams do
    http_adapter().get_json("#{@base_url}/teams")
  end

  @doc """
  Fetches details for a specific team including roster and stats.
  """
  @spec get_team(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_team(team_id) do
    http_adapter().get_json("#{@base_url}/teams/#{team_id}?enable=roster,stats,schedule")
  end

  @doc """
  Fetches NHL standings.
  """
  @spec get_standings() :: {:ok, map()} | {:error, term()}
  def get_standings do
    # Use the v2 API which returns full standings data
    http_adapter().get_json("https://site.api.espn.com/apis/v2/sports/hockey/nhl/standings")
  end

  @doc """
  Fetches NHL news.
  """
  @spec get_news() :: {:ok, map()} | {:error, term()}
  def get_news do
    http_adapter().get_json("#{@base_url}/news")
  end

  @doc """
  Fetches schedule for a specific team.
  """
  @spec get_team_schedule(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_team_schedule(team_id) do
    http_adapter().get_json("#{@base_url}/teams/#{team_id}/schedule")
  end

  @doc """
  Fetches the current season information.
  """
  @spec get_season() :: {:ok, map()} | {:error, term()}
  def get_season do
    http_adapter().get_json("#{@core_url}/seasons?limit=1")
  end

  @doc """
  Fetches details for a specific player.
  """
  @spec get_player(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_player(player_id) do
    http_adapter().get_json("https://site.api.espn.com/apis/common/v3/sports/hockey/nhl/athletes/#{player_id}")
  end

  @doc """
  Fetches career statistics for a specific player (season-by-season).
  """
  @spec get_player_stats(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_player_stats(player_id) do
    http_adapter().get_json("https://site.web.api.espn.com/apis/common/v3/sports/hockey/nhl/athletes/#{player_id}/stats")
  end

  @doc """
  Searches for players by name.
  """
  @spec search_players(String.t()) :: {:ok, map()} | {:error, term()}
  def search_players(query) do
    encoded_query = URI.encode(query)
    http_adapter().get_json("https://site.api.espn.com/apis/common/v3/search?query=#{encoded_query}&type=player&sport=hockey&league=nhl&limit=10")
  end
end
