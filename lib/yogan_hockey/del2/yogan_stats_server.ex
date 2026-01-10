defmodule YoganHockey.DEL2.YoganStatsServer do
  @moduledoc """
  GenServer that polls Andrew Yogan's stats from Elite Prospects every 5 minutes.

  Stats don't change frequently, so a longer polling interval is appropriate.
  """

  use GenServer

  require Logger

  alias YoganHockey.DEL2

  @poll_interval :timer.minutes(5)

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
    Logger.info("Starting YoganStatsServer with #{div(@poll_interval, 1000)}s interval")

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
    case DEL2.refresh_yogan_stats() do
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
  end
end
