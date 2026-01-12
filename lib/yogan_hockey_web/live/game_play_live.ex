defmodule YoganHockeyWeb.GamePlayLive do
  @moduledoc """
  Live game play page with ice rink visualization and play-by-play stream.
  Shows countdown for pregame, live data for in-progress games.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.GamePlay.GamePlayServer
  alias YoganHockey.NHL
  alias YoganHockeyWeb.SEO

  import YoganHockeyWeb.GamePlayComponents

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    # First, get basic game info from scoreboard cache
    game_info = NHL.get_game(game_id)

    socket =
      socket
      |> assign(:game_id, game_id)
      |> assign(:game_info, game_info)
      |> assign(:game_data, nil)
      |> assign(:play_filter, :all)
      |> assign(:period_filter, :all)
      |> assign(:countdown, nil)
      |> put_seo(game_info)

    if connected?(socket) do
      socket = maybe_start_game_server(socket, game_info)
      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  # Only start game server for in-progress or completed games
  defp maybe_start_game_server(socket, %{status: %{state: state}})
       when state in ["in", "post"] do
    game_id = socket.assigns.game_id
    Phoenix.PubSub.subscribe(YoganHockey.PubSub, "game_play:#{game_id}")
    GamePlayServer.register_viewer(game_id, self())

    game_data = GamePlayServer.get_game_data(game_id)
    assign(socket, :game_data, game_data)
  end

  # For pregame, start countdown timer
  defp maybe_start_game_server(socket, %{date: date_string} = _game_info) when is_binary(date_string) do
    countdown = calculate_countdown(date_string)
    if countdown && countdown > 0 do
      Process.send_after(self(), :tick_countdown, 1000)
    end
    assign(socket, :countdown, countdown)
  end

  defp maybe_start_game_server(socket, _game_info), do: socket

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
    if socket.assigns[:game_id] && socket.assigns[:game_data] do
      GamePlayServer.unregister_viewer(socket.assigns.game_id, self())
    end

    :ok
  end

  @impl true
  def handle_info(:tick_countdown, socket) do
    countdown = socket.assigns.countdown

    cond do
      is_nil(countdown) ->
        {:noreply, socket}

      countdown <= 0 ->
        # Game should be starting - check for updates and potentially start server
        game_info = NHL.get_game(socket.assigns.game_id)
        socket = assign(socket, :game_info, game_info)
        socket = maybe_start_game_server(socket, game_info)
        {:noreply, socket}

      true ->
        Process.send_after(self(), :tick_countdown, 1000)
        {:noreply, assign(socket, :countdown, countdown - 1)}
    end
  end

  @impl true
  def handle_info({:game_play_updated, game_data}, socket) do
    {:noreply, assign(socket, :game_data, game_data)}
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
              <.ice_rink_placeholder />
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
