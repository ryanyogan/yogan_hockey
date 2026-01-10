defmodule YoganHockeyWeb.YoganLive do
  @moduledoc """
  Andrew Yogan stats - ESPN-style player page.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.DEL2

  import YoganHockeyWeb.HockeyComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "yogan:stats")
    end

    stats = DEL2.get_yogan_stats()
    team = DEL2.get_team()

    {:ok,
     socket
     |> assign(:page_title, "Andrew Yogan")
     |> assign(:player, stats.player)
     |> assign(:current_season, stats.current_season)
     |> assign(:career_stats, stats.career_stats)
     |> assign(:team, team)
     |> assign(:last_updated, DEL2.yogan_stats_updated_at())}
  end

  @impl true
  def handle_info({:yogan_stats_updated, stats}, socket) do
    {:noreply,
     socket
     |> assign(:player, stats.player)
     |> assign(:current_season, stats.current_season)
     |> assign(:career_stats, stats.career_stats)
     |> assign(:last_updated, DateTime.utc_now())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Player Header Card --%>
      <div class="featured-card p-6">
        <span class="featured-badge">{@player[:league] || "DEL"}</span>
        <div class="relative z-10 flex flex-col lg:flex-row gap-6">
          <%!-- Avatar --%>
          <div class="w-24 h-24 lg:w-32 lg:h-32 bg-base-300 flex items-center justify-center text-5xl shrink-0">
            🏒
          </div>

          <%!-- Info --%>
          <div class="flex-1">
            <div class="flex items-center gap-3 mb-2">
              <h1 class="text-2xl lg:text-3xl font-bold">{@player.name}</h1>
              <span class="text-xs bg-primary/20 text-primary px-2 py-0.5 font-mono">
                {@player.position}
              </span>
            </div>
            <p class="text-base-content/60 mb-4">{@player.team}</p>

            <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
              <div>
                <span class="text-base-content/50">Born</span>
                <div class="font-medium">{@player[:birth_date] || @player.birth_date}</div>
              </div>
              <div>
                <span class="text-base-content/50">Birthplace</span>
                <div class="font-medium">{@player.birth_place}</div>
              </div>
              <div>
                <span class="text-base-content/50">Height</span>
                <div class="font-medium">{@player.height}</div>
              </div>
              <div>
                <span class="text-base-content/50">Shoots</span>
                <div class="font-medium">{@player.shoots}</div>
              </div>
            </div>

            <div :if={@player[:draft]} class="mt-3 text-xs">
              <span class="text-base-content/50">Draft:</span>
              <span class="font-medium ml-1">{@player.draft}</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Current Season Stats --%>
      <section>
        <.section_header title="Current Season" />
        <div class="text-xs text-base-content/50 -mt-2 mb-3">
          {@current_season.season} · {@current_season.team} · {@current_season.league}
        </div>

        <div class="grid grid-cols-3 sm:grid-cols-6 gap-2">
          <.stat_box label="GP" value={@current_season.games_played} />
          <.stat_box label="G" value={@current_season.goals} />
          <.stat_box label="A" value={@current_season.assists} />
          <.stat_box label="PTS" value={@current_season.points} class="bg-primary/10 border-primary/30" />
          <.stat_box label="PIM" value={@current_season.penalty_minutes} />
          <.stat_box label="+/-" value={format_plus_minus(@current_season.plus_minus)} />
        </div>
      </section>

      <%!-- Career Stats --%>
      <section>
        <div class="data-card">
          <%!-- Header with totals --%>
          <div class="flex items-center justify-between px-3 py-2 border-b border-base-300 bg-base-200/50">
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold uppercase tracking-wider">Career</span>
              <span class="text-xs text-base-content/50">({length(@career_stats)} seasons)</span>
            </div>
            <div class="flex items-center gap-3 text-xs font-mono">
              <span class="text-base-content/50">{career_total(@career_stats, :games_played)} GP</span>
              <span>{career_total(@career_stats, :goals)} G</span>
              <span>{career_total(@career_stats, :assists)} A</span>
              <span class="font-bold text-primary">{career_total(@career_stats, :points)} PTS</span>
              <span class="text-base-content/50">{points_per_game(@career_stats)} PPG</span>
            </div>
          </div>
          <%!-- Column labels --%>
          <div class="flex items-center justify-between px-3 py-1 border-b border-base-300/50 text-[10px] uppercase tracking-wider text-base-content/40">
            <div class="flex items-center gap-2 flex-1">
              <span class="w-14">Season</span>
              <span>Team</span>
            </div>
            <div class="flex items-center gap-1 font-mono">
              <span class="w-6 text-center">GP</span>
              <span class="w-6 text-center">G</span>
              <span class="w-6 text-center">A</span>
              <span class="w-7 text-center">PTS</span>
              <span class="w-7 text-center">+/-</span>
            </div>
          </div>
          <%!-- Stats rows --%>
          <.stats_table stats={@career_stats} />
        </div>
      </section>

      <%!-- Team Info --%>
      <section>
        <.section_header title="Current Team" />
        <div class="data-card p-4">
          <div class="flex items-center gap-4 mb-4">
            <div class="w-16 h-16 bg-base-300 flex items-center justify-center text-3xl">🐻‍❄️</div>
            <div>
              <h3 class="font-bold text-lg">{@team.name}</h3>
              <p class="text-sm text-base-content/60">{@team.league_full_name}</p>
            </div>
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 text-xs">
            <div>
              <span class="text-base-content/50">City</span>
              <div class="font-medium">{@team.city}, {@team.country}</div>
            </div>
            <div>
              <span class="text-base-content/50">Arena</span>
              <div class="font-medium">{@team.arena}</div>
            </div>
            <div>
              <span class="text-base-content/50">Founded</span>
              <div class="font-medium">{@team.founded}</div>
            </div>
          </div>
          <div :if={@team.achievements != []} class="mt-4 pt-4 border-t border-base-300">
            <div class="text-[10px] uppercase tracking-wider text-base-content/50 mb-2">Achievements</div>
            <div class="flex flex-wrap gap-2">
              <span :for={a <- @team.achievements} class="stat-badge">{a}</span>
            </div>
          </div>
        </div>
      </section>

      <%!-- Last Updated --%>
      <div :if={@last_updated} class="text-center text-xs text-base-content/40">
        Updated: {format_datetime(@last_updated)}
      </div>
    </div>
    """
  end

  defp format_plus_minus(value) when is_integer(value) and value > 0, do: "+#{value}"
  defp format_plus_minus(value) when is_integer(value), do: "#{value}"
  defp format_plus_minus(_), do: "0"

  defp career_total(stats, key) do
    Enum.reduce(stats, 0, fn season, acc ->
      acc + (Map.get(season, key) || 0)
    end)
  end

  defp points_per_game(stats) do
    total_games = career_total(stats, :games_played)
    total_points = career_total(stats, :points)
    if total_games > 0, do: Float.round(total_points / total_games, 2), else: 0.0
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %H:%M UTC")
  end
end
