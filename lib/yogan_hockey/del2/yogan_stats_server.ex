defmodule YoganHockey.DEL2.YoganStatsServer do
  @moduledoc """
  GenServer that polls Andrew Yogan's stats from Elite Prospects/HockeyDB every 24 hours.

  Stats don't change frequently during the season, so a long polling interval is appropriate.
  Uses exponential backoff on failures (up to 30 minutes) before retrying.
  """

  use GenServer

  require Logger

  alias YoganHockey.DEL2

  # Poll once per day - stats don't change frequently
  @poll_interval :timer.hours(24)

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Forces an immediate refresh of Yogan stats.
  """
  def refresh_now do
    GenServer.cast(__MODULE__, :refresh)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting YoganStatsServer with #{div(@poll_interval, 3_600_000)}h interval")

    # Initial fetch
    send(self(), :poll)

    {:ok, %{last_poll: nil, consecutive_failures: 0}}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = do_poll(state)

    # Schedule next poll (use exponential backoff on failures)
    interval =
      if new_state.consecutive_failures > 0 do
        min(@poll_interval * new_state.consecutive_failures, :timer.minutes(30))
      else
        @poll_interval
      end

    Process.send_after(self(), :poll, interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    new_state = do_poll(state)
    {:noreply, new_state}
  end

  # --- Private ---

  defp do_poll(state) do
    # Run both fetches in parallel for ~50% speedup
    stats_task =
      Task.Supervisor.async_nolink(YoganHockey.TaskSupervisor, fn ->
        DEL2.refresh_yogan_stats()
      end)

    schedule_task =
      Task.Supervisor.async_nolink(YoganHockey.TaskSupervisor, fn ->
        DEL2.refresh_team_schedule()
      end)

    # Wait for both to complete
    stats_result = Task.await(stats_task, 30_000)
    schedule_result = Task.await(schedule_task, 30_000)

    # Process stats result
    new_state =
      case stats_result do
        {:ok, stats} ->
          Logger.debug("Fetched Yogan stats: #{stats.player.name}")

          Phoenix.PubSub.broadcast(
            YoganHockey.PubSub,
            "yogan:stats",
            {:yogan_stats_updated, stats}
          )

          %{state | last_poll: DateTime.utc_now(), consecutive_failures: 0}

        {:error, reason} ->
          Logger.warning("Failed to fetch Yogan stats: #{inspect(reason)}")
          %{state | consecutive_failures: state.consecutive_failures + 1}
      end

    # Process schedule result (independent of stats success)
    case schedule_result do
      {:ok, schedule} ->
        Logger.debug(
          "Fetched team schedule: #{length(schedule.past_games)} past, #{length(schedule.upcoming_games)} upcoming"
        )

        Phoenix.PubSub.broadcast(
          YoganHockey.PubSub,
          "yogan:stats",
          {:team_schedule_updated, schedule}
        )

      {:error, reason} ->
        Logger.warning("Failed to fetch team schedule: #{inspect(reason)}")
    end

    new_state
  end
end
