defmodule YoganHockey.Games.GamePersistenceServer do
  @moduledoc """
  Background GenServer that saves completed game data to the database.

  Subscribes to live scores updates and detects when games transition
  from "in" (live) to "post" (completed). When a game completes,
  fetches full game data from ESPN and persists to SQLite.

  This ensures ALL completed games are saved, not just ones being actively viewed.
  """
  use GenServer

  require Logger

  alias YoganHockey.Games
  alias YoganHockey.NHL.APIClient
  alias YoganHockey.NHL.Parsers

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting GamePersistenceServer")
    Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")
    {:ok, %{live_game_ids: MapSet.new()}}
  end

  @impl true
  def handle_info({:live_scores_updated, games}, state) do
    # Identify games currently live
    current_live_ids =
      games
      |> Enum.filter(&(&1.status.state == "in"))
      |> Enum.map(&to_string(&1.id))
      |> MapSet.new()

    # Identify games that just completed (were live, now post)
    newly_completed_ids =
      games
      |> Enum.filter(&(&1.status.state == "post"))
      |> Enum.map(&to_string(&1.id))
      |> Enum.filter(&MapSet.member?(state.live_game_ids, &1))

    # Save each newly completed game (async to not block the GenServer)
    Enum.each(newly_completed_ids, fn game_id ->
      Task.Supervisor.start_child(
        YoganHockey.TaskSupervisor,
        fn -> save_completed_game(game_id) end
      )
    end)

    {:noreply, %{state | live_game_ids: current_live_ids}}
  end

  # Ignore other messages
  def handle_info(_msg, state), do: {:noreply, state}

  defp save_completed_game(game_id) do
    # Skip if already saved
    if Games.get_completed_game(game_id) do
      Logger.debug("Game #{game_id} already saved, skipping")
    else
      Logger.info("Fetching and saving completed game #{game_id}")

      with {:ok, summary_data} <- APIClient.get_game_summary(game_id),
           game_data when not is_nil(game_data) <- Parsers.parse_game_summary(summary_data) do
        # Fetch full plays from core API (returns all plays, not just 100)
        game_data = fetch_full_plays(game_id, game_data)
        Games.save_completed_game(game_data)
      else
        nil ->
          Logger.warning("Failed to parse game #{game_id} for persistence")

        {:error, reason} ->
          Logger.warning("Failed to fetch game #{game_id} for persistence: #{inspect(reason)}")
      end
    end
  end

  # Fetch full play-by-play from core API and merge into game data
  defp fetch_full_plays(game_id, game_data) do
    case APIClient.get_game_plays(game_id) do
      {:ok, plays_data} ->
        plays = Parsers.parse_core_api_plays(plays_data, game_data.home_team, game_data.away_team)
        Logger.info("Fetched #{length(plays)} plays for game #{game_id} from core API")
        %{game_data | plays: plays}

      {:error, reason} ->
        Logger.warning("Failed to fetch plays from core API for #{game_id}: #{inspect(reason)}, using summary plays")
        game_data
    end
  end
end
