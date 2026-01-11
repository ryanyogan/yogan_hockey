defmodule YoganHockeyWeb.Helpers.StatsHelpersTest do
  use ExUnit.Case, async: true

  alias YoganHockeyWeb.Helpers.StatsHelpers

  describe "format_plus_minus/1" do
    test "formats positive values with plus sign" do
      assert StatsHelpers.format_plus_minus(5) == "+5"
      assert StatsHelpers.format_plus_minus(1) == "+1"
      assert StatsHelpers.format_plus_minus(100) == "+100"
    end

    test "formats negative values with minus sign" do
      assert StatsHelpers.format_plus_minus(-3) == "-3"
      assert StatsHelpers.format_plus_minus(-1) == "-1"
      assert StatsHelpers.format_plus_minus(-50) == "-50"
    end

    test "formats zero as plain zero" do
      assert StatsHelpers.format_plus_minus(0) == "0"
    end

    test "handles nil as zero" do
      assert StatsHelpers.format_plus_minus(nil) == "0"
    end
  end

  describe "plus_minus_class/1" do
    test "returns success class for positive values" do
      assert StatsHelpers.plus_minus_class(5) == "text-success"
      assert StatsHelpers.plus_minus_class(1) == "text-success"
    end

    test "returns error class for negative values" do
      assert StatsHelpers.plus_minus_class(-3) == "text-error"
      assert StatsHelpers.plus_minus_class(-1) == "text-error"
    end

    test "returns empty string for zero" do
      assert StatsHelpers.plus_minus_class(0) == ""
    end

    test "returns empty string for nil" do
      assert StatsHelpers.plus_minus_class(nil) == ""
    end
  end

  describe "career_total/2" do
    test "sums a stat across all seasons" do
      stats = [%{goals: 10}, %{goals: 15}, %{goals: 5}]
      assert StatsHelpers.career_total(stats, :goals) == 30
    end

    test "handles nil values in seasons" do
      stats = [%{goals: 10}, %{goals: nil}, %{goals: 5}]
      assert StatsHelpers.career_total(stats, :goals) == 15
    end

    test "handles missing keys" do
      stats = [%{goals: 10}, %{}, %{goals: 5}]
      assert StatsHelpers.career_total(stats, :goals) == 15
    end

    test "returns 0 for empty list" do
      assert StatsHelpers.career_total([], :goals) == 0
    end

    test "returns 0 for non-list input" do
      assert StatsHelpers.career_total(nil, :goals) == 0
    end
  end

  describe "points_per_game/1" do
    test "calculates points per game" do
      stats = [%{games_played: 80, points: 100}]
      assert StatsHelpers.points_per_game(stats) == 1.25
    end

    test "handles multiple seasons" do
      stats = [%{games_played: 40, points: 20}, %{games_played: 40, points: 30}]
      # 50 points / 80 games = 0.625
      assert StatsHelpers.points_per_game(stats) == 0.62 || StatsHelpers.points_per_game(stats) == 0.63
    end

    test "returns 0.0 for zero games" do
      stats = [%{games_played: 0, points: 0}]
      assert StatsHelpers.points_per_game(stats) == 0.0
    end

    test "returns 0.0 for empty list" do
      assert StatsHelpers.points_per_game([]) == 0.0
    end
  end

  describe "format_date/1" do
    test "formats ISO8601 date to human readable" do
      assert StatsHelpers.format_date("2024-01-15") == "January 15, 2024"
      assert StatsHelpers.format_date("2023-12-25") == "December 25, 2023"
    end

    test "returns nil for nil input" do
      assert StatsHelpers.format_date(nil) == nil
    end

    test "returns original string for invalid date" do
      assert StatsHelpers.format_date("not-a-date") == "not-a-date"
    end

    test "passes through non-string values" do
      assert StatsHelpers.format_date(123) == 123
    end
  end

  describe "format_datetime/1" do
    test "formats DateTime to human readable" do
      {:ok, dt, _} = DateTime.from_iso8601("2024-01-15T14:30:00Z")
      assert StatsHelpers.format_datetime(dt) == "January 15, 2024 at 14:30 UTC"
    end

    test "returns nil for nil input" do
      assert StatsHelpers.format_datetime(nil) == nil
    end

    test "returns nil for non-DateTime input" do
      assert StatsHelpers.format_datetime("not a datetime") == nil
    end
  end

  describe "get_stat/2" do
    test "extracts stat from map" do
      stats = %{"wins" => 45, "losses" => 20}
      assert StatsHelpers.get_stat(stats, "wins") == 45
    end

    test "rounds float values" do
      stats = %{"pct" => 0.567}
      assert StatsHelpers.get_stat(stats, "pct") == 1
    end

    test "returns dash for nil stats" do
      assert StatsHelpers.get_stat(nil, "wins") == "-"
    end

    test "returns dash for missing key" do
      stats = %{"wins" => 45}
      assert StatsHelpers.get_stat(stats, "losses") == "-"
    end
  end

  describe "get_team_name/1" do
    test "extracts name from map with name key" do
      assert StatsHelpers.get_team_name(%{name: "Edmonton Oilers"}) == "Edmonton Oilers"
    end

    test "falls back to abbreviation if no name" do
      assert StatsHelpers.get_team_name(%{abbreviation: "EDM"}) == "EDM"
    end

    test "returns string as-is" do
      assert StatsHelpers.get_team_name("Some Team") == "Some Team"
    end

    test "returns NHL for nil or unknown" do
      assert StatsHelpers.get_team_name(nil) == "NHL"
      assert StatsHelpers.get_team_name(%{}) == "NHL"
    end
  end

  describe "format_diff/1" do
    test "formats positive numbers with plus sign" do
      assert StatsHelpers.format_diff(15) == "+15"
      assert StatsHelpers.format_diff(15.7) == "+16"
    end

    test "formats negative numbers with minus sign" do
      assert StatsHelpers.format_diff(-5) == "-5"
      assert StatsHelpers.format_diff(-5.3) == "-5"
    end

    test "formats zero" do
      assert StatsHelpers.format_diff(0) == "0"
    end

    test "returns dash for nil" do
      assert StatsHelpers.format_diff(nil) == "-"
    end
  end

  describe "period_display/1" do
    test "displays regulation periods" do
      assert StatsHelpers.period_display(1) == "1st"
      assert StatsHelpers.period_display(2) == "2nd"
      assert StatsHelpers.period_display(3) == "3rd"
    end

    test "displays overtime" do
      assert StatsHelpers.period_display(4) == "OT"
    end

    test "displays shootout" do
      assert StatsHelpers.period_display(5) == "SO"
    end

    test "displays multiple overtimes" do
      assert StatsHelpers.period_display(6) == "3OT"
      assert StatsHelpers.period_display(7) == "4OT"
    end

    test "returns empty string for nil" do
      assert StatsHelpers.period_display(nil) == ""
    end
  end
end
