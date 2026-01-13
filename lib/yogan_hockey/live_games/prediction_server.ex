defmodule YoganHockey.LiveGames.PredictionServer do
  @moduledoc """
  GenServer that manages AI predictions for live NHL games.

  - Generates predictions when games start or when requested
  - Detects scoring events and regenerates predictions for affected games
  - Each prediction is generated asynchronously via Task.Supervisor
  - Broadcasts prediction updates via PubSub
  """

  use GenServer

  require Logger

  alias YoganHockey.{Cache, Anthropic}
  alias YoganHockey.Cluster.Primary

  @pubsub YoganHockey.PubSub
  @predictions_topic "live_games:predictions"

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the prediction for a specific game.
  Returns nil if no prediction exists.
  """
  @spec get_prediction(String.t()) :: map() | nil
  def get_prediction(game_id) do
    Cache.get(:live_game_predictions, game_id)
  end

  @doc """
  Gets all current predictions as a map of game_id => prediction.
  """
  @spec get_all_predictions() :: map()
  def get_all_predictions do
    Cache.all(:live_game_predictions)
    |> Enum.reduce(%{}, fn prediction, acc ->
      Map.put(acc, prediction.game_id, prediction)
    end)
  end

  @doc """
  Requests prediction generation for the given games.
  Used when a user visits the live scores page.
  Forwards to primary node if called from a replica.
  """
  @spec ensure_predictions(list()) :: :ok
  def ensure_predictions(games) do
    if Primary.primary?() do
      GenServer.cast(__MODULE__, {:ensure_predictions, games})
    else
      # Forward to primary via RPC (cast, don't wait for response)
      Primary.cast_to_primary(__MODULE__, :do_ensure_predictions, [games])
    end

    :ok
  end

  @doc false
  # Called via RPC from replicas
  def do_ensure_predictions(games) do
    GenServer.cast(__MODULE__, {:ensure_predictions, games})
  end

  @doc """
  Forces regeneration of a prediction for a specific game.
  Forwards to primary node if called from a replica.
  """
  @spec refresh_prediction(String.t(), map()) :: :ok
  def refresh_prediction(game_id, game) do
    if Primary.primary?() do
      GenServer.cast(__MODULE__, {:refresh_prediction, game_id, game})
    else
      Primary.cast_to_primary(__MODULE__, :do_refresh_prediction, [game_id, game])
    end

    :ok
  end

  @doc false
  # Called via RPC from replicas
  def do_refresh_prediction(game_id, game) do
    GenServer.cast(__MODULE__, {:refresh_prediction, game_id, game})
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting LiveGamePredictionServer")

    # Subscribe to live scores for score change detection
    Phoenix.PubSub.subscribe(@pubsub, "nhl:live_scores")

    {:ok,
     %{
       # Track scores to detect changes: %{game_id => %{away: score, home: score}}
       previous_scores: %{},
       # Track which games are currently generating predictions
       generating: MapSet.new()
     }}
  end

  @impl true
  def handle_cast({:ensure_predictions, games}, state) do
    Logger.info("ensure_predictions called with #{length(games)} games")

    # Filter to games that don't have predictions and aren't already generating
    games_needing_predictions =
      games
      |> Enum.filter(fn game ->
        game_id = game.id
        not MapSet.member?(state.generating, game_id) and
          Cache.get(:live_game_predictions, game_id) == nil
      end)

    Logger.info("#{length(games_needing_predictions)} games need predictions")

    # Start prediction generation for each game
    new_generating =
      Enum.reduce(games_needing_predictions, state.generating, fn game, acc ->
        Logger.info("Starting prediction task for game #{game.id}: #{game.away_team.abbreviation} @ #{game.home_team.abbreviation}")
        start_prediction_task(game)
        MapSet.put(acc, game.id)
      end)

    {:noreply, %{state | generating: new_generating}}
  end

  @impl true
  def handle_cast({:refresh_prediction, game_id, game}, state) do
    unless MapSet.member?(state.generating, game_id) do
      start_prediction_task(game)
      {:noreply, %{state | generating: MapSet.put(state.generating, game_id)}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:live_scores_updated, games}, state) do
    # Build current scores map
    current_scores = build_scores_map(games)

    # Find games where the score changed (scoring event)
    games_with_score_changes =
      Enum.filter(games, fn game ->
        game_id = game.id
        current = Map.get(current_scores, game_id)
        previous = Map.get(state.previous_scores, game_id)

        # Only trigger for games in progress with score changes
        game.status.state == "in" and
          previous != nil and
          current != previous
      end)

    # Regenerate predictions for games with score changes
    new_generating =
      Enum.reduce(games_with_score_changes, state.generating, fn game, acc ->
        unless MapSet.member?(acc, game.id) do
          Logger.info("Score changed in #{game.away_team.abbreviation} @ #{game.home_team.abbreviation}, regenerating prediction")
          start_prediction_task(game)
          MapSet.put(acc, game.id)
        else
          acc
        end
      end)

    {:noreply, %{state | previous_scores: current_scores, generating: new_generating}}
  end

  @impl true
  def handle_info({:prediction_complete, game_id, result}, state) do
    case result do
      {:ok, prediction} ->
        # Store in cache
        Cache.put(:live_game_predictions, game_id, prediction)

        # Broadcast update
        Logger.info("Broadcasting prediction for game #{game_id}: #{prediction.predicted_winner} (#{prediction.winner_probability})")
        Phoenix.PubSub.broadcast(@pubsub, @predictions_topic, {:prediction_updated, game_id, prediction})

      {:error, reason} ->
        Logger.warning("Failed to generate prediction for game #{game_id}: #{inspect(reason)}")
    end

    {:noreply, %{state | generating: MapSet.delete(state.generating, game_id)}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private Functions ---

  defp build_scores_map(games) do
    Map.new(games, fn game ->
      {game.id, %{away: game.away_team.score, home: game.home_team.score}}
    end)
  end

  defp start_prediction_task(game) do
    parent = self()
    game_id = game.id

    Task.Supervisor.start_child(YoganHockey.TaskSupervisor, fn ->
      result = Anthropic.predict_live_game_winner(game)
      send(parent, {:prediction_complete, game_id, result})
    end)
  end
end
