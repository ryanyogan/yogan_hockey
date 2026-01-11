defmodule YoganHockeyWeb.StandingsComponents do
  @moduledoc """
  Components for displaying NHL standings, team grids, and team-related information.
  """
  use YoganHockeyWeb, :html

  import YoganHockeyWeb.Helpers.StatsHelpers, only: [get_stat: 2]

  # ============================================
  # STANDINGS WIDGET
  # ============================================

  @doc """
  Renders a compact standings widget with conference leaders.
  """
  attr :standings, :list, required: true
  attr :class, :string, default: ""

  def standings_widget(assigns) do
    # Group by conference and get top teams from each
    conferences =
      assigns.standings
      |> Enum.group_by(& &1.conference)
      |> Enum.map(fn {conf, teams} ->
        sorted = Enum.sort_by(teams, fn t -> -(get_stat(t.stats, "points") || 0) end)
        {conf, Enum.take(sorted, 8)}
      end)
      |> Enum.sort_by(fn {conf, _} -> conf end)

    assigns = assign(assigns, conferences: conferences)

    ~H"""
    <div class={["data-card", @class]}>
      <div class="data-card-header">
        <span class="data-card-title">Standings</span>
        <.link navigate={~p"/nhl"} class="section-link">Full Standings</.link>
      </div>
      <div class="data-card-body">
        <div class="divide-y divide-base-300">
          <div :for={{conference, teams} <- @conferences}>
            <div class="px-3 py-1.5 bg-base-300/30 text-[10px] font-bold uppercase tracking-wider">
              {conference}
            </div>
            <.standings_mini_table teams={teams} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :teams, :list, required: true

  defp standings_mini_table(assigns) do
    ~H"""
    <div class="divide-y divide-base-300/50">
      <.link
        :for={{entry, idx} <- Enum.with_index(@teams, 1)}
        navigate={~p"/nhl/teams/#{entry.team.id}"}
        class="flex items-center justify-between px-3 py-1.5 hover:bg-base-300/30 transition-colors"
      >
        <div class="flex items-center gap-2">
          <span class="w-4 text-[10px] text-base-content/40 font-mono">{idx}</span>
          <img :if={entry.team.logo} src={entry.team.logo} class="w-4 h-4 object-contain" />
          <span class="text-xs font-medium">{entry.team.abbreviation}</span>
        </div>
        <div class="flex items-center gap-3 text-xs font-mono">
          <span class="text-base-content/60">
            {get_stat(entry.stats, "wins")}-{get_stat(entry.stats, "losses")}-{get_stat(entry.stats, "otLosses")}
          </span>
          <span class="font-bold w-6 text-right">{get_stat(entry.stats, "points")}</span>
        </div>
      </.link>
    </div>
    """
  end

  # ============================================
  # FULL STANDINGS TABLE
  # ============================================

  @doc """
  Renders a full conference standings table.
  """
  attr :division, :string, required: true
  attr :teams, :list, required: true
  attr :class, :string, default: ""

  def standings_table(assigns) do
    ~H"""
    <div class={["data-card", @class]}>
      <div class="data-card-header">
        <span class="data-card-title">{@division}</span>
      </div>
      <div class="divide-y divide-base-300/50">
        <.link
          :for={{entry, idx} <- Enum.with_index(@teams, 1)}
          navigate={~p"/nhl/teams/#{entry.team.id}"}
          class="flex items-center justify-between px-3 py-2 hover:bg-base-300/30 transition-colors"
        >
          <div class="flex items-center gap-2">
            <span class="w-5 text-xs text-base-content/40 font-mono">{idx}</span>
            <img :if={entry.team.logo} src={entry.team.logo} class="w-5 h-5 object-contain" />
            <span class="text-sm font-medium">{entry.team.abbreviation}</span>
          </div>
          <div class="flex items-center gap-4 text-xs font-mono">
            <span class="text-base-content/50 w-8">{get_stat(entry.stats, "gamesPlayed")} GP</span>
            <span class="w-16 text-center">
              {get_stat(entry.stats, "wins")}-{get_stat(entry.stats, "losses")}-{get_stat(entry.stats, "otLosses")}
            </span>
            <span class={["w-10 text-center", diff_class(entry.stats)]}>{goal_diff(entry.stats)}</span>
            <span class="font-bold text-primary w-8 text-right">{get_stat(entry.stats, "points")}</span>
          </div>
        </.link>
      </div>
    </div>
    """
  end

  defp goal_diff(stats) do
    gf = get_stat(stats, "goalsFor")
    ga = get_stat(stats, "goalsAgainst")

    if is_number(gf) and is_number(ga) do
      diff = gf - ga
      if diff > 0, do: "+#{diff}", else: "#{diff}"
    else
      "-"
    end
  end

  defp diff_class(stats) do
    gf = get_stat(stats, "goalsFor")
    ga = get_stat(stats, "goalsAgainst")

    if is_number(gf) and is_number(ga) do
      cond do
        gf > ga -> "text-success"
        gf < ga -> "text-error"
        true -> ""
      end
    else
      ""
    end
  end

  # ============================================
  # TEAM GRID
  # ============================================

  @doc """
  Renders a compact team grid.
  """
  attr :teams, :list, required: true
  attr :class, :string, default: ""

  def team_grid(assigns) do
    ~H"""
    <div class={["team-grid", @class]}>
      <.team_tile :for={team <- @teams} team={team} />
    </div>
    """
  end

  attr :team, :map, required: true

  defp team_tile(assigns) do
    ~H"""
    <.link navigate={~p"/nhl/teams/#{@team.id}"} class="team-tile">
      <img :if={@team.logo} src={@team.logo} class="team-tile-logo" />
      <span class="team-tile-abbrev">{@team.abbreviation}</span>
    </.link>
    """
  end
end
