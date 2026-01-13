# Ensure required services are started for tests
# (These may already be started by the application)

# Initialize ETS cache tables if not already done
unless :ets.whereis(:nhl_live_scores) != :undefined do
  YoganHockey.Cache.init()
end

# Start PubSub if not already running
unless Process.whereis(YoganHockey.PubSub) do
  {:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: YoganHockey.PubSub)
end

# Start Task.Supervisor if not already running
unless Process.whereis(YoganHockey.TaskSupervisor) do
  {:ok, _} = Task.Supervisor.start_link(name: YoganHockey.TaskSupervisor)
end

ExUnit.start()
