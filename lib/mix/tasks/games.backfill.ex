defmodule Mix.Tasks.Games.Backfill do
  @moduledoc """
  Backfills completed games from the ESPN API into the database.

  This task fetches all completed games from the current scoreboard
  and saves them to SQLite with full play-by-play data from the core API.

  ## Usage

      mix games.backfill

  ## Options

      --days=N  - Number of days back to fetch (default: 7)

  ## Examples

      # Backfill games from today's scoreboard
      mix games.backfill

      # Backfill games from the last 14 days
      mix games.backfill --days=14
  """
  use Mix.Task

  require Logger

  @shortdoc "Backfills completed NHL games into the database"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [days: :integer])
    days = Keyword.get(opts, :days, 7)

    # Start the application (needed for Repo and HTTP client)
    Mix.Task.run("app.start")

    alias YoganHockey.Games
    alias YoganHockey.NHL.{APIClient, Parsers}

    Logger.info("Backfilling completed games from the last #{days} days...")

    # Fetch games for each day
    dates = for d <- 0..days, do: Date.utc_today() |> Date.add(-d) |> Calendar.strftime("%Y%m%d")

    total_saved = 0

    total_saved =
      Enum.reduce(dates, total_saved, fn date, acc ->
        case APIClient.get_scoreboard(date) do
          {:ok, data} ->
            games = Parsers.parse_scoreboard(data)
            completed = Enum.filter(games, &(&1.status.state == "post"))

            saved =
              Enum.reduce(completed, 0, fn game, count ->
                game_id = to_string(game.id)

                if Games.get_completed_game(game_id) do
                  Logger.debug("Game #{game_id} already exists, skipping")
                  count
                else
                  case save_game_with_plays(game_id) do
                    :ok -> count + 1
                    :error -> count
                  end
                end
              end)

            Logger.info("Date #{date}: found #{length(completed)} completed games, saved #{saved} new")
            acc + saved

          {:error, reason} ->
            Logger.warning("Failed to fetch scoreboard for #{date}: #{inspect(reason)}")
            acc
        end
      end)

    Logger.info("Backfill complete. Total new games saved: #{total_saved}")
  end

  defp save_game_with_plays(game_id) do
    alias YoganHockey.Games
    alias YoganHockey.NHL.{APIClient, Parsers}

    with {:ok, summary_data} <- APIClient.get_game_summary(game_id),
         game_data when not is_nil(game_data) <- Parsers.parse_game_summary(summary_data),
         {:ok, plays_data} <- APIClient.get_game_plays(game_id) do
      # Parse full plays from core API
      plays = Parsers.parse_core_api_plays(plays_data, game_data.home_team, game_data.away_team)
      game_data = %{game_data | plays: plays}

      case Games.save_completed_game(game_data) do
        {:ok, _} ->
          Logger.info("Saved game #{game_id} with #{length(plays)} plays")
          :ok

        {:error, reason} ->
          Logger.error("Failed to save game #{game_id}: #{inspect(reason)}")
          :error
      end
    else
      nil ->
        Logger.warning("Failed to parse game #{game_id}")
        :error

      {:error, reason} ->
        Logger.warning("Failed to fetch game #{game_id}: #{inspect(reason)}")
        :error
    end
  end
end
