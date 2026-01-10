defmodule YoganHockeyWeb.HockeyComponents do
  @moduledoc """
  ESPN-style hockey UI components.
  """
  use YoganHockeyWeb, :html

  # ============================================
  # SCOREBOARD TICKER
  # ============================================

  @doc """
  Renders a horizontal scrolling scoreboard ticker.
  """
  attr :games, :list, required: true
  attr :class, :string, default: ""

  def scoreboard_ticker(assigns) do
    ~H"""
    <div class={["scoreboard-ticker", @class]}>
      <%= if Enum.empty?(@games) do %>
        <div class="ticker-game opacity-50">
          <div class="text-center text-xs">No games today</div>
        </div>
      <% else %>
        <.ticker_game :for={game <- @games} game={game} />
      <% end %>
    </div>
    """
  end

  attr :game, :map, required: true

  defp ticker_game(assigns) do
    ~H"""
    <.link navigate={~p"/nhl/live"} class={ticker_game_class(@game)}>
      <div class="ticker-team">
        <div class="ticker-team-info">
          <img :if={@game.away_team.logo} src={@game.away_team.logo} class="ticker-logo" />
          <span class="ticker-abbrev">{@game.away_team.abbreviation}</span>
        </div>
        <span class={["ticker-score", @game.away_team.winner && "winner"]}>
          {@game.away_team.score || "-"}
        </span>
      </div>
      <div class="ticker-team mt-1">
        <div class="ticker-team-info">
          <img :if={@game.home_team.logo} src={@game.home_team.logo} class="ticker-logo" />
          <span class="ticker-abbrev">{@game.home_team.abbreviation}</span>
        </div>
        <span class={["ticker-score", @game.home_team.winner && "winner"]}>
          {@game.home_team.score || "-"}
        </span>
      </div>
      <div class={ticker_status_class(@game)}>
        {ticker_status_text(@game)}
      </div>
    </.link>
    """
  end

  defp ticker_game_class(game) do
    base = "ticker-game"
    cond do
      game.status.state == "in" -> "#{base} live"
      game.status.completed -> "#{base} final"
      true -> base
    end
  end

  defp ticker_status_class(game) do
    if game.status.state == "in", do: "ticker-status live", else: "ticker-status"
  end

  defp ticker_status_text(game) do
    cond do
      game.status.state == "in" ->
        "#{period_display(game.status.period)} #{game.status.display_clock || ""}"
      game.status.completed -> "Final"
      true -> game.status.detail || ""
    end
  end

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
          <span class="text-base-content/60">{get_stat(entry.stats, "wins")}-{get_stat(entry.stats, "losses")}-{get_stat(entry.stats, "otLosses")}</span>
          <span class="font-bold w-6 text-right">{get_stat(entry.stats, "points")}</span>
        </div>
      </.link>
    </div>
    """
  end

  # ============================================
  # FEATURED PLAYER CARD
  # ============================================

  @doc """
  Renders a featured player card for Andrew Yogan.
  """
  attr :player, :map, required: true
  attr :stats, :map, required: true
  attr :class, :string, default: ""

  def featured_player(assigns) do
    ppg = if assigns.stats.games_played > 0 do
      Float.round(assigns.stats.points / assigns.stats.games_played, 2)
    else
      0.0
    end
    assigns = assign(assigns, ppg: ppg)

    ~H"""
    <.link navigate={~p"/yogan"} class="block group">
      <div class={["featured-card p-4 hover:border-primary/50 transition-all", @class]}>
        <span class="featured-badge">Featured</span>
        <div class="relative z-10">
          <div class="flex items-center gap-4">
            <%!-- Player Avatar --%>
            <div class="w-16 h-16 sm:w-20 sm:h-20 bg-base-300 flex items-center justify-center text-3xl shrink-0">
              <span>🏒</span>
            </div>
            <%!-- Player Info --%>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <h3 class="font-bold text-lg sm:text-xl truncate">{@player.name}</h3>
                <span class="text-xs bg-primary/20 text-primary px-1.5 py-0.5 font-mono">
                  {@player.position}
                </span>
              </div>
              <p class="text-sm text-base-content/60 truncate">{@player.team}</p>
              <p class="text-xs text-base-content/40 mt-0.5">{@stats.league} · {@stats.season}</p>
            </div>
          </div>
          <%!-- Stats Grid --%>
          <div class="featured-stats">
            <div class="featured-stat">
              <div class="featured-stat-value">{@stats.games_played}</div>
              <div class="featured-stat-label">GP</div>
            </div>
            <div class="featured-stat">
              <div class="featured-stat-value text-primary">{@stats.goals}</div>
              <div class="featured-stat-label">G</div>
            </div>
            <div class="featured-stat">
              <div class="featured-stat-value text-primary">{@stats.assists}</div>
              <div class="featured-stat-label">A</div>
            </div>
            <div class="featured-stat">
              <div class="featured-stat-value text-accent">{@stats.points}</div>
              <div class="featured-stat-label">PTS</div>
            </div>
            <div class="featured-stat">
              <div class={["featured-stat-value", plus_minus_class(@stats.plus_minus)]}>
                {format_plus_minus(@stats.plus_minus)}
              </div>
              <div class="featured-stat-label">+/-</div>
            </div>
            <div class="featured-stat">
              <div class="featured-stat-value">{@ppg}</div>
              <div class="featured-stat-label">PPG</div>
            </div>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  # ============================================
  # GAME CARD (ESPN-Style)
  # ============================================

  @doc """
  Renders an ESPN-style game card.
  """
  attr :game, :map, required: true
  attr :class, :string, default: ""

  def game_card(assigns) do
    ~H"""
    <div class={[game_card_class(@game), @class]}>
      <div class="game-card-header">
        <span :if={@game.status.state == "in"} class="live-indicator">Live</span>
        <span :if={@game.status.completed} class="text-base-content/50">Final</span>
        <span :if={@game.status.state == "pre"} class="text-base-content/50">{@game.status.detail}</span>
        <span :if={@game.broadcasts != []} class="text-base-content/40">
          {Enum.join(@game.broadcasts, ", ")}
        </span>
      </div>
      <div class="game-card-body">
        <%!-- Away Team --%>
        <div class="game-team-row">
          <div class="game-team-info">
            <img :if={@game.away_team.logo} src={@game.away_team.logo} class="game-team-logo" />
            <span class="game-team-name">{@game.away_team.abbreviation}</span>
            <span :if={@game.away_team.records} class="game-team-record">
              {get_record(@game.away_team.records)}
            </span>
          </div>
          <span class={["game-score", @game.away_team.winner && "winner"]}>
            {@game.away_team.score || "-"}
          </span>
        </div>
        <%!-- Home Team --%>
        <div class="game-team-row">
          <div class="game-team-info">
            <img :if={@game.home_team.logo} src={@game.home_team.logo} class="game-team-logo" />
            <span class="game-team-name">{@game.home_team.abbreviation}</span>
            <span :if={@game.home_team.records} class="game-team-record">
              {get_record(@game.home_team.records)}
            </span>
          </div>
          <span class={["game-score", @game.home_team.winner && "winner"]}>
            {@game.home_team.score || "-"}
          </span>
        </div>
      </div>
      <div :if={@game.status.state == "in"} class="game-status live">
        {period_display(@game.status.period)} - {@game.status.display_clock || ""}
      </div>
      <div :if={@game.venue} class="game-status">
        {@game.venue.name}
      </div>
    </div>
    """
  end

  defp game_card_class(game) do
    if game.status.state == "in", do: "game-card live", else: "game-card"
  end

  defp get_record(records) when is_map(records) do
    Map.get(records, "total", "")
  end
  defp get_record(_), do: ""

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

  # ============================================
  # STATS TABLE (Career Stats - Compact Rows)
  # ============================================

  @doc """
  Renders a player career stats table with compact rows.
  """
  attr :stats, :list, required: true
  attr :class, :string, default: ""

  def stats_table(assigns) do
    ~H"""
    <div class={["divide-y divide-base-300/50", @class]}>
      <div
        :for={season <- @stats}
        class="flex items-center justify-between px-3 py-1.5 hover:bg-base-300/30 transition-colors"
      >
        <%!-- Left: Season, Team, League --%>
        <div class="flex items-center gap-2 min-w-0 flex-1">
          <span class="text-xs font-mono text-base-content/50 w-14 shrink-0">{season.season}</span>
          <span class="text-xs font-medium truncate">{season.team}</span>
          <span class="text-[10px] text-base-content/40 shrink-0">({season.league})</span>
        </div>
        <%!-- Right: Stats --%>
        <div class="flex items-center gap-1 text-xs font-mono shrink-0">
          <span class="w-6 text-center text-base-content/50">{season.games_played}</span>
          <span class="w-6 text-center">{season.goals}</span>
          <span class="w-6 text-center">{season.assists}</span>
          <span class="w-7 text-center font-bold text-primary">{season.points}</span>
          <span class={["w-7 text-center", plus_minus_class(season.plus_minus)]}>
            {format_plus_minus(season.plus_minus)}
          </span>
        </div>
      </div>
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
            <span class="w-16 text-center">{get_stat(entry.stats, "wins")}-{get_stat(entry.stats, "losses")}-{get_stat(entry.stats, "otLosses")}</span>
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
  # UTILITY COMPONENTS
  # ============================================

  @doc """
  Renders a section header.
  """
  attr :title, :string, required: true
  attr :link_text, :string, default: nil
  attr :link_to, :string, default: nil

  def section_header(assigns) do
    ~H"""
    <div class="section-header">
      <span class="section-title">{@title}</span>
      <.link :if={@link_to} navigate={@link_to} class="section-link">{@link_text}</.link>
    </div>
    """
  end

  @doc """
  Renders a loading skeleton.
  """
  attr :class, :string, default: ""

  def loading_skeleton(assigns) do
    ~H"""
    <div class={["loading-skeleton h-24", @class]}></div>
    """
  end

  @doc """
  Renders a stat box.
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :string, default: ""

  def stat_box(assigns) do
    ~H"""
    <div class={["text-center p-3 bg-base-200 border border-base-300", @class]}>
      <div class="text-2xl font-mono font-bold">{@value}</div>
      <div class="text-[10px] uppercase tracking-wider text-base-content/50 mt-1">{@label}</div>
    </div>
    """
  end

  # ============================================
  # HELPER FUNCTIONS
  # ============================================

  defp period_display(1), do: "1st"
  defp period_display(2), do: "2nd"
  defp period_display(3), do: "3rd"
  defp period_display(4), do: "OT"
  defp period_display(5), do: "SO"
  defp period_display(n) when is_integer(n) and n > 5, do: "#{n - 3}OT"
  defp period_display(_), do: ""

  defp plus_minus_class(value) when is_integer(value) and value > 0, do: "text-success"
  defp plus_minus_class(value) when is_integer(value) and value < 0, do: "text-error"
  defp plus_minus_class(_), do: ""

  defp format_plus_minus(value) when is_integer(value) and value > 0, do: "+#{value}"
  defp format_plus_minus(value) when is_integer(value), do: "#{value}"
  defp format_plus_minus(_), do: "0"

  defp get_stat(stats, key) when is_map(stats) do
    case Map.get(stats, key) do
      nil -> "-"
      value when is_float(value) -> round(value)
      value -> value
    end
  end
  defp get_stat(_, _), do: "-"
end
