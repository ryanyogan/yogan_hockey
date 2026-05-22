defmodule YoganHockey.LiveGames.PredictionServerTest do
  use ExUnit.Case, async: false

  alias YoganHockey.LiveGames.PredictionServer
  alias YoganHockey.Cache
  alias YoganHockey.HTTP.MockOpenAIAdapter

  # Sample game data for testing
  defp sample_game(id, state \\ "in", away_score \\ 2, home_score \\ 1) do
    %{
      id: id,
      status: %{state: state, period: 2, display_clock: "10:00"},
      away_team: %{
        id: "1",
        abbreviation: "TOR",
        score: away_score,
        logo: "tor.png",
        records: %{"total" => "30-20-5"}
      },
      home_team: %{
        id: "2",
        abbreviation: "MTL",
        score: home_score,
        logo: "mtl.png",
        records: %{"total" => "25-25-5"}
      }
    }
  end

  setup do
    {:ok, _} = MockOpenAIAdapter.start_link()
    Application.put_env(:yogan_hockey, :openai_adapter, MockOpenAIAdapter)

    # Clear caches
    Enum.each(Cache.tables(), fn table ->
      try do
        Cache.clear(table)
      rescue
        ArgumentError -> :ok
      end
    end)

    on_exit(fn ->
      # Stop server if running
      case Process.whereis(PredictionServer) do
        nil -> :ok
        pid when is_pid(pid) ->
          try do
            GenServer.stop(PredictionServer, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
      end

      MockOpenAIAdapter.stop()
      Application.delete_env(:yogan_hockey, :openai_adapter)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer" do
      assert {:ok, pid} = PredictionServer.start_link([])
      assert Process.alive?(pid)
    end

    test "subscribes to live scores topic" do
      {:ok, _pid} = PredictionServer.start_link([])

      # Broadcast a message to verify subscription
      Phoenix.PubSub.broadcast(
        YoganHockey.PubSub,
        "nhl:live_scores",
        {:live_scores_updated, []}
      )

      # Server should handle it without crashing
      Process.sleep(50)
      assert Process.whereis(PredictionServer) != nil
    end
  end

  describe "get_prediction/1" do
    test "returns nil when no prediction exists" do
      {:ok, _pid} = PredictionServer.start_link([])
      assert PredictionServer.get_prediction("game123") == nil
    end

    test "returns cached prediction when it exists" do
      {:ok, _pid} = PredictionServer.start_link([])

      prediction = %{
        game_id: "game123",
        predicted_winner: "TOR",
        winner_probability: 0.65
      }

      Cache.put(:live_game_predictions, "game123", prediction)

      assert PredictionServer.get_prediction("game123") == prediction
    end
  end

  describe "get_all_predictions/0" do
    test "returns empty map when no predictions exist" do
      {:ok, _pid} = PredictionServer.start_link([])
      assert PredictionServer.get_all_predictions() == %{}
    end

    test "returns all predictions as a map" do
      {:ok, _pid} = PredictionServer.start_link([])

      prediction1 = %{game_id: "game1", predicted_winner: "TOR", winner_probability: 0.6}
      prediction2 = %{game_id: "game2", predicted_winner: "MTL", winner_probability: 0.55}

      Cache.put(:live_game_predictions, "game1", prediction1)
      Cache.put(:live_game_predictions, "game2", prediction2)

      predictions = PredictionServer.get_all_predictions()

      assert map_size(predictions) == 2
      assert predictions["game1"] == prediction1
      assert predictions["game2"] == prediction2
    end
  end

  describe "ensure_predictions/1" do
    test "generates predictions for games without existing predictions" do
      MockOpenAIAdapter.expect(
        {:ok, ~s|{"winner": "TOR", "win_probability": 65, "loser": "MTL", "lose_probability": 35}|}
      )

      {:ok, _pid} = PredictionServer.start_link([])
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")

      game = sample_game("game123")
      PredictionServer.ensure_predictions([game])

      # Wait for async prediction generation
      assert_receive {:prediction_updated, "game123", prediction}, 2000
      assert prediction.predicted_winner == "TOR"
      assert prediction.winner_probability == 0.65
    end

    test "does not regenerate predictions for games that already have one" do
      {:ok, _pid} = PredictionServer.start_link([])

      # Pre-populate cache
      existing_prediction = %{game_id: "game123", predicted_winner: "MTL", winner_probability: 0.7}
      Cache.put(:live_game_predictions, "game123", existing_prediction)

      game = sample_game("game123")
      PredictionServer.ensure_predictions([game])

      # Wait a bit to ensure no new prediction was generated
      Process.sleep(200)

      # Should still have the original prediction
      assert PredictionServer.get_prediction("game123") == existing_prediction
      assert MockOpenAIAdapter.call_count() == 0
    end
  end

  describe "score change detection" do
    test "regenerates prediction when score changes" do
      MockOpenAIAdapter.expect(
        {:ok, ~s|{"winner": "TOR", "win_probability": 60, "loser": "MTL", "lose_probability": 40}|}
      )
      MockOpenAIAdapter.expect(
        {:ok, ~s|{"winner": "MTL", "win_probability": 55, "loser": "TOR", "lose_probability": 45}|}
      )

      {:ok, _pid} = PredictionServer.start_link([])
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")

      # First update with initial score
      game_v1 = sample_game("game123", "in", 1, 0)
      Phoenix.PubSub.broadcast(
        YoganHockey.PubSub,
        "nhl:live_scores",
        {:live_scores_updated, [game_v1]}
      )

      # Wait for initial state to be recorded
      Process.sleep(100)

      # Second update with changed score (goal scored)
      game_v2 = sample_game("game123", "in", 1, 1)
      Phoenix.PubSub.broadcast(
        YoganHockey.PubSub,
        "nhl:live_scores",
        {:live_scores_updated, [game_v2]}
      )

      # Should receive a new prediction due to score change
      assert_receive {:prediction_updated, "game123", _prediction}, 2000
    end

    test "does not regenerate prediction when score stays the same" do
      {:ok, _pid} = PredictionServer.start_link([])

      # Pre-populate with existing prediction
      existing = %{game_id: "game123", predicted_winner: "TOR", winner_probability: 0.6}
      Cache.put(:live_game_predictions, "game123", existing)

      # Send same score twice
      game = sample_game("game123", "in", 2, 1)

      Phoenix.PubSub.broadcast(
        YoganHockey.PubSub,
        "nhl:live_scores",
        {:live_scores_updated, [game]}
      )
      Process.sleep(100)

      Phoenix.PubSub.broadcast(
        YoganHockey.PubSub,
        "nhl:live_scores",
        {:live_scores_updated, [game]}
      )
      Process.sleep(200)

      # OpenAI should not have been called
      assert MockOpenAIAdapter.call_count() == 0
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts prediction_updated when prediction is generated" do
      MockOpenAIAdapter.expect(
        {:ok, ~s|{"winner": "TOR", "win_probability": 70, "loser": "MTL", "lose_probability": 30}|}
      )

      {:ok, _pid} = PredictionServer.start_link([])
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")

      game = sample_game("game456")
      PredictionServer.ensure_predictions([game])

      assert_receive {:prediction_updated, "game456", prediction}, 2000
      assert prediction.game_id == "game456"
      assert prediction.predicted_winner == "TOR"
    end
  end
end
