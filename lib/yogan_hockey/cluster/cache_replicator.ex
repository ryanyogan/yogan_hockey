defmodule YoganHockey.Cluster.CacheReplicator do
  @moduledoc """
  Replicates ETS cache data across cluster nodes via PubSub.

  On replica nodes, this GenServer subscribes to PubSub topics and updates
  the local ETS cache when data is broadcast from the primary.

  This ensures all nodes have cached data available for serving requests,
  even though the GenServers that fetch from APIs only run on the primary.
  """

  use GenServer

  require Logger

  alias YoganHockey.{Cache, NHL}

  @pubsub YoganHockey.PubSub

  # PubSub topics to subscribe to
  @topics [
    "nhl:live_scores",
    "nhl:teams",
    "nhl:standings",
    "nhl:injuries",
    "yogan:stats",
    "playoffs:updates",
    "live_games:predictions"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting CacheReplicator - subscribing to #{length(@topics)} PubSub topics")

    # Subscribe to all topics
    Enum.each(@topics, fn topic ->
      Phoenix.PubSub.subscribe(@pubsub, topic)
    end)

    # If we're a replica, request initial data from primary
    unless primary_region?() do
      # Give cluster time to form, then request data
      Process.send_after(self(), :request_initial_data, 5_000)
    end

    {:ok, %{}}
  end

  # --- PubSub Handlers ---

  # NHL Live Scores
  @impl true
  def handle_info({:live_scores_updated, games}, state) do
    Cache.put(:nhl_live_scores, :current, games)
    {:noreply, state}
  end

  # NHL Teams
  @impl true
  def handle_info({:teams_updated, teams}, state) do
    Cache.put(:nhl_teams, :all, teams)
    {:noreply, state}
  end

  # NHL Standings
  @impl true
  def handle_info({:standings_updated, standings}, state) do
    Cache.put(:nhl_standings, :current, standings)
    {:noreply, state}
  end

  # NHL Injuries
  @impl true
  def handle_info({:injuries_updated, injuries}, state) do
    Cache.put(:nhl_injuries, :all, injuries)
    {:noreply, state}
  end

  # Yogan Stats (DEL2)
  @impl true
  def handle_info({:yogan_stats_updated, stats}, state) do
    Cache.put(:yogan_stats, :current, stats)
    {:noreply, state}
  end

  @impl true
  def handle_info({:yogan_team_updated, team}, state) do
    Cache.put(:del2_team, :yogan, team)
    {:noreply, state}
  end

  # Playoffs
  @impl true
  def handle_info({:playoff_picture_updated, picture}, state) do
    Cache.put(:playoffs, :playoff_picture, picture)
    {:noreply, state}
  end

  @impl true
  def handle_info({:generation_started}, state) do
    # Just a status update, no cache action needed
    {:noreply, state}
  end

  @impl true
  def handle_info({:generation_failed, _reason}, state) do
    # Just a status update, no cache action needed
    {:noreply, state}
  end

  # Live Game Predictions
  @impl true
  def handle_info({:prediction_updated, game_id, prediction}, state) do
    Cache.put(:live_game_predictions, game_id, prediction)
    {:noreply, state}
  end

  # Request initial data from primary via RPC
  @impl true
  def handle_info(:request_initial_data, state) do
    Logger.info("CacheReplicator requesting initial data from primary...")

    case find_primary_node() do
      nil ->
        Logger.warning("No primary node found, will retry in 10s")
        Process.send_after(self(), :request_initial_data, 10_000)

      primary ->
        Logger.info("Found primary node: #{primary}, fetching data...")
        fetch_and_cache_from_primary(primary)
    end

    {:noreply, state}
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private Functions ---

  defp primary_region? do
    primary = System.get_env("PRIMARY_REGION", "dfw")
    System.get_env("FLY_REGION") == primary or System.get_env("FLY_REGION") == nil
  end

  defp find_primary_node do
    primary_region = System.get_env("PRIMARY_REGION", "dfw")

    Node.list()
    |> Enum.find(fn node ->
      try do
        :rpc.call(node, System, :get_env, ["FLY_REGION"], 5000) == primary_region
      catch
        _, _ -> false
      end
    end)
  end

  defp fetch_and_cache_from_primary(primary) do
    # Fetch teams
    case :rpc.call(primary, NHL, :list_teams, [], 10_000) do
      teams when is_list(teams) and teams != [] ->
        Cache.put(:nhl_teams, :all, teams)
        Logger.info("Cached #{length(teams)} teams from primary")

      _ ->
        Logger.warning("Failed to fetch teams from primary")
    end

    # Fetch standings
    case :rpc.call(primary, NHL, :list_standings, [], 10_000) do
      standings when is_list(standings) and standings != [] ->
        Cache.put(:nhl_standings, :current, standings)
        Logger.info("Cached #{length(standings)} standings from primary")

      _ ->
        Logger.warning("Failed to fetch standings from primary")
    end

    # Fetch live scores
    case :rpc.call(primary, NHL, :list_live_scores, [], 10_000) do
      games when is_list(games) ->
        Cache.put(:nhl_live_scores, :current, games)
        Logger.info("Cached #{length(games)} live scores from primary")

      _ ->
        Logger.warning("Failed to fetch live scores from primary")
    end

    # Fetch injuries
    case :rpc.call(primary, NHL, :list_injuries, [], 10_000) do
      injuries when is_list(injuries) ->
        Cache.put(:nhl_injuries, :all, injuries)
        Logger.info("Cached #{length(injuries)} injuries from primary")

      _ ->
        Logger.warning("Failed to fetch injuries from primary")
    end

    # Fetch playoff picture
    case :rpc.call(primary, YoganHockey.Playoffs, :get_playoff_picture, [], 10_000) do
      {:ok, picture} when not is_nil(picture) ->
        Cache.put(:playoffs, :playoff_picture, picture)
        Logger.info("Cached playoff picture from primary")

      _ ->
        Logger.warning("Failed to fetch playoff picture from primary")
    end

    # Fetch live game predictions (entire ETS table)
    case :rpc.call(primary, :ets, :tab2list, [:live_game_predictions], 10_000) do
      entries when is_list(entries) and entries != [] ->
        Enum.each(entries, fn {key, value} ->
          Cache.put(:live_game_predictions, key, value)
        end)
        Logger.info("Cached #{length(entries)} live game predictions from primary")

      [] ->
        Logger.info("No live game predictions to cache from primary")

      _ ->
        Logger.warning("Failed to fetch live game predictions from primary")
    end

    # Fetch team details (entire ETS table - contains team details, schedules, etc.)
    case :rpc.call(primary, :ets, :tab2list, [:nhl_team_stats], 10_000) do
      entries when is_list(entries) and entries != [] ->
        Enum.each(entries, fn {key, value} ->
          Cache.put(:nhl_team_stats, key, value)
        end)
        Logger.info("Cached #{length(entries)} team stats entries from primary")

      [] ->
        Logger.info("No team stats to cache from primary")

      _ ->
        Logger.warning("Failed to fetch team stats from primary")
    end

    Logger.info("CacheReplicator finished fetching initial data from primary")
  end
end
