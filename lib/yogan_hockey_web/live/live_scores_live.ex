defmodule YoganHockeyWeb.LiveScoresLive do
  @moduledoc """
  Live NHL scores - ESPN-style real-time scores page with AI predictions.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.NHL
  alias YoganHockey.LiveGames.PredictionServer

  import YoganHockeyWeb.HockeyComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")
    end

    games = NHL.list_live_scores()
    last_updated = NHL.live_scores_updated_at()

    # Request predictions for live/scheduled games
    if connected?(socket) do
      PredictionServer.ensure_predictions(games)
    end

    # Get existing predictions
    predictions = PredictionServer.get_all_predictions()

    {:ok,
     socket
     |> assign(:page_title, "Live Scores")
     |> assign(:games, games)
     |> assign(:last_updated, last_updated)
     |> assign(:predictions, predictions)
     |> assign_game_categories(games)}
  end

  @impl true
  def handle_info({:live_scores_updated, games}, socket) do
    {:noreply,
     socket
     |> assign(:games, games)
     |> assign(:last_updated, DateTime.utc_now())
     |> assign_game_categories(games)}
  end

  @impl true
  def handle_info({:prediction_updated, game_id, prediction}, socket) do
    require Logger
    Logger.info("LiveScoresLive received prediction for game #{game_id}")
    predictions = Map.put(socket.assigns.predictions, game_id, prediction)
    {:noreply, assign(socket, :predictions, predictions)}
  end

  defp assign_game_categories(socket, games) do
    socket
    |> assign(:live_games, Enum.filter(games, &(&1.status.state == "in")))
    |> assign(:scheduled_games, Enum.filter(games, &(&1.status.state == "pre")))
    |> assign(:completed_games, Enum.filter(games, &(&1.status.state == "post")))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span class="live-indicator">Live</span>
          <span class="section-title text-lg">NHL Scores</span>
        </div>
        <div :if={@last_updated} class="text-xs text-base-content/50">
          Updated: {format_time(@last_updated)}
        </div>
      </div>

      <%!-- Live Games --%>
      <section :if={@live_games != []} class="space-y-3">
        <div class="text-xs font-bold uppercase tracking-wider text-base-content/60">
          In Progress ({length(@live_games)})
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <.live_game_card :for={game <- @live_games} game={game} prediction={@predictions[game.id]} />
        </div>
      </section>

      <%!-- Scheduled Games --%>
      <section :if={@scheduled_games != []} class="space-y-3">
        <div class="text-xs font-bold uppercase tracking-wider text-base-content/60">
          Upcoming ({length(@scheduled_games)})
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          <.game_card :for={game <- @scheduled_games} game={game} prediction={@predictions[game.id]} />
        </div>
      </section>

      <%!-- Completed Games --%>
      <section :if={@completed_games != []} class="space-y-3">
        <div class="text-xs font-bold uppercase tracking-wider text-base-content/60">
          Final ({length(@completed_games)})
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          <.game_card :for={game <- @completed_games} game={game} />
        </div>
      </section>

      <%!-- No Games --%>
      <div :if={Enum.empty?(@games)} class="data-card p-12 text-center">
        <div class="text-5xl mb-4">🏒</div>
        <h2 class="text-xl font-bold mb-2">No Games Today</h2>
        <p class="text-base-content/60">Check back later for NHL action</p>
      </div>
    </div>
    """
  end

  attr :game, :map, required: true
  attr :prediction, :map, default: nil

  def live_game_card(assigns) do
    assigns = assign(assigns, :predicted_winner_abbrev, get_predicted_winner(assigns.prediction))

    ~H"""
    <div class="game-card live">
      <div class="game-card-header">
        <div class="flex items-center gap-2 min-w-0">
          <span class="live-indicator shrink-0">Live</span>
          <span class="font-mono shrink-0">{period_display(@game.status)}</span>
        </div>
        <div :if={@game.broadcasts != []} class="relative group shrink min-w-0">
          <span class="text-base-content/40 truncate block max-w-[80px] cursor-help">
            {Enum.join(@game.broadcasts, ", ")}
          </span>
          <div class="absolute right-0 top-full mt-1 z-50 hidden group-hover:block group-focus:block bg-base-300 text-base-content text-xs px-2 py-1 rounded shadow-lg whitespace-nowrap">
            {Enum.join(@game.broadcasts, ", ")}
          </div>
        </div>
      </div>
      <div class="p-4">
        <%!-- Away Team --%>
        <div class="flex items-center justify-between gap-3">
          <div class="flex items-center gap-2 flex-1">
            <img :if={@game.away_team.logo} src={@game.away_team.logo} class="w-7 h-7 object-contain" />
            <div>
              <div class={[
                "text-sm font-bold",
                @predicted_winner_abbrev == @game.away_team.abbreviation && "text-info"
              ]}>
                {@game.away_team.abbreviation}
              </div>
              <div class="text-[10px] text-base-content/50">{@game.away_team.records["total"]}</div>
            </div>
          </div>
          <span class={["text-2xl font-bold font-mono", @game.away_team.winner && "text-primary"]}>
            {@game.away_team.score}
          </span>
        </div>

        <%!-- Prediction Progress Bar --%>
        <div :if={@prediction} class="relative flex items-center my-2">
          <div class="h-[1px] w-full flex">
            <div class="bg-info" style={"width: #{prediction_bar_percent(@prediction)}%"}></div>
            <div class="bg-base-200" style={"width: #{100 - prediction_bar_percent(@prediction)}%"}></div>
          </div>
          <span
            class="absolute -translate-x-1/2 text-[9px] text-base-content/50 font-mono bg-base-100 px-1"
            style={"left: #{prediction_bar_percent(@prediction)}%"}
          >
            {@prediction.predicted_winner} {format_probability(@prediction.winner_probability)}
          </span>
        </div>

        <%!-- Home Team --%>
        <div class="flex items-center justify-between gap-3">
          <div class="flex items-center gap-2 flex-1">
            <img :if={@game.home_team.logo} src={@game.home_team.logo} class="w-7 h-7 object-contain" />
            <div>
              <div class={[
                "text-sm font-bold",
                @predicted_winner_abbrev == @game.home_team.abbreviation && "text-info"
              ]}>
                {@game.home_team.abbreviation}
              </div>
              <div class="text-[10px] text-base-content/50">{@game.home_team.records["total"]}</div>
            </div>
          </div>
          <span class={["text-2xl font-bold font-mono", @game.home_team.winner && "text-primary"]}>
            {@game.home_team.score}
          </span>
        </div>

        <%!-- Footer: Clock + Venue --%>
        <div class="mt-3 pt-3 border-t border-base-300 flex justify-between items-center text-xs">
          <span class="font-mono text-error">{@game.status.display_clock}</span>
          <span :if={@game.venue} class="text-base-content/50 truncate">{@game.venue.name}</span>
        </div>
      </div>
    </div>
    """
  end

  defp get_predicted_winner(nil), do: nil
  defp get_predicted_winner(%{predicted_winner: winner}), do: winner

  defp prediction_bar_percent(%{winner_probability: prob}) when is_float(prob) do
    round(prob * 100)
  end

  defp prediction_bar_percent(_), do: 50

  defp period_display(%{period: period, detail: detail}) when is_integer(period) do
    case period do
      1 -> "1st"
      2 -> "2nd"
      3 -> "3rd"
      _ -> detail || "OT"
    end
  end
  defp period_display(%{detail: detail}), do: detail || ""

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S UTC")
  end

  defp format_probability(prob) when is_float(prob) do
    "#{round(prob * 100)}%"
  end

  defp format_probability(_), do: ""
end
