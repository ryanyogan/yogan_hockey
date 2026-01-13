defmodule YoganHockey.GamesDistributedTest do
  @moduledoc """
  Tests for the Games context distribution-aware functions.

  These tests verify:
  - Distribution routing logic (primary detection)
  - RPC forwarding behavior when on replica
  - Data conversion helpers work correctly

  Note: Tests that require actual DB operations are tagged with @tag :requires_repo
  and skipped when Repo is not available (e.g., in lightweight test runs).
  """
  use ExUnit.Case, async: false

  alias YoganHockey.Games
  alias YoganHockey.Cluster.Primary

  setup do
    # Store original env vars
    original_fly_region = System.get_env("FLY_REGION")
    original_primary_region = System.get_env("PRIMARY_REGION")

    on_exit(fn ->
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

  describe "distribution routing" do
    test "Primary.primary?() returns true in local dev (no FLY_REGION)" do
      System.delete_env("FLY_REGION")
      System.delete_env("PRIMARY_REGION")

      assert Primary.primary?() == true
    end

    test "Primary.primary?() returns false when FLY_REGION != PRIMARY_REGION" do
      System.put_env("FLY_REGION", "ewr")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == false
    end

    test "save_completed_game returns error when on replica with no primary" do
      System.put_env("FLY_REGION", "ewr")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == false

      game_data = %{
        game_id: "test_game_replica",
        home_team: %{id: "1", name: "Test", abbreviation: "TST", score: 1},
        away_team: %{id: "2", name: "Test2", abbreviation: "TS2", score: 0},
        status: %{state: "post"},
        plays: [],
        boxscore: %{},
        last_updated: DateTime.utc_now()
      }

      result = Games.save_completed_game(game_data)

      assert result == {:error, :no_primary_available}
    end

    test "get_completed_game returns error when on replica with no primary" do
      System.put_env("FLY_REGION", "lhr")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == false

      result = Games.get_completed_game("some_game")

      assert result == {:error, :no_primary_available}
    end

    test "game_ids_for_team returns error when on replica with no primary" do
      System.put_env("FLY_REGION", "sjc")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == false

      result = Games.game_ids_for_team("team123")

      assert result == {:error, :no_primary_available}
    end

    test "count_completed_games returns error when on replica with no primary" do
      System.put_env("FLY_REGION", "nrt")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == false

      result = Games.count_completed_games()

      assert result == {:error, :no_primary_available}
    end
  end

  describe "map_to_game_data/1" do
    test "correctly reconstructs game data from stored map" do
      stored_map = %{
        "game_id" => "12345",
        "status" => %{
          "state" => "post",
          "period" => 3,
          "clock" => "0:00",
          "intermission" => false,
          "detail" => "Final"
        },
        "home_team" => %{
          "id" => "1",
          "name" => "Toronto Maple Leafs",
          "abbreviation" => "TOR",
          "score" => 4,
          "shots" => 32
        },
        "away_team" => %{
          "id" => "2",
          "name" => "Montreal Canadiens",
          "abbreviation" => "MTL",
          "score" => 2,
          "shots" => 28
        },
        "plays" => [
          %{
            "id" => "1",
            "type" => "goal",
            "period" => 1,
            "time" => "5:30",
            "team_id" => "1",
            "description" => "Goal scored"
          }
        ],
        "boxscore" => %{
          "period_scores" => [
            %{"period" => 1, "home" => 2, "away" => 1}
          ]
        },
        "last_updated" => "2026-01-13T12:00:00Z"
      }

      result = Games.map_to_game_data(stored_map)

      assert result.game_id == "12345"
      assert result.status.state == "post"
      assert result.status.period == 3
      assert result.home_team.id == "1"
      assert result.home_team.name == "Toronto Maple Leafs"
      assert result.home_team.score == 4
      assert result.away_team.id == "2"
      assert result.away_team.abbreviation == "MTL"
      assert length(result.plays) == 1
      assert hd(result.plays).type == :goal
      assert length(result.boxscore.period_scores) == 1
    end

    test "returns nil for invalid map" do
      assert Games.map_to_game_data(nil) == nil
      assert Games.map_to_game_data(%{"invalid" => "data"}) == nil
    end
  end
end
