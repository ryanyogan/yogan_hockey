defmodule YoganHockey.Anthropic do
  @moduledoc """
  Client for Anthropic Claude API.

  Provides high-level functions for AI-powered hockey predictions.
  """

  require Logger

  @system_prompt """
  You are an expert hockey analyst with deep knowledge of NHL team statistics, \
  player performance, and playoff dynamics. When analyzing matchups, consider:
  - Regular season record and recent form
  - Goals for/against and goal differential
  - Power play and penalty kill percentages
  - Head-to-head history
  - Home/away performance
  - Key player injuries or absences
  - Goaltending strength

  Provide predictions as JSON with win probabilities that sum to 100%.
  Be concise but insightful in your reasoning.
  """

  @doc """
  Predicts playoff qualification and full bracket outcomes for all teams.

  Takes standings data and returns predictions for:
  - Which teams make playoffs (with probability)
  - Predicted seeding
  - Round-by-round advancement probabilities
  - Championship probability
  """
  @spec predict_playoff_picture(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def predict_playoff_picture(standings, opts \\ []) do
    prompt = build_playoff_picture_prompt(standings)

    messages = [
      %{role: "user", content: prompt}
    ]

    system = """
    You are an expert NHL analyst specializing in playoff predictions. Analyze team statistics \
    and predict playoff outcomes. Consider current standings, goal differential, recent form, \
    and historical playoff performance. Be analytical and provide probability-based predictions.
    """

    case adapter().chat_completion(messages, Keyword.merge([system: system, max_tokens: 4096], opts)) do
      {:ok, response} ->
        parse_playoff_picture_response(response)

      {:error, reason} ->
        Logger.error("Failed to get playoff picture prediction: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_playoff_picture_prompt(standings) do
    eastern = format_conference_standings(standings, "Eastern")
    western = format_conference_standings(standings, "Western")

    """
    Analyze the current NHL standings and predict the complete playoff picture.

    EASTERN CONFERENCE:
    #{eastern}

    WESTERN CONFERENCE:
    #{western}

    Based on current standings, points pace, and remaining schedule, predict:
    1. Which 16 teams make playoffs (8 per conference)
    2. Their predicted seeding (1-8 per conference)
    3. Each team's probability to advance through each round

    Respond with ONLY a JSON object in this exact format (no markdown):
    {
      "eastern": [
        {"team_id": "id", "team_name": "name", "seed": 1, "playoff_prob": 99, "round2_prob": 70, "conf_final_prob": 45, "cup_final_prob": 25, "cup_win_prob": 12},
        ... (8 teams)
      ],
      "western": [
        {"team_id": "id", "team_name": "name", "seed": 1, "playoff_prob": 99, "round2_prob": 70, "conf_final_prob": 45, "cup_final_prob": 25, "cup_win_prob": 12},
        ... (8 teams)
      ],
      "cup_favorite": "team name",
      "analysis": "2-3 sentence overall analysis"
    }
    """
  end

  defp format_conference_standings(standings, conference) do
    standings
    |> Enum.filter(fn s ->
      conf = s[:conference] || s["conference"] || ""
      String.contains?(String.downcase(conf), String.downcase(conference))
    end)
    |> Enum.sort_by(fn s ->
      stats = s[:stats] || s["stats"] || %{}
      -(get_stat(stats, "points") || 0)
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {s, rank} ->
      team = s[:team] || s["team"] || %{}
      stats = s[:stats] || s["stats"] || %{}
      name = team[:display_name] || team["displayName"] || team[:name] || team["name"] || "Unknown"
      team_id = team[:id] || team["id"] || ""
      wins = get_stat(stats, "wins") || 0
      losses = get_stat(stats, "losses") || 0
      ot = get_stat(stats, "otLosses") || 0
      pts = get_stat(stats, "points") || 0
      gf = get_stat(stats, "pointsFor") || 0
      ga = get_stat(stats, "pointsAgainst") || 0
      diff = get_stat(stats, "differential") || (gf - ga)

      "#{rank}. #{name} (ID:#{team_id}) - #{wins}-#{losses}-#{ot}, #{pts}pts, GF:#{gf}, GA:#{ga}, Diff:#{diff}"
    end)
    |> Enum.join("\n")
  end

  defp get_stat(stats, name) when is_list(stats) do
    case Enum.find(stats, &(&1["name"] == name || &1[:name] == name)) do
      nil -> nil
      stat -> stat["value"] || stat[:value]
    end
  end

  defp get_stat(stats, name) when is_map(stats) do
    stats[name] || stats[String.to_atom(name)]
  end

  defp get_stat(_, _), do: nil

  defp parse_playoff_picture_response(response) do
    json_str = extract_large_json(response)

    case Jason.decode(json_str) do
      {:ok, data} ->
        prediction = %{
          eastern: parse_conference_predictions(data["eastern"] || []),
          western: parse_conference_predictions(data["western"] || []),
          cup_favorite: data["cup_favorite"],
          analysis: data["analysis"],
          generated_at: DateTime.utc_now(),
          model: "claude-sonnet-4-20250514"
        }
        {:ok, prediction}

      {:error, _} ->
        Logger.warning("Failed to parse playoff picture JSON: #{String.slice(response, 0, 500)}")
        {:error, :parse_error}
    end
  end

  defp parse_conference_predictions(teams) do
    Enum.map(teams, fn team ->
      %{
        team_id: to_string(team["team_id"] || ""),
        team_name: team["team_name"] || "",
        seed: team["seed"] || 0,
        playoff_prob: (team["playoff_prob"] || 0) / 100,
        round2_prob: (team["round2_prob"] || 0) / 100,
        conf_final_prob: (team["conf_final_prob"] || 0) / 100,
        cup_final_prob: (team["cup_final_prob"] || 0) / 100,
        cup_win_prob: (team["cup_win_prob"] || 0) / 100
      }
    end)
  end

  defp extract_large_json(str) do
    # Find JSON object that may contain nested objects/arrays
    case Regex.run(~r/\{[\s\S]*\}/m, str, capture: :first) do
      [json] -> json
      nil -> str
    end
  end

  @doc """
  Predicts the outcome of a playoff series between two teams.

  Returns a prediction map with win probabilities and reasoning.
  """
  @spec predict_series_outcome(map(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def predict_series_outcome(home_team, away_team, opts \\ []) do
    prompt = build_prediction_prompt(home_team, away_team)

    messages = [
      %{role: "user", content: prompt}
    ]

    case adapter().chat_completion(messages, Keyword.merge([system: @system_prompt], opts)) do
      {:ok, response} ->
        parse_prediction_response(response, home_team, away_team)

      {:error, reason} ->
        Logger.error("Failed to get prediction: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_prediction_prompt(home_team, away_team) do
    """
    Analyze this NHL playoff matchup and predict the series outcome.

    HOME TEAM: #{home_team.name}
    #{format_team_stats(home_team)}

    AWAY TEAM: #{away_team.name}
    #{format_team_stats(away_team)}

    Respond with ONLY a JSON object in this exact format (no markdown, no explanation outside JSON):
    {
      "home_win_probability": <number 0-100>,
      "away_win_probability": <number 0-100>,
      "predicted_winner": "<team name>",
      "predicted_games": <4-7>,
      "reasoning": "<2-3 sentence analysis>"
    }
    """
  end

  defp format_team_stats(%{stats: stats} = team) when is_map(stats) do
    """
    - Record: #{stats[:wins] || "?"}-#{stats[:losses] || "?"}-#{stats[:ot_losses] || "?"}
    - Points: #{stats[:points] || "?"}
    - Goals For: #{stats[:goals_for] || "?"}
    - Goals Against: #{stats[:goals_against] || "?"}
    - Goal Differential: #{stats[:goal_diff] || "?"}
    - Conference Rank: #{team[:conference_rank] || "?"}
    - Division Rank: #{team[:division_rank] || "?"}
    """
  end

  defp format_team_stats(team) do
    record = format_record(team[:record])

    """
    - Record: #{record}
    - Points: #{team[:points] || "?"}
    - Conference Rank: #{team[:conference_rank] || "?"}
    """
  end

  defp format_record(%{"total" => total}), do: total
  defp format_record(%{total: total}), do: total
  defp format_record(record) when is_binary(record), do: record
  defp format_record(_), do: "Unknown"

  defp parse_prediction_response(response, home_team, away_team) do
    # Try to extract JSON from the response
    json_str =
      response
      |> String.trim()
      |> extract_json()

    case Jason.decode(json_str) do
      {:ok, data} ->
        prediction = %{
          home_team_id: home_team.id,
          away_team_id: away_team.id,
          home_win_prob: (data["home_win_probability"] || 50) / 100,
          away_win_prob: (data["away_win_probability"] || 50) / 100,
          predicted_winner: data["predicted_winner"],
          predicted_games: data["predicted_games"],
          reasoning: data["reasoning"],
          generated_at: DateTime.utc_now(),
          model: "claude-sonnet-4-20250514"
        }

        {:ok, prediction}

      {:error, _} ->
        Logger.warning("Failed to parse prediction JSON: #{response}")
        # Return a fallback prediction
        {:ok, fallback_prediction(home_team, away_team)}
    end
  end

  defp extract_json(str) do
    # Try to find JSON object in the string
    case Regex.run(~r/\{[^{}]*\}/, str, capture: :first) do
      [json] -> json
      nil -> str
    end
  end

  defp fallback_prediction(home_team, away_team) do
    %{
      home_team_id: home_team.id,
      away_team_id: away_team.id,
      home_win_prob: 0.5,
      away_win_prob: 0.5,
      predicted_winner: nil,
      predicted_games: nil,
      reasoning: "Unable to generate prediction at this time.",
      generated_at: DateTime.utc_now(),
      model: "fallback"
    }
  end

  @doc """
  Predicts the winner of a live NHL game based on current score and game state.

  Takes a game struct with team info, scores, and game status.
  Returns a prediction with win probabilities for each team.
  """
  @spec predict_live_game_winner(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def predict_live_game_winner(game, opts \\ []) do
    prompt = build_live_game_prompt(game)

    messages = [
      %{role: "user", content: prompt}
    ]

    system = """
    You are an NHL game analyst. Given the current game state, predict which team will win. \
    Consider current score, period, time remaining, and team records. Be concise. \
    Respond with ONLY a JSON object, no other text.
    """

    case adapter().chat_completion(messages, Keyword.merge([system: system, max_tokens: 256], opts)) do
      {:ok, response} ->
        parse_live_game_response(response, game)

      {:error, reason} ->
        Logger.error("Failed to get live game prediction: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_live_game_prompt(game) do
    period = game.status.period || 1
    clock = game.status.display_clock || "20:00"

    away_record = game.away_team.records["total"] || "0-0-0"
    home_record = game.home_team.records["total"] || "0-0-0"

    """
    Current NHL game state:

    #{game.away_team.abbreviation} (#{away_record}): #{game.away_team.score}
    #{game.home_team.abbreviation} (#{home_record}): #{game.home_team.score}

    Period: #{period}, Time: #{clock}

    Predict the final winner. Respond with ONLY this JSON format:
    {"winner": "TEAM_ABBREV", "win_probability": 65, "loser": "TEAM_ABBREV", "lose_probability": 35}
    """
  end

  defp parse_live_game_response(response, game) do
    json_str = extract_json(response)

    case Jason.decode(json_str) do
      {:ok, data} ->
        winner_abbrev = data["winner"]
        win_prob = (data["win_probability"] || 50) / 100

        # Determine which team is the predicted winner
        {predicted_winner, predicted_loser, winner_prob, loser_prob} =
          if winner_abbrev == game.home_team.abbreviation do
            {game.home_team, game.away_team, win_prob, 1 - win_prob}
          else
            {game.away_team, game.home_team, win_prob, 1 - win_prob}
          end

        prediction = %{
          game_id: game.id,
          predicted_winner: predicted_winner.abbreviation,
          predicted_winner_logo: predicted_winner.logo,
          winner_probability: winner_prob,
          predicted_loser: predicted_loser.abbreviation,
          loser_probability: loser_prob,
          home_team: game.home_team.abbreviation,
          away_team: game.away_team.abbreviation,
          current_score: "#{game.away_team.score}-#{game.home_team.score}",
          generated_at: DateTime.utc_now(),
          model: "claude-sonnet-4-20250514"
        }

        {:ok, prediction}

      {:error, _} ->
        Logger.warning("Failed to parse live game prediction JSON: #{response}")
        {:ok, fallback_live_game_prediction(game)}
    end
  end

  defp fallback_live_game_prediction(game) do
    # Simple fallback: team with more goals is predicted to win
    {winner, loser, win_prob} =
      cond do
        game.home_team.score > game.away_team.score ->
          {game.home_team, game.away_team, 0.65}

        game.away_team.score > game.home_team.score ->
          {game.away_team, game.home_team, 0.65}

        true ->
          # Tie - slight home advantage
          {game.home_team, game.away_team, 0.52}
      end

    %{
      game_id: game.id,
      predicted_winner: winner.abbreviation,
      predicted_winner_logo: winner.logo,
      winner_probability: win_prob,
      predicted_loser: loser.abbreviation,
      loser_probability: 1 - win_prob,
      home_team: game.home_team.abbreviation,
      away_team: game.away_team.abbreviation,
      current_score: "#{game.away_team.score}-#{game.home_team.score}",
      generated_at: DateTime.utc_now(),
      model: "fallback"
    }
  end

  defp adapter do
    Application.get_env(:yogan_hockey, :anthropic_adapter, YoganHockey.HTTP.AnthropicHTTPAdapter)
  end
end
