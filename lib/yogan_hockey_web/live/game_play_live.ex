defmodule YoganHockeyWeb.GamePlayLive do
  @moduledoc """
  Live game play page with ice rink visualization and play-by-play stream.
  Shows countdown for pregame, live data for in-progress games.
  For historical games not in DB, fetches and saves on demand.
  """
  use YoganHockeyWeb, :live_view

  require Logger

  alias YoganHockey.GamePlay.GamePlayServer
  alias YoganHockey.Games
  alias YoganHockey.Games.CompletedGame
  alias YoganHockey.NHL
  alias YoganHockey.NHL.{APIClient, Parsers}
  alias YoganHockeyWeb.SEO

  import YoganHockeyWeb.GamePlayComponents

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    # First, check if game exists in database (historical game)
    case Games.get_completed_game(game_id) do
      %CompletedGame{game_data: stored_data} = completed ->
        # Historical game - load from DB
        game_data = Games.map_to_game_data(stored_data)

        socket =
          socket
          |> assign(:game_id, game_id)
          |> assign(:game_info, nil)
          |> assign(:game_data, game_data)
          |> assign(:play_filter, :all)
          |> assign(:period_filter, :all)
          |> assign(:countdown, nil)
          |> assign(:historical, true)
          |> assign(:fetching_historical, false)
          |> put_seo_from_completed(completed)

        {:ok, socket}

      nil ->
        # Game not in DB - check if it's a completed game we need to fetch
        game_info = NHL.get_game(game_id)

        socket =
          socket
          |> assign(:game_id, game_id)
          |> assign(:game_info, game_info)
          |> assign(:game_data, nil)
          |> assign(:play_filter, :all)
          |> assign(:period_filter, :all)
          |> assign(:countdown, nil)
          |> assign(:historical, false)
          |> assign(:fetching_historical, false)
          |> put_seo(game_info)

        if connected?(socket) do
          socket = maybe_start_game_server(socket, game_info)
          {:ok, socket}
        else
          {:ok, socket}
        end
    end
  end

  # Determine how to handle the game based on its status
  defp maybe_start_game_server(socket, game_info) do
    cond do
      # Game is completed but not in DB - fetch and save
      game_is_completed?(game_info) ->
        fetch_historical_game(socket, game_info)

      # Game is in progress - connect to live updates
      game_has_started?(game_info) ->
        start_live_game(socket, game_info)

      # Game is pregame with valid date - start countdown
      is_binary(game_info[:date]) ->
        start_pregame_countdown(socket, game_info.date)

      # Fallback
      true ->
        socket
    end
  end

  # Fetch completed game data in background and save to DB
  defp fetch_historical_game(socket, game_info) do
    game_id = socket.assigns.game_id
    pid = self()

    # Start background task to fetch and save
    Task.Supervisor.start_child(YoganHockey.TaskSupervisor, fn ->
      result = fetch_and_save_game(game_id)
      send(pid, {:historical_game_fetched, result})
    end)

    socket
    |> assign(:fetching_historical, true)
    |> assign(:game_info, game_info)
  end

  # Fetch game data from API and save to database
  defp fetch_and_save_game(game_id) do
    with {:ok, summary_data} <- APIClient.get_game_summary(game_id),
         game_data when not is_nil(game_data) <- Parsers.parse_game_summary(summary_data),
         {:ok, plays_data} <- APIClient.get_game_plays(game_id) do
      # Parse full plays from core API
      plays = Parsers.parse_core_api_plays(plays_data, game_data.home_team, game_data.away_team)
      game_data = %{game_data | plays: plays}

      # Save to database
      case Games.save_completed_game(game_data) do
        {:ok, _} ->
          Logger.info("Saved historical game #{game_id} with #{length(plays)} plays")
          {:ok, game_data}

        {:error, reason} ->
          Logger.error("Failed to save historical game #{game_id}: #{inspect(reason)}")
          {:ok, game_data}
      end
    else
      nil ->
        Logger.warning("Failed to parse historical game #{game_id}")
        {:error, :parse_failed}

      {:error, reason} ->
        Logger.warning("Failed to fetch historical game #{game_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp game_is_completed?(nil), do: false
  defp game_is_completed?(%{status: %{state: "post"}}), do: true
  defp game_is_completed?(%{status: status}) when is_map(status), do: status[:state] == "post"
  defp game_is_completed?(_), do: false

  defp start_pregame_countdown(socket, date_string) do
    # Subscribe to live scores to get notified when game status changes
    Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")

    countdown = calculate_countdown(date_string)

    cond do
      countdown && countdown > 0 ->
        # Game hasn't started - countdown to scheduled time
        Process.send_after(self(), :tick_countdown, 1000)
        assign(socket, :countdown, countdown)

      true ->
        # Game should have started by now but status is still "pre"
        # Poll for game start every 10 seconds as backup
        Process.send_after(self(), :check_game_start, 1000)
        assign(socket, :countdown, 0)
    end
  end

  defp calculate_countdown(date_string) do
    # ESPN returns dates like "2026-01-13T00:00Z" (missing seconds)
    # Elixir requires "2026-01-13T00:00:00Z" format
    normalized = normalize_iso8601(date_string)

    case DateTime.from_iso8601(normalized) do
      {:ok, game_time, _offset} ->
        now = DateTime.utc_now()
        DateTime.diff(game_time, now)

      _ ->
        nil
    end
  end

  # Normalize ESPN date format to include seconds if missing
  defp normalize_iso8601(date_string) do
    # Match pattern like "T00:00Z" and convert to "T00:00:00Z"
    if String.match?(date_string, ~r/T\d{2}:\d{2}Z$/) do
      String.replace(date_string, ~r/T(\d{2}):(\d{2})Z$/, "T\\1:\\2:00Z")
    else
      date_string
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Only unregister from GamePlayServer for live games (not historical)
    if socket.assigns[:game_id] && socket.assigns[:game_data] && !socket.assigns[:historical] do
      GamePlayServer.unregister_viewer(socket.assigns.game_id, self())
    end

    :ok
  end

  # ============================================
  # HANDLE_INFO CALLBACKS
  # ============================================

  @impl true
  def handle_info(:tick_countdown, socket) do
    countdown = socket.assigns.countdown

    cond do
      is_nil(countdown) ->
        {:noreply, socket}

      countdown <= 0 ->
        # Countdown expired - check if game has started
        check_game_status(socket)

      true ->
        Process.send_after(self(), :tick_countdown, 1000)
        {:noreply, assign(socket, :countdown, countdown - 1)}
    end
  end

  # Periodically check if game has started (every 10 seconds after countdown expires)
  def handle_info(:check_game_start, socket) do
    check_game_status(socket)
  end

  # Game play data updated from GamePlayServer
  def handle_info({:game_play_updated, game_data}, socket) do
    {:noreply, assign(socket, :game_data, game_data)}
  end

  # Handle live scores update - check if our game has started
  def handle_info({:live_scores_updated, games}, socket) do
    # Only process if we don't already have game_data (still in pregame)
    if socket.assigns.game_data do
      {:noreply, socket}
    else
      game_id = socket.assigns.game_id

      case Enum.find(games, &(to_string(&1.id) == to_string(game_id))) do
        nil ->
          {:noreply, socket}

        game_info ->
          if game_has_started?(game_info) do
            # Game has started - transition to live mode
            socket = start_live_game(socket, game_info)
            {:noreply, socket}
          else
            # Update game info but game hasn't started yet
            {:noreply, assign(socket, :game_info, game_info)}
          end
      end
    end
  end

  # Historical game data fetched from API
  def handle_info({:historical_game_fetched, {:ok, game_data}}, socket) do
    socket =
      socket
      |> assign(:game_data, game_data)
      |> assign(:fetching_historical, false)
      |> assign(:historical, true)

    {:noreply, socket}
  end

  def handle_info({:historical_game_fetched, {:error, _reason}}, socket) do
    # Failed to fetch - show error state
    {:noreply, assign(socket, :fetching_historical, false)}
  end

  # ============================================
  # PRIVATE FUNCTIONS
  # ============================================

  defp check_game_status(socket) do
    game_info = NHL.get_game(socket.assigns.game_id)
    socket = assign(socket, :game_info, game_info)

    if game_has_started?(game_info) do
      # Game has started - subscribe to live updates
      socket = start_live_game(socket, game_info)
      {:noreply, socket}
    else
      # Game still hasn't started - keep checking every 10 seconds
      Process.send_after(self(), :check_game_start, 10_000)
      {:noreply, assign(socket, :countdown, 0)}
    end
  end

  # Determines if game has started based on various status indicators
  defp game_has_started?(nil), do: false

  defp game_has_started?(%{status: status}) do
    cond do
      # Explicit state indicates in-progress or completed
      status[:state] in ["in", "post"] ->
        true

      # Period > 0 means game has started
      is_integer(status[:period]) and status[:period] > 0 ->
        true

      # Status detail contains period/intermission info
      is_binary(status[:detail]) and game_in_progress_detail?(status[:detail]) ->
        true

      true ->
        false
    end
  end

  defp game_has_started?(_), do: false

  # Check if status detail indicates game is in progress
  defp game_in_progress_detail?(detail) do
    detail_lower = String.downcase(detail)

    Enum.any?([
      String.contains?(detail_lower, "1st"),
      String.contains?(detail_lower, "2nd"),
      String.contains?(detail_lower, "3rd"),
      String.contains?(detail_lower, "ot"),
      String.contains?(detail_lower, "overtime"),
      String.contains?(detail_lower, "shootout"),
      String.contains?(detail_lower, "so"),
      String.contains?(detail_lower, "end of"),
      String.contains?(detail_lower, "final"),
      String.contains?(detail_lower, "intermission")
    ])
  end

  defp start_live_game(socket, game_info) do
    game_id = socket.assigns.game_id
    Phoenix.PubSub.subscribe(YoganHockey.PubSub, "game_play:#{game_id}")
    GamePlayServer.register_viewer(game_id, self())

    game_data = GamePlayServer.get_game_data(game_id)

    socket
    |> assign(:game_info, game_info)
    |> assign(:game_data, game_data)
  end

  @impl true
  def handle_event("filter_plays", %{"type" => type}, socket) do
    filter =
      case type do
        "all" -> :all
        "goal" -> :goal
        "shot" -> :shot
        "penalty" -> :penalty
        "hit" -> :hit
        _ -> :all
      end

    {:noreply, assign(socket, :play_filter, filter)}
  end

  @impl true
  def handle_event("filter_period", %{"period" => period}, socket) do
    filter =
      case period do
        "all" -> :all
        p -> String.to_integer(p)
      end

    {:noreply, assign(socket, :period_filter, filter)}
  end

  defp put_seo(socket, nil) do
    SEO.put_seo(socket,
      title: "Game",
      description: "Live NHL game stats, play-by-play, and ice rink visualization.",
      url: "/nhl/games/#{socket.assigns.game_id}"
    )
  end

  defp put_seo(socket, game_info) do
    SEO.put_seo(socket,
      title: "#{game_info.away_team.abbreviation} @ #{game_info.home_team.abbreviation}",
      description: "#{game_info.away_team.name} vs #{game_info.home_team.name}. Real-time stats, play-by-play, and ice rink visualization.",
      url: "/nhl/games/#{socket.assigns.game_id}"
    )
  end

  defp put_seo_from_completed(socket, %CompletedGame{} = completed) do
    SEO.put_seo(socket,
      title: "#{completed.away_team_name} @ #{completed.home_team_name}",
      description: "Final: #{completed.away_team_name} #{completed.away_score} - #{completed.home_team_name} #{completed.home_score}. Play-by-play and game stats.",
      url: "/nhl/games/#{completed.game_id}"
    )
  end

  defp filter_plays(plays, :all, :all), do: plays

  defp filter_plays(plays, type_filter, period_filter) do
    plays
    |> filter_by_type(type_filter)
    |> filter_by_period(period_filter)
  end

  defp filter_by_type(plays, :all), do: plays
  defp filter_by_type(plays, type), do: Enum.filter(plays, &(&1.type == type))

  defp filter_by_period(plays, :all), do: plays
  defp filter_by_period(plays, period), do: Enum.filter(plays, &(&1.period == period))

  @impl true
  def render(assigns) do
    # Determine if game has started based on game_info status
    game_started = game_has_started?(assigns.game_info)

    assigns = assign(assigns, :game_started, game_started)

    ~H"""
    <div class="space-y-4">
      <%= cond do %>
        <% @game_data -> %>
          <%!-- Live/Complete game with full data --%>
          <.game_header
            home_team={@game_data.home_team}
            away_team={@game_data.away_team}
            status={@game_data.status}
          />

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <div class="lg:col-span-2 space-y-4">
              <.ice_rink
                plays={filter_plays(@game_data.plays, @play_filter, @period_filter)}
                home_team={@game_data.home_team}
                away_team={@game_data.away_team}
              />

              <.play_filters
                play_filter={@play_filter}
                period_filter={@period_filter}
                current_period={@game_data.status.period}
                plays={@game_data.plays}
              />
            </div>

            <div class="space-y-4">
              <.team_stats_comparison
                home_team={@game_data.home_team}
                away_team={@game_data.away_team}
              />

              <.play_by_play_stream
                plays={filter_plays(@game_data.plays, @play_filter, @period_filter)}
                home_team={@game_data.home_team}
                away_team={@game_data.away_team}
              />
            </div>
          </div>

          <.period_scoring boxscore={@game_data.boxscore} />

          <div class="text-center text-xs text-base-content/40">
            Updated: {format_datetime(@game_data.last_updated)}
          </div>

        <% @fetching_historical and @game_info -> %>
          <%!-- Fetching historical game data --%>
          <.game_header_loading game_info={@game_info} />

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <div class="lg:col-span-2 space-y-4">
              <div class="data-card p-12">
                <div class="flex flex-col items-center justify-center text-center">
                  <div class="inline-block animate-spin rounded-full h-10 w-10 border-b-2 border-primary mb-4"></div>
                  <h3 class="text-lg font-bold mb-2">Fetching Game Data</h3>
                  <p class="text-sm text-base-content/60">Loading play-by-play and statistics...</p>
                </div>
              </div>
            </div>

            <div class="space-y-4">
              <div class="data-card p-8 text-center">
                <div class="inline-block animate-spin rounded-full h-6 w-6 border-b-2 border-primary mb-3"></div>
                <p class="text-sm text-base-content/60">Loading stats...</p>
              </div>
            </div>
          </div>

        <% @game_started and @game_info -> %>
          <%!-- Game started but waiting for detailed data --%>
          <.game_header_loading game_info={@game_info} />

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <div class="lg:col-span-2 space-y-4">
              <.loading_state game_id={@game_id} />
            </div>

            <div class="space-y-4">
              <div class="data-card p-8 text-center">
                <div class="inline-block animate-spin rounded-full h-6 w-6 border-b-2 border-primary mb-3"></div>
                <p class="text-sm text-base-content/60">Loading live stats...</p>
              </div>
            </div>
          </div>

        <% @game_info -> %>
          <%!-- Pregame state with countdown --%>
          <.pregame_header
            home_team={@game_info.home_team}
            away_team={@game_info.away_team}
            status={@game_info.status}
            venue={@game_info.venue}
            broadcasts={@game_info.broadcasts}
          />

          <.countdown_timer countdown={@countdown} scheduled_time={@game_info.status.detail} />

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <div class="lg:col-span-2 space-y-4">
              <.ice_rink_placeholder countdown={@countdown} />
            </div>

            <div class="space-y-4">
              <.pregame_team_preview
                home_team={@game_info.home_team}
                away_team={@game_info.away_team}
              />
            </div>
          </div>

        <% true -> %>
          <%!-- Game not found --%>
          <.game_not_found game_id={@game_id} />
      <% end %>
    </div>
    """
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%H:%M:%S UTC")
  end
end
