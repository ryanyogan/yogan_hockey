defmodule YoganHockey.LiveGames.PredictionServerDistributedTest do
  @moduledoc """
  Tests for the PredictionServer's distribution-aware functions.

  These tests verify:
  - ensure_predictions forwards to primary when on replica
  - refresh_prediction forwards to primary when on replica
  - Local execution when on primary
  """
  use ExUnit.Case, async: false

  alias YoganHockey.LiveGames.PredictionServer
  alias YoganHockey.Cluster.Primary
  alias YoganHockey.Cache
  alias YoganHockey.HTTP.MockAnthropicAdapter

  defp sample_game(id) do
    %{
      id: id,
      status: %{state: "in", period: 2, display_clock: "10:00"},
      away_team: %{
        id: "1",
        abbreviation: "TOR",
        score: 2,
        logo: "tor.png",
        records: %{"total" => "30-20-5"}
      },
      home_team: %{
        id: "2",
        abbreviation: "MTL",
        score: 1,
        logo: "mtl.png",
        records: %{"total" => "25-25-5"}
      }
    }
  end

  setup do
    # Store original env vars
    original_fly_region = System.get_env("FLY_REGION")
    original_primary_region = System.get_env("PRIMARY_REGION")

    # Start mock Anthropic adapter
    {:ok, _} = MockAnthropicAdapter.start_link()
    Application.put_env(:yogan_hockey, :anthropic_adapter, MockAnthropicAdapter)

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

      MockAnthropicAdapter.stop()
      Application.delete_env(:yogan_hockey, :anthropic_adapter)

      # Restore env vars
      if original_fly_region do
        System.put_env("FLY_REGION", original_fly_region)
      else
        System.delete_env("FLY_REGION")
      end

      if original_primary_region do
        System.put_env("PRIMARY_REGION", original_primary_region)
      else
        System.delete_env("PRIMARY_REGION")
      end
    end)

    :ok
  end

  describe "ensure_predictions/1 distribution" do
    test "executes locally when on primary region" do
      # Set up as primary
      System.delete_env("FLY_REGION")
      System.delete_env("PRIMARY_REGION")

      assert Primary.primary?() == true

      MockAnthropicAdapter.expect(
        {:ok, ~s|{"winner": "TOR", "win_probability": 65, "loser": "MTL", "lose_probability": 35}|}
      )

      {:ok, _pid} = PredictionServer.start_link([])
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")

      game = sample_game("game_primary")
      result = PredictionServer.ensure_predictions([game])

      assert result == :ok

      # Should receive prediction via PubSub
      assert_receive {:prediction_updated, "game_primary", prediction}, 2000
      assert prediction.predicted_winner == "TOR"
    end

    test "returns :ok but doesn't execute locally when on replica with no primary" do
      # Set up as replica
      System.put_env("FLY_REGION", "ewr")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == false

      # Don't start the server (simulating replica without GenServer)
      game = sample_game("game_replica")
      result = PredictionServer.ensure_predictions([game])

      # Should return :ok (cast_to_primary returns :ok or error)
      # The actual cast fails silently because no primary is available
      assert result == :ok

      # Anthropic should not have been called (no local execution)
      assert MockAnthropicAdapter.call_count() == 0
    end
  end

  describe "refresh_prediction/2 distribution" do
    test "executes locally when on primary region" do
      System.delete_env("FLY_REGION")
      System.delete_env("PRIMARY_REGION")

      assert Primary.primary?() == true

      MockAnthropicAdapter.expect(
        {:ok, ~s|{"winner": "MTL", "win_probability": 55, "loser": "TOR", "lose_probability": 45}|}
      )

      {:ok, _pid} = PredictionServer.start_link([])
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")

      game = sample_game("game_refresh")
      result = PredictionServer.refresh_prediction("game_refresh", game)

      assert result == :ok

      # Should receive prediction via PubSub
      assert_receive {:prediction_updated, "game_refresh", prediction}, 2000
      assert prediction.predicted_winner == "MTL"
    end

    test "returns :ok when on replica (forwards to primary)" do
      System.put_env("FLY_REGION", "lhr")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == false

      game = sample_game("game_replica_refresh")
      result = PredictionServer.refresh_prediction("game_replica_refresh", game)

      # Should return :ok (the cast is sent even if primary unavailable)
      assert result == :ok
    end
  end

  describe "get_prediction/1" do
    test "reads from local cache regardless of region" do
      # This should work on any node since it reads from local ETS
      System.put_env("FLY_REGION", "lhr")
      System.put_env("PRIMARY_REGION", "dfw")

      prediction = %{
        game_id: "cached_game",
        predicted_winner: "TOR",
        winner_probability: 0.65
      }

      Cache.put(:live_game_predictions, "cached_game", prediction)

      result = PredictionServer.get_prediction("cached_game")

      assert result == prediction
    end
  end

  describe "get_all_predictions/0" do
    test "reads from local cache regardless of region" do
      System.put_env("FLY_REGION", "sjc")
      System.put_env("PRIMARY_REGION", "dfw")

      prediction1 = %{game_id: "game1", predicted_winner: "TOR", winner_probability: 0.6}
      prediction2 = %{game_id: "game2", predicted_winner: "MTL", winner_probability: 0.55}

      Cache.put(:live_game_predictions, "game1", prediction1)
      Cache.put(:live_game_predictions, "game2", prediction2)

      result = PredictionServer.get_all_predictions()

      assert map_size(result) == 2
      assert result["game1"] == prediction1
      assert result["game2"] == prediction2
    end
  end

  describe "do_ensure_predictions/1 (RPC target)" do
    test "casts to local GenServer" do
      System.delete_env("FLY_REGION")

      MockAnthropicAdapter.expect(
        {:ok, ~s|{"winner": "TOR", "win_probability": 70, "loser": "MTL", "lose_probability": 30}|}
      )

      {:ok, _pid} = PredictionServer.start_link([])
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")

      game = sample_game("game_rpc")

      # This is the function called via RPC from replicas
      PredictionServer.do_ensure_predictions([game])

      assert_receive {:prediction_updated, "game_rpc", prediction}, 2000
      assert prediction.predicted_winner == "TOR"
    end
  end

  describe "do_refresh_prediction/2 (RPC target)" do
    test "casts to local GenServer" do
      System.delete_env("FLY_REGION")

      MockAnthropicAdapter.expect(
        {:ok, ~s|{"winner": "MTL", "win_probability": 60, "loser": "TOR", "lose_probability": 40}|}
      )

      {:ok, _pid} = PredictionServer.start_link([])
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")

      game = sample_game("game_rpc_refresh")

      # This is the function called via RPC from replicas
      PredictionServer.do_refresh_prediction("game_rpc_refresh", game)

      assert_receive {:prediction_updated, "game_rpc_refresh", prediction}, 2000
      assert prediction.predicted_winner == "MTL"
    end
  end
end
