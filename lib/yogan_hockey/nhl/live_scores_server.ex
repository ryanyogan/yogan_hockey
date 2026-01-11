defmodule YoganHockey.NHL.LiveScoresServer do
  @moduledoc """
  GenServer that polls NHL live scores every 30 seconds.

  Broadcasts updates via PubSub when new data is available.
  """

  use GenServer

  require Logger

  alias YoganHockey.NHL

  @poll_interval :timer.seconds(30)

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Forces an immediate refresh of live scores.
  """
  def refresh_now do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Returns the current polling interval in milliseconds.
  """
  def poll_interval, do: @poll_interval

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting NHL LiveScoresServer with #{@poll_interval}ms interval")

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
    case NHL.refresh_live_scores() do
      {:ok, games} ->
        Logger.debug("Fetched #{length(games)} NHL games")

        # Broadcast to subscribers
        Phoenix.PubSub.broadcast(
          YoganHockey.PubSub,
          "nhl:live_scores",
          {:live_scores_updated, games}
        )

        # Refresh team details for teams currently playing
        refresh_playing_team_details(games)

        %{state | last_poll: DateTime.utc_now()}

      {:error, reason} ->
        Logger.warning("Failed to fetch live scores: #{inspect(reason)}")
        state
    end
  end

  # Refresh team details for teams that are currently playing
  defp refresh_playing_team_details(games) do
    live_games = Enum.filter(games, &(&1.status.state == "in"))

    if live_games != [] do
      team_ids =
        live_games
        |> Enum.flat_map(fn game ->
          [game.home_team.id, game.away_team.id]
        end)
        |> Enum.uniq()
        |> Enum.filter(&(&1 != nil))

      if team_ids != [] do
        YoganHockey.NHL.TeamsServer.refresh_team_details(team_ids)
      end
    end
  end
end
