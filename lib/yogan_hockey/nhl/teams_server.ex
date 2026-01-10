defmodule YoganHockey.NHL.TeamsServer do
  @moduledoc """
  GenServer that polls NHL teams and standings every 5 minutes.

  Less frequent polling since this data doesn't change as often.
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

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting NHL TeamsServer with #{div(@poll_interval, 1000)}s interval")

    # Initial fetch
    send(self(), :poll)

    {:ok, %{last_poll: nil}}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = do_poll(state)

    # Schedule next poll
    Process.send_after(self(), :poll, @poll_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    new_state = do_poll(state)
    {:noreply, new_state}
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
end
