defmodule YoganHockey.NHL.ParsersTest do
  use ExUnit.Case, async: true

  alias YoganHockey.NHL.Parsers

  describe "parse_scoreboard/1" do
    test "parses events into game maps" do
      data = %{
        "events" => [
          %{
            "id" => "123",
            "name" => "Test Game",
            "shortName" => "TEST @ TEST",
            "date" => "2024-01-15T19:00:00Z",
            "competitions" => [
              %{
                "competitors" => [
                  %{
                    "homeAway" => "home",
                    "team" => %{
                      "id" => "1",
                      "name" => "Home Team",
                      "abbreviation" => "HOM"
                    },
                    "score" => "3"
                  },
                  %{
                    "homeAway" => "away",
                    "team" => %{
                      "id" => "2",
                      "name" => "Away Team",
                      "abbreviation" => "AWY"
                    },
                    "score" => "2"
                  }
                ],
                "status" => %{
                  "type" => %{
                    "state" => "post",
                    "completed" => true,
                    "shortDetail" => "Final"
                  }
                }
              }
            ]
          }
        ]
      }

      [game] = Parsers.parse_scoreboard(data)

      assert game.id == "123"
      assert game.name == "Test Game"
      assert game.home_team.name == "Home Team"
      assert game.away_team.name == "Away Team"
      assert game.status.completed == true
    end

    test "returns empty list for missing events" do
      assert Parsers.parse_scoreboard(%{}) == []
      assert Parsers.parse_scoreboard(nil) == []
    end
  end

  describe "parse_teams/1" do
    test "parses teams from ESPN response" do
      data = %{
        "sports" => [
          %{
            "leagues" => [
              %{
                "teams" => [
                  %{
                    "team" => %{
                      "id" => "1",
                      "name" => "Oilers",
                      "abbreviation" => "EDM",
                      "displayName" => "Edmonton Oilers",
                      "location" => "Edmonton",
                      "logos" => [%{"href" => "http://example.com/logo.png"}],
                      "color" => "FF4C00"
                    }
                  }
                ]
              }
            ]
          }
        ]
      }

      [team] = Parsers.parse_teams(data)

      assert team.id == "1"
      assert team.name == "Oilers"
      assert team.abbreviation == "EDM"
      assert team.display_name == "Edmonton Oilers"
      assert team.logo == "http://example.com/logo.png"
    end

    test "returns empty list for invalid data" do
      assert Parsers.parse_teams(%{}) == []
      assert Parsers.parse_teams(nil) == []
    end
  end

  describe "parse_standings/1" do
    test "parses standings with divisions (old format)" do
      data = %{
        "children" => [
          %{
            "name" => "Eastern Conference",
            "children" => [
              %{
                "name" => "Atlantic Division",
                "standings" => %{
                  "entries" => [
                    %{
                      "team" => %{
                        "id" => "1",
                        "name" => "Bruins",
                        "abbreviation" => "BOS",
                        "displayName" => "Boston Bruins",
                        "logos" => [%{"href" => "http://example.com/logo.png"}]
                      },
                      "stats" => [
                        %{"name" => "wins", "value" => 30},
                        %{"name" => "losses", "value" => 10},
                        %{"name" => "points", "value" => 65}
                      ]
                    }
                  ]
                }
              }
            ]
          }
        ]
      }

      [entry] = Parsers.parse_standings(data)

      assert entry.conference == "Eastern Conference"
      assert entry.division == "Atlantic Division"
      assert entry.team.name == "Bruins"
      assert entry.stats["wins"] == 30
      assert entry.stats["points"] == 65
    end

    test "returns empty list for invalid data" do
      assert Parsers.parse_standings(%{}) == []
      assert Parsers.parse_standings(nil) == []
    end
  end

  describe "parse_player/1" do
    test "parses player data from API response" do
      data = %{
        "athlete" => %{
          "id" => "12345",
          "displayName" => "Connor McDavid",
          "firstName" => "Connor",
          "lastName" => "McDavid",
          "jersey" => "97",
          "position" => %{"abbreviation" => "C", "name" => "Center"},
          "team" => %{
            "id" => "1",
            "displayName" => "Edmonton Oilers",
            "abbreviation" => "EDM"
          },
          "dateOfBirth" => "1997-01-13",
          "hand" => %{"displayValue" => "Left"}
        }
      }

      player = Parsers.parse_player(data)

      assert player.id == "12345"
      assert player.name == "Connor McDavid"
      assert player.jersey == "97"
      assert player.position == "C"
      assert player.team.name == "Edmonton Oilers"
      assert player.birth_date == "1997-01-13"
      assert player.shoots == "Left"
    end

    test "returns nil for invalid data" do
      assert Parsers.parse_player(%{}) == nil
      assert Parsers.parse_player(nil) == nil
    end
  end

  describe "parse_search_results/1" do
    test "parses player search results" do
      data = %{
        "items" => [
          %{
            "id" => "123",
            "type" => "player",
            "displayName" => "Test Player",
            "position" => "C",
            "team" => "Edmonton Oilers",
            "headshot" => %{"href" => "http://example.com/headshot.png"}
          },
          %{
            "id" => "456",
            "type" => "team",
            "displayName" => "Edmonton Oilers"
          }
        ]
      }

      results = Parsers.parse_search_results(data)

      # Should filter out non-player results
      assert length(results) == 1
      [player] = results
      assert player.id == "123"
      assert player.name == "Test Player"
      assert player.position == "C"
    end

    test "returns empty list for no items" do
      assert Parsers.parse_search_results(%{}) == []
      assert Parsers.parse_search_results(%{"items" => []}) == []
    end
  end

  describe "parse_career_seasons/1" do
    test "parses career statistics" do
      data = %{
        "categories" => [
          %{
            "names" => ["games", "goals", "assists", "points"],
            "statistics" => [
              %{
                "season" => %{
                  "displayName" => "2023-24",
                  "year" => 2024
                },
                "stats" => [82, 50, 70, 120],
                "teamSlug" => "edmonton-oilers"
              }
            ]
          }
        ]
      }

      [season] = Parsers.parse_career_seasons(data)

      assert season.season == "2023-24"
      assert season.year == 2024
      assert season.games_played == 82
      assert season.goals == 50
      assert season.assists == 70
      assert season.points == 120
      assert season.team == "Edmonton Oilers"
    end

    test "returns empty list for invalid data" do
      assert Parsers.parse_career_seasons(%{}) == []
      assert Parsers.parse_career_seasons(nil) == []
    end
  end

  describe "parse_team_schedule/1" do
    test "parses team schedule into past and upcoming games" do
      future_date =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_iso8601()

      past_date =
        DateTime.utc_now()
        |> DateTime.add(-7, :day)
        |> DateTime.to_iso8601()

      data = %{
        "team" => %{
          "id" => "1",
          "displayName" => "Edmonton Oilers"
        },
        "events" => [
          %{
            "id" => "1",
            "date" => future_date,
            "competitions" => [
              %{
                "competitors" => [
                  %{"id" => "1", "homeAway" => "home"},
                  %{"id" => "2", "homeAway" => "away", "team" => %{"displayName" => "Opponent"}}
                ],
                "status" => %{"type" => %{}}
              }
            ]
          },
          %{
            "id" => "2",
            "date" => past_date,
            "competitions" => [
              %{
                "competitors" => [
                  %{"id" => "1", "homeAway" => "home", "score" => %{"value" => 3}},
                  %{
                    "id" => "2",
                    "homeAway" => "away",
                    "score" => %{"value" => 2},
                    "team" => %{"displayName" => "Opponent"}
                  }
                ],
                "status" => %{"type" => %{"completed" => true}}
              }
            ]
          }
        ]
      }

      schedule = Parsers.parse_team_schedule(data)

      assert schedule.team_id == "1"
      assert schedule.team_name == "Edmonton Oilers"
      assert length(schedule.upcoming_games) == 1
      assert length(schedule.past_games) == 1
    end

    test "returns default schedule for invalid data" do
      schedule = Parsers.parse_team_schedule(%{})

      assert schedule.past_games == []
      assert schedule.upcoming_games == []
    end
  end
end
