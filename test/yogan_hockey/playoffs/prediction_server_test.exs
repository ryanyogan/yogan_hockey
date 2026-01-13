defmodule YoganHockey.Playoffs.PredictionServerTest do
  use ExUnit.Case, async: false

  alias YoganHockey.Playoffs.PredictionServer
  alias YoganHockey.Cache
  alias YoganHockey.HTTP.MockAnthropicAdapter
  alias YoganHockey.HTTP.MockAdapter

  setup do
    # Start mock adapters
    {:ok, _} = MockAnthropicAdapter.start_link()
    {:ok, _} = MockAdapter.start_link()

    Application.put_env(:yogan_hockey, :anthropic_adapter, MockAnthropicAdapter)
    Application.put_env(:yogan_hockey, :http_adapter, MockAdapter)

    # Setup mock standings response
    MockAdapter.expect("standings", {:ok, %{
      "children" => [
        %{
          "name" => "Eastern Conference",
          "standings" => %{
            "entries" => [
              %{
                "team" => %{"id" => "1", "displayName" => "Test Team", "name" => "Test"},
                "stats" => [
                  %{"name" => "points", "value" => 100},
                  %{"name" => "wins", "value" => 45}
                ]
              }
            ]
          }
        }
      ]
    }})

    # Setup mock teams response
    MockAdapter.expect("teams", {:ok, %{
      "sports" => [%{
        "leagues" => [%{
          "teams" => [
            %{"team" => %{"id" => "1", "name" => "Test", "displayName" => "Test Team", "abbreviation" => "TST", "logos" => []}}
          ]
        }]
      }]
    }})

    # Clear caches
    Enum.each(Cache.tables(), fn table ->
      try do
        Cache.clear(table)
      rescue
        ArgumentError -> :ok
      end
    end)

    on_exit(fn ->
      # Stop server if running - use :shutdown to be more graceful
      case Process.whereis(PredictionServer) do
        nil -> :ok
        pid when is_pid(pid) ->
          ref = Process.monitor(pid)
          try do
            GenServer.stop(PredictionServer, :shutdown, 5000)
          catch
            :exit, _ -> :ok
          end
          # Wait for process to actually terminate
          receive do
            {:DOWN, ^ref, :process, ^pid, _} -> :ok
          after
            5000 -> :ok
          end
      end

      # Wait for any spawned tasks to complete/fail
      Process.sleep(100)

      # Now safe to stop the mock adapters
      try do
        MockAnthropicAdapter.stop()
      catch
        :exit, _ -> :ok
      end

      try do
        MockAdapter.stop()
      catch
        :exit, _ -> :ok
      end

      Application.delete_env(:yogan_hockey, :anthropic_adapter)
      Application.delete_env(:yogan_hockey, :http_adapter)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer" do
      assert {:ok, pid} = PredictionServer.start_link([])
      assert Process.alive?(pid)
    end

    test "subscribes to live scores topic for game-end detection" do
      {:ok, _pid} = PredictionServer.start_link([])

      # Broadcast should not crash the server
      Phoenix.PubSub.broadcast(
        YoganHockey.PubSub,
        "nhl:live_scores",
        {:live_scores_updated, []}
      )

      Process.sleep(50)
      assert Process.whereis(PredictionServer) != nil
    end
  end

  describe "generating?/0" do
    test "returns false when not generating" do
      {:ok, _pid} = PredictionServer.start_link([])
      # Wait for initial check to complete
      Process.sleep(100)
      refute PredictionServer.generating?()
    end
  end

  describe "check_interval/0" do
    test "returns configured interval in milliseconds" do
      interval = PredictionServer.check_interval()
      assert is_integer(interval)
      assert interval == :timer.hours(1)
    end
  end

  describe "auto-generation on startup" do
    test "generates predictions when none exist in cache" do
      # Setup mock Anthropic response for playoff picture
      MockAnthropicAdapter.expect({:ok, playoff_picture_response()})

      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "playoffs:updates")

      {:ok, _pid} = PredictionServer.start_link([])

      # Should receive generation_started broadcast
      assert_receive {:generation_started}, 6000
    end

    test "does not generate when predictions already exist" do
      # Pre-populate cache with existing prediction
      Cache.put(:playoffs, :playoff_picture, %{
        eastern: [],
        western: [],
        cup_favorite: "Test Team",
        analysis: "Test analysis",
        generated_at: DateTime.utc_now()
      })

      {:ok, _pid} = PredictionServer.start_link([])

      # Wait for initial check
      Process.sleep(6000)

      # Anthropic should not have been called
      assert MockAnthropicAdapter.call_count() == 0
    end
  end

  describe "game ending detection" do
    test "regenerates predictions when a game ends" do
      # Pre-populate with existing prediction
      Cache.put(:playoffs, :playoff_picture, %{
        eastern: [],
        western: [],
        cup_favorite: "Test Team",
        analysis: "Test",
        generated_at: DateTime.utc_now()
      })

      MockAnthropicAdapter.expect({:ok, playoff_picture_response()})

      {:ok, _pid} = PredictionServer.start_link([])
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "playoffs:updates")

      # First update: game in progress
      game_in_progress = %{
        id: "game123",
        status: %{state: "in"},
        away_team: %{abbreviation: "TOR"},
        home_team: %{abbreviation: "MTL"}
      }

      Phoenix.PubSub.broadcast(
        YoganHockey.PubSub,
        "nhl:live_scores",
        {:live_scores_updated, [game_in_progress]}
      )

      Process.sleep(100)

      # Second update: game ended
      game_ended = %{
        id: "game123",
        status: %{state: "post"},
        away_team: %{abbreviation: "TOR"},
        home_team: %{abbreviation: "MTL"}
      }

      Phoenix.PubSub.broadcast(
        YoganHockey.PubSub,
        "nhl:live_scores",
        {:live_scores_updated, [game_ended]}
      )

      # Should receive generation_started because game ended
      assert_receive {:generation_started}, 2000
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts generation_started when starting generation" do
      # Pre-populate standings so prediction can be generated
      Cache.put(:nhl_standings, :current, sample_standings())
      Cache.put(:nhl_teams, :all, sample_teams())

      MockAnthropicAdapter.expect({:ok, playoff_picture_response()})

      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "playoffs:updates")

      {:ok, _pid} = PredictionServer.start_link([])

      assert_receive {:generation_started}, 6000
    end

    test "broadcasts playoff_picture_updated on successful generation" do
      # Pre-populate standings so prediction can be generated
      Cache.put(:nhl_standings, :current, sample_standings())
      Cache.put(:nhl_teams, :all, sample_teams())

      MockAnthropicAdapter.expect({:ok, playoff_picture_response()})

      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "playoffs:updates")

      {:ok, _pid} = PredictionServer.start_link([])

      # First we get generation_started
      assert_receive {:generation_started}, 6000

      # Then we should get the update (may take a while for API call)
      assert_receive {:playoff_picture_updated, _picture}, 10000
    end
  end

  defp sample_standings do
    [
      %{
        "name" => "Eastern Conference",
        "entries" => [
          %{
            "team" => %{"id" => "1", "displayName" => "Test Team"},
            "stats" => [%{"name" => "points", "value" => 100}]
          }
        ]
      }
    ]
  end

  defp sample_teams do
    [
      %{id: "1", name: "Test Team", abbreviation: "TST", logo: "test.png"}
    ]
  end

  # Helper to generate a valid playoff picture response
  defp playoff_picture_response do
    ~s|{
      "eastern": [
        {"team_id": "1", "team_name": "Test Team", "seed": 1, "playoff_prob": 99, "round2_prob": 70, "conf_final_prob": 45, "cup_final_prob": 25, "cup_win_prob": 12}
      ],
      "western": [
        {"team_id": "2", "team_name": "West Team", "seed": 1, "playoff_prob": 98, "round2_prob": 65, "conf_final_prob": 40, "cup_final_prob": 20, "cup_win_prob": 10}
      ],
      "cup_favorite": "Test Team",
      "analysis": "Test team looks strong"
    }|
  end
end
