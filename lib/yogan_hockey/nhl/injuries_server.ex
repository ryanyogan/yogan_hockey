defmodule YoganHockey.NHL.InjuriesServer do
  @moduledoc """
  GenServer that polls NHL injuries every hour.

  Injuries don't change frequently, so an hourly poll is sufficient.
  Data is cached in ETS for fast read access.
  """

  use GenServer

  require Logger

  alias YoganHockey.NHL

  @poll_interval :timer.hours(1)

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Forces an immediate refresh of injuries data.
  """
  def refresh_now do
    GenServer.cast(__MODULE__, :refresh)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting NHL InjuriesServer with #{div(@poll_interval, 60_000)} min interval")

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
    case NHL.refresh_injuries() do
      {:ok, injuries} ->
        Logger.debug("Fetched #{length(injuries)} NHL injuries")

        Phoenix.PubSub.broadcast(
          YoganHockey.PubSub,
          "nhl:injuries",
          {:injuries_updated, injuries}
        )

      {:error, reason} ->
        Logger.warning("Failed to fetch injuries: #{inspect(reason)}")
    end

    %{state | last_poll: DateTime.utc_now()}
  end
end
