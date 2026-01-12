defmodule YoganHockey.NHL.TeamsServerTest do
  use ExUnit.Case, async: false

  alias YoganHockey.NHL.TeamsServer
  alias YoganHockey.Cache
  alias YoganHockey.HTTP.MockAdapter

  setup do
    # Start mock adapter
    {:ok, _} = MockAdapter.start_link()
    Application.put_env(:yogan_hockey, :http_adapter, MockAdapter)

    # Clear caches
    Enum.each(Cache.tables(), &Cache.clear/1)

    # Setup mock responses for teams and standings
    MockAdapter.expect("teams", {:ok, %{
      "sports" => [%{
        "leagues" => [%{
          "teams" => [
            %{
              "team" => %{
                "id" => "1",
                "name" => "Test Team",
                "displayName" => "Test Team",
                "abbreviation" => "TST",
                "logos" => [%{"href" => "logo.png"}]
              }
            }
          ]
        }]
      }]
    }})

    MockAdapter.expect("standings", {:ok, %{
      "children" => []
    }})

    on_exit(fn ->
      # Stop server if running
      case Process.whereis(TeamsServer) do
        nil -> :ok
        pid when is_pid(pid) ->
          try do
            GenServer.stop(TeamsServer)
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
      assert {:ok, pid} = TeamsServer.start_link([])
      assert Process.alive?(pid)
    end
  end

  describe "refresh_now/0" do
    test "triggers immediate refresh without error" do
      {:ok, _pid} = TeamsServer.start_link([])

      # Wait for initial poll
      Process.sleep(100)

      # Should not raise
      assert :ok = TeamsServer.refresh_now()
    end
  end

  describe "refresh_team_details/1" do
    test "accepts list of team IDs" do
      # Add mock for team details
      MockAdapter.expect("teams/1", {:ok, %{
        "team" => %{
          "id" => "1",
          "name" => "Test Team",
          "displayName" => "Test Team",
          "abbreviation" => "TST",
          "logos" => [%{"href" => "logo.png"}],
          "athletes" => []
        }
      }})

      MockAdapter.expect("schedule", {:ok, %{
        "team" => %{"id" => "1"},
        "events" => []
      }})

      {:ok, _pid} = TeamsServer.start_link([])
      Process.sleep(100)

      # Should not raise
      assert :ok = TeamsServer.refresh_team_details(["1"])
    end
  end

  describe "init/1" do
    test "initializes with proper state" do
      {:ok, pid} = TeamsServer.start_link([])

      # Verify it's a proper GenServer
      assert Process.alive?(pid)
      assert Process.whereis(TeamsServer) == pid
    end
  end
end
