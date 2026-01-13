defmodule YoganHockey.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Run migrations on application start (only on primary region with SQLite)
    if primary_region?() do
      YoganHockey.Release.migrate()
    end

    # Initialize ETS tables before starting children
    YoganHockey.Cache.init()

    children =
      [
        YoganHockeyWeb.Telemetry,
        {Phoenix.PubSub, name: YoganHockey.PubSub},

        # Task supervisor for background tasks
        {Task.Supervisor, name: YoganHockey.TaskSupervisor},

        # Registry for per-game servers
        {Registry, keys: :unique, name: YoganHockey.GamePlayRegistry},

        # Dynamic supervisor for game play servers
        YoganHockey.GamePlay.GamePlaySupervisor,

        # Cache replicator - runs on ALL nodes to sync ETS via PubSub
        YoganHockey.Cluster.CacheReplicator
      ] ++
        cluster_children() ++
        repo_children() ++
        genserver_children() ++
        [
          # Start to serve requests, typically the last entry
          YoganHockeyWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YoganHockey.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Only start Repo on primary region (which has the SQLite volume)
  # Replica regions use RPC for database writes
  defp repo_children do
    if primary_region?() do
      [YoganHockey.Repo]
    else
      []
    end
  end

  # Libcluster for Fly.io distributed clustering
  # Uses DNSPoll strategy to discover nodes via Fly's internal DNS
  defp cluster_children do
    topologies = Application.get_env(:libcluster, :topologies, [])

    if topologies != [] do
      [{Cluster.Supervisor, [topologies, [name: YoganHockey.ClusterSupervisor]]}]
    else
      []
    end
  end

  # GenServers that poll external APIs - only start on primary region
  # to prevent duplicate API calls and ensure single-writer for SQLite.
  # Replica regions receive updates via Phoenix.PubSub broadcasts.
  defp genserver_children do
    if Application.get_env(:yogan_hockey, :start_genservers, true) and primary_region?() do
      [
        YoganHockey.NHL.LiveScoresServer,
        YoganHockey.NHL.TeamsServer,
        YoganHockey.NHL.InjuriesServer,
        YoganHockey.DEL2.YoganStatsServer,
        YoganHockey.Playoffs.PredictionServer,
        YoganHockey.LiveGames.PredictionServer,
        YoganHockey.Games.GamePersistenceServer
      ]
    else
      []
    end
  end

  # Returns true if this node is in the primary region (has SQLite volume)
  # Local dev always returns true
  defp primary_region? do
    primary = System.get_env("PRIMARY_REGION", "dfw")
    System.get_env("FLY_REGION") == primary or System.get_env("FLY_REGION") == nil
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YoganHockeyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
