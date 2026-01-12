defmodule YoganHockey.EasterEggsTest do
  use ExUnit.Case, async: true

  alias YoganHockey.EasterEggs

  describe "rylan_yogan_id/0" do
    test "returns the easter egg player ID" do
      assert EasterEggs.rylan_yogan_id() == "easter-egg-rylan-yogan"
    end
  end

  describe "maple_leafs_id/0" do
    test "returns the Maple Leafs team ID" do
      assert EasterEggs.maple_leafs_id() == "21"
    end
  end

  describe "all_players/0" do
    test "returns list of all easter egg players" do
      players = EasterEggs.all_players()
      assert is_list(players)
      assert length(players) == 1

      [player] = players
      assert player.name == "Rylan Yogan"
    end
  end

  describe "get_player/1" do
    test "returns easter egg player when ID matches" do
      {:ok, player} = EasterEggs.get_player("easter-egg-rylan-yogan")
      assert player.name == "Rylan Yogan"
      assert player.position == "C"
      assert player.jersey == "99"
    end

    test "returns nil for non-easter-egg ID" do
      assert EasterEggs.get_player("12345") == nil
      assert EasterEggs.get_player("random-id") == nil
    end
  end

  describe "is_easter_egg?/1" do
    test "returns true for easter egg player ID" do
      assert EasterEggs.is_easter_egg?("easter-egg-rylan-yogan") == true
    end

    test "returns false for regular player ID" do
      assert EasterEggs.is_easter_egg?("12345") == false
      assert EasterEggs.is_easter_egg?("connor-mcdavid") == false
    end
  end

  describe "search_players/1" do
    test "finds player by first name" do
      results = EasterEggs.search_players("Rylan")
      assert length(results) == 1
      assert hd(results).name == "Rylan Yogan"
    end

    test "finds player by last name" do
      results = EasterEggs.search_players("Yogan")
      assert length(results) == 1
      assert hd(results).name == "Rylan Yogan"
    end

    test "finds player by full name" do
      results = EasterEggs.search_players("Rylan Yogan")
      assert length(results) == 1
    end

    test "search is case insensitive" do
      results_lower = EasterEggs.search_players("rylan")
      results_upper = EasterEggs.search_players("RYLAN")
      results_mixed = EasterEggs.search_players("RyLaN")

      assert length(results_lower) == 1
      assert length(results_upper) == 1
      assert length(results_mixed) == 1
    end

    test "returns empty list for non-matching query" do
      assert EasterEggs.search_players("McDavid") == []
      assert EasterEggs.search_players("xyz123") == []
    end

    test "partial name match works" do
      results = EasterEggs.search_players("yla")
      assert length(results) == 1
    end
  end

  describe "players_for_team/1" do
    test "returns Rylan for Maple Leafs team ID" do
      players = EasterEggs.players_for_team("21")
      assert length(players) == 1

      [player] = players
      assert player.name == "Rylan Yogan"
      assert player.jersey == "99"
      assert player.position == "C"
    end

    test "returns empty list for other teams" do
      assert EasterEggs.players_for_team("1") == []
      assert EasterEggs.players_for_team("22") == []
      assert EasterEggs.players_for_team("random") == []
    end
  end

  describe "rylan_yogan/0" do
    test "returns complete player data" do
      player = EasterEggs.rylan_yogan()

      assert player.id == "easter-egg-rylan-yogan"
      assert player.name == "Rylan Yogan"
      assert player.first_name == "Rylan"
      assert player.last_name == "Yogan"
      assert player.position == "C"
      assert player.jersey == "99"
      assert player.height == "6'2\""
      assert player.shoots == "Right"
    end

    test "includes current season stats" do
      player = EasterEggs.rylan_yogan()
      stats = player.current_season_stats

      assert stats.season == "2025-26"
      assert stats.league == "NHL"
      assert is_integer(stats.goals)
      assert is_integer(stats.assists)
      assert is_integer(stats.points)
    end

    test "includes career seasons" do
      player = EasterEggs.rylan_yogan()
      seasons = player.career_seasons

      assert is_list(seasons)
      assert length(seasons) > 0

      # First season should be most recent
      first = hd(seasons)
      assert first.season == "2025-26"
      assert first.league == "NHL"
    end

    test "includes team information" do
      player = EasterEggs.rylan_yogan()
      team = player.team

      assert team.id == "21"
      assert team.name == "Maple Leafs"
      assert team.display_name == "Toronto Maple Leafs"
      assert team.abbreviation == "TOR"
    end

    test "includes career totals" do
      player = EasterEggs.rylan_yogan()
      totals = player.career_totals

      assert is_integer(totals.games_played)
      assert is_integer(totals.goals)
      assert is_integer(totals.assists)
      assert is_integer(totals.points)
    end
  end
end
