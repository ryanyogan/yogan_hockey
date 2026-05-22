defmodule YoganHockey.OpenAITest do
  use ExUnit.Case, async: false

  alias YoganHockey.OpenAI
  alias YoganHockey.HTTP.MockOpenAIAdapter

  setup do
    {:ok, _} = MockOpenAIAdapter.start_link()
    Application.put_env(:yogan_hockey, :openai_adapter, MockOpenAIAdapter)

    on_exit(fn ->
      MockOpenAIAdapter.stop()
      Application.delete_env(:yogan_hockey, :openai_adapter)
    end)

    :ok
  end

  describe "predict_live_game_winner/2" do
    test "returns prediction for a live game" do
      MockOpenAIAdapter.expect(
        {:ok, ~s|{"winner": "TOR", "win_probability": 65, "loser": "MTL", "lose_probability": 35}|}
      )

      game = %{
        id: "game123",
        status: %{period: 2, display_clock: "10:00"},
        away_team: %{
          abbreviation: "TOR",
          score: 3,
          logo: "tor.png",
          records: %{"total" => "30-20-5"}
        },
        home_team: %{
          abbreviation: "MTL",
          score: 2,
          logo: "mtl.png",
          records: %{"total" => "25-25-5"}
        }
      }

      assert {:ok, prediction} = OpenAI.predict_live_game_winner(game)
      assert prediction.game_id == "game123"
      assert prediction.predicted_winner == "TOR"
      assert prediction.winner_probability == 0.65
      assert prediction.predicted_loser == "MTL"
      assert prediction.loser_probability == 0.35
    end

    test "returns fallback prediction on parse error" do
      MockOpenAIAdapter.expect({:ok, "invalid json response"})

      game = %{
        id: "game456",
        status: %{period: 1, display_clock: "15:00"},
        away_team: %{
          abbreviation: "BOS",
          score: 0,
          logo: "bos.png",
          records: %{"total" => "35-15-5"}
        },
        home_team: %{
          abbreviation: "NYR",
          score: 1,
          logo: "nyr.png",
          records: %{"total" => "32-18-5"}
        }
      }

      assert {:ok, prediction} = OpenAI.predict_live_game_winner(game)
      assert prediction.game_id == "game456"
      assert prediction.model == "fallback"
      # Fallback favors team with more goals
      assert prediction.predicted_winner == "NYR"
    end

    test "returns error when API fails" do
      MockOpenAIAdapter.expect({:error, :api_error})

      game = %{
        id: "game789",
        status: %{period: 3, display_clock: "5:00"},
        away_team: %{abbreviation: "CHI", score: 2, logo: nil, records: %{"total" => "20-30-5"}},
        home_team: %{abbreviation: "DET", score: 2, logo: nil, records: %{"total" => "22-28-5"}}
      }

      assert {:error, :api_error} = OpenAI.predict_live_game_winner(game)
    end
  end

  describe "predict_series_outcome/3" do
    test "returns series prediction" do
      MockOpenAIAdapter.expect(
        {:ok, ~s|{
          "home_win_probability": 55,
          "away_win_probability": 45,
          "predicted_winner": "Florida Panthers",
          "predicted_games": 6,
          "reasoning": "Home team has better goaltending"
        }|}
      )

      home_team = %{
        id: "1",
        name: "Florida Panthers",
        stats: %{wins: 50, losses: 20, ot_losses: 5, points: 105}
      }

      away_team = %{
        id: "2",
        name: "Boston Bruins",
        stats: %{wins: 48, losses: 22, ot_losses: 5, points: 101}
      }

      assert {:ok, prediction} = OpenAI.predict_series_outcome(home_team, away_team)
      assert prediction.home_win_prob == 0.55
      assert prediction.away_win_prob == 0.45
      assert prediction.predicted_winner == "Florida Panthers"
      assert prediction.predicted_games == 6
    end

    test "returns fallback prediction on parse error" do
      MockOpenAIAdapter.expect({:ok, "not valid json"})

      home_team = %{id: "1", name: "Team A"}
      away_team = %{id: "2", name: "Team B"}

      assert {:ok, prediction} = OpenAI.predict_series_outcome(home_team, away_team)
      assert prediction.model == "fallback"
      assert prediction.home_win_prob == 0.5
      assert prediction.away_win_prob == 0.5
    end
  end

  describe "predict_playoff_picture/2" do
    test "returns playoff picture prediction" do
      MockOpenAIAdapter.expect({:ok, ~s|{
        "eastern": [
          {"team_id": "1", "team_name": "Florida Panthers", "seed": 1, "playoff_prob": 99, "round2_prob": 75, "conf_final_prob": 50, "cup_final_prob": 30, "cup_win_prob": 15}
        ],
        "western": [
          {"team_id": "2", "team_name": "Dallas Stars", "seed": 1, "playoff_prob": 98, "round2_prob": 70, "conf_final_prob": 45, "cup_final_prob": 25, "cup_win_prob": 12}
        ],
        "cup_favorite": "Florida Panthers",
        "analysis": "Panthers have the best record"
      }|})

      standings = [
        %{
          conference: "Eastern",
          team: %{id: "1", display_name: "Florida Panthers"},
          stats: [%{"name" => "points", "value" => 110}]
        },
        %{
          conference: "Western",
          team: %{id: "2", display_name: "Dallas Stars"},
          stats: [%{"name" => "points", "value" => 105}]
        }
      ]

      assert {:ok, prediction} = OpenAI.predict_playoff_picture(standings)
      assert prediction.cup_favorite == "Florida Panthers"
      assert length(prediction.eastern) == 1
      assert length(prediction.western) == 1

      [eastern_team] = prediction.eastern
      assert eastern_team.team_name == "Florida Panthers"
      assert eastern_team.playoff_prob == 0.99
    end

    test "returns error on API failure" do
      MockOpenAIAdapter.expect({:error, :network_error})

      standings = [%{conference: "Eastern", team: %{id: "1"}, stats: []}]

      assert {:error, :network_error} = OpenAI.predict_playoff_picture(standings)
    end
  end
end
