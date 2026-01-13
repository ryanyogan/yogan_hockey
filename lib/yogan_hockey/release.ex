defmodule YoganHockey.Release do
  @moduledoc """
  Release tasks for migrations and data backfill.

  For Fly.io with SQLite, migrations run on application start
  because volumes may not be ready during the release phase.

  ## Usage in production

      # Run migrations (done automatically on app start)
      /app/bin/yogan_hockey eval "YoganHockey.Release.migrate()"

      # Backfill completed games from last 7 days
      /app/bin/yogan_hockey eval "YoganHockey.Release.backfill_games()"

      # Backfill completed games from last 14 days
      /app/bin/yogan_hockey eval "YoganHockey.Release.backfill_games(14)"
  """

  require Logger

  @app :yogan_hockey

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Backfills completed games from the ESPN API into the database.
  Fetches games from the last N days (default: 7).
  """
  def backfill_games(days \\ 7) do
    start_app()

    alias YoganHockey.Games
    alias YoganHockey.NHL.{APIClient, Parsers}

    Logger.info("Backfilling completed games from the last #{days} days...")

    dates = for d <- 0..days, do: Date.utc_today() |> Date.add(-d) |> Calendar.strftime("%Y%m%d")

    total_saved =
      Enum.reduce(dates, 0, fn date, acc ->
        case APIClient.get_scoreboard(date) do
          {:ok, data} ->
            games = Parsers.parse_scoreboard(data)
            completed = Enum.filter(games, &(&1.status.state == "post"))

            saved =
              Enum.reduce(completed, 0, fn game, count ->
                game_id = to_string(game.id)

                if Games.get_completed_game(game_id) do
                  count
                else
                  case save_game_with_plays(game_id) do
                    :ok -> count + 1
                    :error -> count
                  end
                end
              end)

            Logger.info("Date #{date}: found #{length(completed)} completed, saved #{saved} new")
            acc + saved

          {:error, reason} ->
            Logger.warning("Failed to fetch scoreboard for #{date}: #{inspect(reason)}")
            acc
        end
      end)

    Logger.info("Backfill complete. Total new games saved: #{total_saved}")
    :ok
  end

  defp save_game_with_plays(game_id) do
    alias YoganHockey.Games
    alias YoganHockey.NHL.{APIClient, Parsers}

    with {:ok, summary_data} <- APIClient.get_game_summary(game_id),
         game_data when not is_nil(game_data) <- Parsers.parse_game_summary(summary_data),
         {:ok, plays_data} <- APIClient.get_game_plays(game_id) do
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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end
end
