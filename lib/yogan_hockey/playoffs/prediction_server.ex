defmodule YoganHockey.Playoffs.PredictionServer do
  @moduledoc """
  GenServer that autonomously manages playoff predictions.

  - Generates predictions on startup if none exist in ETS
  - Subscribes to live scores and regenerates when games end
  - Polls periodically to ensure predictions stay fresh
  - Broadcasts progress updates for real-time UI updates
  """

  use GenServer

  require Logger

  alias YoganHockey.{Playoffs, Cache}

  # Check every hour for missing predictions
  @check_interval :timer.hours(1)

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if predictions are currently being generated.
  """
  def generating? do
    GenServer.call(__MODULE__, :generating?)
  end

  @doc """
  Returns the configured check interval in milliseconds.
  """
  def check_interval, do: @check_interval

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting PredictionServer - autonomous playoff predictions")

    # Subscribe to live scores for game-end detection
    Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")

    # Check for predictions on startup (with a small delay to let other services start)
    Process.send_after(self(), :ensure_predictions, :timer.seconds(5))

    # Schedule periodic checks
    schedule_check()

    {:ok,
     %{
       generating: false,
       last_check: nil,
       previous_game_states: %{},
       generation_start: nil
     }}
  end

  @impl true
  def handle_call(:generating?, _from, state) do
    {:reply, state.generating, state}
  end

  @impl true
  def handle_info(:ensure_predictions, state) do
    new_state = ensure_predictions_exist(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:periodic_check, state) do
    new_state = ensure_predictions_exist(state)
    schedule_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:live_scores_updated, games}, state) do
    new_state = check_for_game_endings(games, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:generation_complete, result}, state) do
    case result do
      {:ok, picture} ->
        Logger.info("Playoff predictions generated successfully")
        broadcast_predictions_ready(picture)

      {:error, reason} ->
        Logger.warning("Failed to generate predictions: #{inspect(reason)}")
        broadcast_generation_failed(reason)
    end

    {:noreply, %{state | generating: false, generation_start: nil}}
  end

  # --- Private Functions ---

  defp schedule_check do
    Process.send_after(self(), :periodic_check, @check_interval)
  end

  defp ensure_predictions_exist(state) do
    if state.generating do
      Logger.debug("Predictions already generating, skipping check")
      state
    else
      case Cache.get(:playoffs, :playoff_picture) do
        nil ->
          Logger.info("No playoff predictions found, generating...")
          start_generation(state)

        _existing ->
          Logger.debug("Playoff predictions exist in cache")
          %{state | last_check: DateTime.utc_now()}
      end
    end
  end

  defp check_for_game_endings(games, state) do
    current_game_states = build_game_states(games)

    # Find games that just ended (transitioned from "in" to "post")
    ended_games =
      Enum.filter(games, fn game ->
        game_id = game.id
        current_state = game.status.state
        previous_state = Map.get(state.previous_game_states, game_id)

        # Game ended if it was "in" (in progress) and now is "post" (final)
        previous_state == "in" && current_state == "post"
      end)

    new_state = %{state | previous_game_states: current_game_states}

    if ended_games != [] && !state.generating do
      game_names = Enum.map(ended_games, fn g ->
        "#{g.away_team.abbreviation} @ #{g.home_team.abbreviation}"
      end)

      Logger.info("Games ended: #{Enum.join(game_names, ", ")} - regenerating predictions")

      # Clear cache and regenerate
      Cache.delete(:playoffs, :playoff_picture)
      start_generation(new_state)
    else
      new_state
    end
  end

  defp build_game_states(games) do
    Map.new(games, fn game -> {game.id, game.status.state} end)
  end

  defp start_generation(state) do
    # Broadcast that generation is starting
    broadcast_generation_started()

    # Start async generation
    parent = self()

    Task.Supervisor.start_child(YoganHockey.TaskSupervisor, fn ->
      result = Playoffs.generate_playoff_picture()
      send(parent, {:generation_complete, result})
    end)

    %{state | generating: true, generation_start: DateTime.utc_now()}
  end

  defp broadcast_generation_started do
    Phoenix.PubSub.broadcast(
      YoganHockey.PubSub,
      "playoffs:updates",
      {:generation_started}
    )
  end

  defp broadcast_predictions_ready(picture) do
    Phoenix.PubSub.broadcast(
      YoganHockey.PubSub,
      "playoffs:updates",
      {:playoff_picture_updated, picture}
    )
  end

  defp broadcast_generation_failed(reason) do
    Phoenix.PubSub.broadcast(
      YoganHockey.PubSub,
      "playoffs:updates",
      {:generation_failed, reason}
    )
  end
end
