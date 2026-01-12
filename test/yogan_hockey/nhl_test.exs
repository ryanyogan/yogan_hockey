defmodule YoganHockey.NHLTest do
  use ExUnit.Case, async: false

  alias YoganHockey.NHL
  alias YoganHockey.Cache
  alias YoganHockey.HTTP.MockAdapter

  setup do
    # Start mock adapter
    {:ok, _} = MockAdapter.start_link()

    # Configure app to use mock adapter
    Application.put_env(:yogan_hockey, :http_adapter, MockAdapter)

    # Clear caches
    Enum.each(Cache.tables(), &Cache.clear/1)

    on_exit(fn ->
      MockAdapter.stop()
      Application.delete_env(:yogan_hockey, :http_adapter)
    end)

    :ok
  end

  describe "list_live_scores/0" do
    test "returns empty list when cache is empty" do
      assert NHL.list_live_scores() == []
    end

    test "returns cached scores" do
      games = [%{id: "1", name: "Test Game"}]
      Cache.put(:nhl_live_scores, :current, games)

      assert NHL.list_live_scores() == games
    end
  end

  describe "refresh_live_scores/0" do
    test "fetches and caches scores on success" do
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

      assert {:ok, [game]} = NHL.refresh_live_scores()
      assert game.id == "123"

      # Verify cached
      assert [cached] = NHL.list_live_scores()
      assert cached.id == "123"
    end

    test "returns error on API failure" do
      MockAdapter.expect("scoreboard", {:error, :timeout})

      assert {:error, :timeout} = NHL.refresh_live_scores()
    end
  end

  describe "list_teams/0" do
    test "returns empty list when cache is empty" do
      assert NHL.list_teams() == []
    end

    test "returns cached teams" do
      teams = [%{id: "1", name: "Oilers"}]
      Cache.put(:nhl_teams, :all, teams)

      assert NHL.list_teams() == teams
    end
  end

  describe "get_team/1" do
    test "finds team by ID" do
      teams = [
        %{id: "1", name: "Oilers"},
        %{id: "2", name: "Flames"}
      ]
      Cache.put(:nhl_teams, :all, teams)

      assert NHL.get_team("1").name == "Oilers"
      assert NHL.get_team(1).name == "Oilers"
    end

    test "returns nil for non-existent team" do
      Cache.put(:nhl_teams, :all, [])
      assert NHL.get_team("999") == nil
    end
  end

  describe "get_team_details/1" do
    test "returns cached team details" do
      team = %{id: "1", name: "Test Team", roster: [], display_name: "Test Team"}
      Cache.put(:nhl_team_stats, {:team_details, "1"}, team)

      assert {:ok, result} = NHL.get_team_details("1")
      assert result.name == "Test Team"
    end

    test "fetches from API on cache miss" do
      MockAdapter.expect("teams/1", {:ok, %{
        "team" => %{
          "id" => "1",
          "name" => "Test Team",
          "displayName" => "Test Team",
          "abbreviation" => "TST",
          "color" => "000000",
          "alternateColor" => "ffffff",
          "logos" => [%{"href" => "logo.png"}],
          "athletes" => []
        }
      }})

      assert {:ok, team} = NHL.get_team_details("1")
      assert team.name == "Test Team"

      # Verify cached
      assert {:ok, _cached} = NHL.get_team_details("1")
    end
  end

  describe "list_standings/0" do
    test "returns empty list when cache is empty" do
      assert NHL.list_standings() == []
    end

    test "returns cached standings" do
      standings = [%{team: %{id: "1"}, wins: 10}]
      Cache.put(:nhl_standings, :current, standings)

      assert NHL.list_standings() == standings
    end
  end

  describe "search_players/1" do
    test "returns empty list for short queries" do
      assert {:ok, []} = NHL.search_players("a")
    end

    test "includes easter egg players in results" do
      MockAdapter.expect("search", {:ok, %{"items" => []}})

      assert {:ok, results} = NHL.search_players("Rylan Yogan")
      assert length(results) >= 1
      assert Enum.any?(results, fn p -> p.name == "Rylan Yogan" end)
    end

    test "returns API results combined with easter eggs" do
      MockAdapter.expect("search", {:ok, %{
        "items" => [
          %{
            "id" => "123",
            "type" => "player",
            "displayName" => "Connor McDavid",
            "position" => "C",
            "team" => "Edmonton Oilers"
          }
        ]
      }})

      assert {:ok, results} = NHL.search_players("player")
      assert length(results) >= 1
    end

    test "handles API errors and still returns easter egg matches" do
      MockAdapter.expect("search", {:error, :timeout})

      # Search for Rylan - should still get easter egg result
      assert {:ok, results} = NHL.search_players("Rylan")
      assert length(results) == 1
      assert hd(results).name == "Rylan Yogan"
    end
  end

  describe "get_player/1" do
    test "returns easter egg player without API call" do
      # No mock expectation set - if API is called, it would fail

      assert {:ok, player} = NHL.get_player("easter-egg-rylan-yogan")
      assert player.name == "Rylan Yogan"
    end

    test "returns cached player" do
      player = %{id: "123", name: "Test Player", career_seasons: [], birth_date: "1990-01-01"}
      Cache.put(:player_cache, {:player, "123"}, player)

      assert {:ok, cached} = NHL.get_player("123")
      assert cached.name == "Test Player"
    end
  end

  describe "get_players/1" do
    test "returns list of players for valid IDs" do
      player = %{id: "123", name: "Test Player", career_seasons: [], birth_date: "1990-01-01"}
      Cache.put(:player_cache, {:player, "123"}, player)

      results = NHL.get_players(["123", "easter-egg-rylan-yogan"])
      assert length(results) == 2
    end

    test "filters out failed lookups" do
      # Only easter egg exists, API call would fail
      MockAdapter.expect("athletes", {:error, :not_found})

      results = NHL.get_players(["nonexistent", "easter-egg-rylan-yogan"])
      assert length(results) == 1
      assert hd(results).name == "Rylan Yogan"
    end
  end

  describe "live_scores_updated_at/0" do
    test "returns nil when no scores cached" do
      assert NHL.live_scores_updated_at() == nil
    end

    test "returns timestamp when scores are cached" do
      now = DateTime.utc_now()
      Cache.put(:nhl_live_scores, :last_updated, now)

      assert NHL.live_scores_updated_at() == now
    end
  end
end
