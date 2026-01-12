defmodule YoganHockey.NHL.TeamsServer do
  @moduledoc """
  GenServer that polls NHL teams and standings every 5 minutes.

  On startup, pre-populates the ETS cache with all team details for fast access.
  """

  use GenServer

  require Logger

  alias YoganHockey.NHL

  @poll_interval :timer.minutes(5)

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Forces an immediate refresh of teams and standings.
  """
  def refresh_now do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Pre-populates the cache with team details for specific team IDs.
  Called when teams are playing live games.
  """
  def refresh_team_details(team_ids) when is_list(team_ids) do
    GenServer.cast(__MODULE__, {:refresh_team_details, team_ids})
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting NHL TeamsServer with #{div(@poll_interval, 1000)}s interval")

    # Initial fetch
    send(self(), :poll)

    # Pre-populate all team details after initial teams load
    send(self(), :prepopulate_team_details)

    {:ok, %{last_poll: nil, prepopulated: false}}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = do_poll(state)

    # Schedule next poll
    Process.send_after(self(), :poll, @poll_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:prepopulate_team_details, %{prepopulated: true} = state) do
    # Already prepopulated, skip
    {:noreply, state}
  end

  @impl true
  def handle_info(:prepopulate_team_details, state) do
    # Schedule prepopulation after a delay (non-blocking)
    Process.send_after(self(), :do_prepopulate, 2000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:do_prepopulate, state) do
    teams = NHL.list_teams()

    if teams == [] do
      Logger.warning("No teams available to prepopulate - will retry in 30s")
      Process.send_after(self(), :do_prepopulate, 30_000)
      {:noreply, state}
    else
      # Run prepopulation in a supervised task to avoid blocking the GenServer
      Task.Supervisor.start_child(YoganHockey.TaskSupervisor, fn ->
        do_prepopulate_teams(teams)
      end)
      {:noreply, %{state | prepopulated: true}}
    end
  end

  @impl true
  def handle_cast(:refresh, state) do
    new_state = do_poll(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:refresh_team_details, team_ids}, state) do
    # Refresh team details in background using supervised task
    Task.Supervisor.start_child(YoganHockey.TaskSupervisor, fn ->
      Enum.each(team_ids, fn team_id ->
        refresh_single_team_detail(team_id)
      end)
    end)

    {:noreply, state}
  end

  # --- Private ---

  defp do_poll(state) do
    # Fetch teams
    case NHL.refresh_teams() do
      {:ok, teams} ->
        Logger.debug("Fetched #{length(teams)} NHL teams")

        Phoenix.PubSub.broadcast(
          YoganHockey.PubSub,
          "nhl:teams",
          {:teams_updated, teams}
        )

      {:error, reason} ->
        Logger.warning("Failed to fetch teams: #{inspect(reason)}")
    end

    # Fetch standings
    case NHL.refresh_standings() do
      {:ok, standings} ->
        Logger.debug("Fetched standings for #{length(standings)} teams")

        Phoenix.PubSub.broadcast(
          YoganHockey.PubSub,
          "nhl:standings",
          {:standings_updated, standings}
        )

      {:error, reason} ->
        Logger.warning("Failed to fetch standings: #{inspect(reason)}")
    end

    %{state | last_poll: DateTime.utc_now()}
  end

  defp do_prepopulate_teams(teams) do
    Logger.info("Pre-populating team details for #{length(teams)} teams...")

    teams
    |> Enum.map(& &1.id)
    |> Enum.chunk_every(4)
    |> Enum.each(fn chunk ->
      # Fetch in parallel batches of 4 using supervised tasks
      tasks =
        Enum.map(chunk, fn team_id ->
          Task.Supervisor.async_nolink(YoganHockey.TaskSupervisor, fn ->
            refresh_single_team_detail(team_id)
          end)
        end)

      Task.await_many(tasks, 30_000)

      # Small delay between batches to avoid rate limiting
      Process.sleep(500)
    end)

    Logger.info("Finished pre-populating team details for #{length(teams)} teams")
  end

  defp refresh_single_team_detail(team_id) do
    # Run both API calls in parallel for ~50% speedup
    details_task =
      Task.Supervisor.async_nolink(YoganHockey.TaskSupervisor, fn ->
        NHL.get_team_details(team_id)
      end)

    schedule_task =
      Task.Supervisor.async_nolink(YoganHockey.TaskSupervisor, fn ->
        NHL.get_team_schedule(team_id)
      end)

    # Wait for both to complete
    details_result = Task.await(details_task, 15_000)
    schedule_result = Task.await(schedule_task, 15_000)

    # Log results
    case details_result do
      {:ok, _team} ->
        Logger.debug("Pre-populated team details for team #{team_id}")

      {:error, reason} ->
        Logger.warning("Failed to pre-populate team #{team_id}: #{inspect(reason)}")
    end

    case schedule_result do
      {:ok, _schedule} ->
        Logger.debug("Pre-populated schedule for team #{team_id}")

      {:error, reason} ->
        Logger.warning("Failed to pre-populate schedule for team #{team_id}: #{inspect(reason)}")
    end

    :ok
  end
end
