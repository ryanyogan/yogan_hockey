defmodule YoganHockeyWeb.LiveScoresLive do
  @moduledoc """
  Live NHL scores - ESPN-style real-time scores page.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.NHL

  import YoganHockeyWeb.HockeyComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")
    end

    games = NHL.list_live_scores()
    last_updated = NHL.live_scores_updated_at()

    {:ok,
     socket
     |> assign(:page_title, "Live Scores")
     |> assign(:games, games)
     |> assign(:last_updated, last_updated)
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
          <.live_game_card :for={game <- @live_games} game={game} />
        </div>
      </section>

      <%!-- Scheduled Games --%>
      <section :if={@scheduled_games != []} class="space-y-3">
        <div class="text-xs font-bold uppercase tracking-wider text-base-content/60">
          Upcoming ({length(@scheduled_games)})
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          <.game_card :for={game <- @scheduled_games} game={game} />
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

  def live_game_card(assigns) do
    ~H"""
    <div class="game-card live">
      <div class="game-card-header">
        <span class="live-indicator">Live</span>
        <span class="font-mono">{period_display(@game.status)}</span>
      </div>
      <div class="p-4">
        <div class="flex items-center justify-between gap-3">
          <%!-- Away --%>
          <div class="flex items-center gap-2 flex-1">
            <img :if={@game.away_team.logo} src={@game.away_team.logo} class="w-7 h-7 object-contain" />
            <div>
              <div class="text-sm font-bold">{@game.away_team.abbreviation}</div>
              <div class="text-[10px] text-base-content/50">{@game.away_team.records["total"]}</div>
            </div>
          </div>
          <%!-- Score --%>
          <div class="flex items-center gap-1.5 font-mono">
            <span class={["text-2xl font-bold", @game.away_team.winner && "text-primary"]}>
              {@game.away_team.score}
            </span>
            <span class="text-lg text-base-content/30">-</span>
            <span class={["text-2xl font-bold", @game.home_team.winner && "text-primary"]}>
              {@game.home_team.score}
            </span>
          </div>
          <%!-- Home --%>
          <div class="flex items-center gap-2 flex-1 justify-end">
            <div class="text-right">
              <div class="text-sm font-bold">{@game.home_team.abbreviation}</div>
              <div class="text-[10px] text-base-content/50">{@game.home_team.records["total"]}</div>
            </div>
            <img :if={@game.home_team.logo} src={@game.home_team.logo} class="w-7 h-7 object-contain" />
          </div>
        </div>
        <%!-- Clock --%>
        <div class="mt-3 pt-3 border-t border-base-300 flex justify-between text-xs">
          <span class="font-mono text-error">{@game.status.display_clock}</span>
          <span :if={@game.venue} class="text-base-content/50 truncate">{@game.venue.name}</span>
        </div>
      </div>
    </div>
    """
  end

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
end
