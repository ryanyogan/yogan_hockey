defmodule YoganHockey.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize ETS tables before starting children
    YoganHockey.Cache.init()

    children =
      [
        YoganHockeyWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:yogan_hockey, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: YoganHockey.PubSub},

        # Task supervisor for background tasks
        {Task.Supervisor, name: YoganHockey.TaskSupervisor}
      ] ++
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

  # Conditionally start GenServers (can be disabled in tests)
  defp genserver_children do
    if Application.get_env(:yogan_hockey, :start_genservers, true) do
      [
        YoganHockey.NHL.LiveScoresServer,
        YoganHockey.NHL.TeamsServer,
        YoganHockey.DEL2.YoganStatsServer,
        YoganHockey.Playoffs.PredictionServer,
        YoganHockey.LiveGames.PredictionServer
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YoganHockeyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
