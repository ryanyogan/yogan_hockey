defmodule YoganHockey.NHL.LiveScoresServerTest do
  use ExUnit.Case, async: false

  alias YoganHockey.NHL.LiveScoresServer
  alias YoganHockey.Cache
  alias YoganHockey.HTTP.MockAdapter

  setup do
    # Start mock adapter
    {:ok, _} = MockAdapter.start_link()
    Application.put_env(:yogan_hockey, :http_adapter, MockAdapter)

    # Clear caches
    Enum.each(Cache.tables(), &Cache.clear/1)

    # Setup mock response for scoreboard
    MockAdapter.expect("scoreboard", {:ok, %{
      "events" => [
        %{
          "id" => "123",
          "name" => "Test Game",
          "shortName" => "TST @ TST",
          "date" => "2024-01-15T19:00:00Z",
          "competitions" => [
            %{
              "competitors" => [
                %{"homeAway" => "home", "team" => %{"id" => "1", "name" => "Home", "abbreviation" => "HOM", "logo" => ""}, "score" => "3"},
                %{"homeAway" => "away", "team" => %{"id" => "2", "name" => "Away", "abbreviation" => "AWY", "logo" => ""}, "score" => "2"}
              ],
              "status" => %{"type" => %{"state" => "post", "completed" => true, "shortDetail" => "Final"}}
            }
          ]
        }
      ]
    }})

    on_exit(fn ->
      # Stop server if running
      case Process.whereis(LiveScoresServer) do
        nil -> :ok
        pid when is_pid(pid) ->
          try do
            GenServer.stop(LiveScoresServer)
          catch
            :exit, _ -> :ok
          end
      end
      MockAdapter.stop()
      Application.delete_env(:yogan_hockey, :http_adapter)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer" do
      assert {:ok, pid} = LiveScoresServer.start_link([])
      assert Process.alive?(pid)
    end

    test "performs initial poll on startup" do
      {:ok, _pid} = LiveScoresServer.start_link([])

      # Wait for initial poll
      Process.sleep(100)

      # Cache should be populated
      scores = Cache.get(:nhl_live_scores, :current)
      assert is_list(scores)
    end
  end

  describe "refresh_now/0" do
    test "triggers immediate refresh" do
      {:ok, _pid} = LiveScoresServer.start_link([])
      Process.sleep(100)

      # Should not raise
      assert :ok = LiveScoresServer.refresh_now()
    end
  end

  describe "poll_interval/0" do
    test "returns configured interval in milliseconds" do
      interval = LiveScoresServer.poll_interval()
      assert is_integer(interval)
      assert interval == :timer.seconds(30)
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts live_scores_updated on successful poll" do
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")

      {:ok, _pid} = LiveScoresServer.start_link([])

      assert_receive {:live_scores_updated, games}, 1000
      assert is_list(games)
    end
  end
end
