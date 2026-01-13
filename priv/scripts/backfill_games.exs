# Backfill Completed NHL Games Script
#
# This script fetches all completed NHL games from the ESPN API
# and saves them to the SQLite database with full play-by-play data.
#
# Usage:
#   Development:  mix run priv/scripts/backfill_games.exs
#   Production:   /app/bin/yogan_hockey eval "Code.eval_file(\"priv/scripts/backfill_games.exs\")"
#
#   Or use the Release module directly in production:
#   /app/bin/yogan_hockey eval "YoganHockey.Release.backfill_games(30)"
#
# Options (set via environment variables):
#   BACKFILL_DAYS - Number of days to look back (default: 30)

require Logger

alias YoganHockey.Games
alias YoganHockey.NHL.{APIClient, Parsers}

defmodule BackfillGames do
  require Logger

  def run(days \\ 30) do
    Logger.info("=" |> String.duplicate(60))
    Logger.info("NHL Games Backfill Script")
    Logger.info("=" |> String.duplicate(60))
    Logger.info("Looking back #{days} days for completed games...")
    Logger.info("")

    # Generate dates to check
    dates =
      for d <- 0..days do
        Date.utc_today() |> Date.add(-d) |> Calendar.strftime("%Y%m%d")
      end

    # Track statistics
    stats = %{
      dates_checked: 0,
      games_found: 0,
      games_saved: 0,
      games_skipped: 0,
      games_failed: 0
    }

    stats =
      Enum.reduce(dates, stats, fn date, acc ->
        acc = %{acc | dates_checked: acc.dates_checked + 1}

        case APIClient.get_scoreboard(date) do
          {:ok, data} ->
            games = Parsers.parse_scoreboard(data)
            completed = Enum.filter(games, &(&1.status.state == "post"))

            acc = %{acc | games_found: acc.games_found + length(completed)}

            Enum.reduce(completed, acc, fn game, inner_acc ->
              game_id = to_string(game.id)
              process_game(game_id, game, inner_acc)
            end)

          {:error, reason} ->
            Logger.warning("Failed to fetch scoreboard for #{date}: #{inspect(reason)}")
            acc
        end
      end)

    # Print summary
    Logger.info("")
    Logger.info("=" |> String.duplicate(60))
    Logger.info("Backfill Complete!")
    Logger.info("=" |> String.duplicate(60))
    Logger.info("Dates checked:  #{stats.dates_checked}")
    Logger.info("Games found:    #{stats.games_found}")
    Logger.info("Games saved:    #{stats.games_saved}")
    Logger.info("Games skipped:  #{stats.games_skipped} (already in database)")
    Logger.info("Games failed:   #{stats.games_failed}")
    Logger.info("=" |> String.duplicate(60))

    :ok
  end

  defp process_game(game_id, game, stats) do
    if Games.get_completed_game(game_id) do
      %{stats | games_skipped: stats.games_skipped + 1}
    else
      away = game.away_team.abbreviation
      home = game.home_team.abbreviation
      Logger.info("Fetching: #{away} @ #{home} (#{game_id})...")

      case fetch_and_save(game_id) do
        {:ok, play_count} ->
          Logger.info("  Saved with #{play_count} plays")
          %{stats | games_saved: stats.games_saved + 1}

        {:error, reason} ->
          Logger.error("  Failed: #{inspect(reason)}")
          %{stats | games_failed: stats.games_failed + 1}
      end
    end
  end

  defp fetch_and_save(game_id) do
    with {:ok, summary_data} <- APIClient.get_game_summary(game_id),
         game_data when not is_nil(game_data) <- Parsers.parse_game_summary(summary_data),
         {:ok, plays_data} <- APIClient.get_game_plays(game_id) do
      # Parse full plays from core API
      plays = Parsers.parse_core_api_plays(plays_data, game_data.home_team, game_data.away_team)
      game_data = %{game_data | plays: plays}

      case Games.save_completed_game(game_data) do
        {:ok, _} -> {:ok, length(plays)}
        {:error, reason} -> {:error, reason}
      end
    else
      nil -> {:error, :parse_failed}
      {:error, reason} -> {:error, reason}
    end
  end
end

# Get days from environment or default to 30
days =
  case System.get_env("BACKFILL_DAYS") do
    nil -> 30
    val -> String.to_integer(val)
  end

# Run the backfill
BackfillGames.run(days)
