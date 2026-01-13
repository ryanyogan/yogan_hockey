defmodule YoganHockeyWeb.GamePlayComponents do
  @moduledoc """
  Components for the live game play page including ice rink SVG,
  play-by-play stream, and game statistics.
  """
  use Phoenix.Component

  @doc """
  Game header with teams, scores, and game status.
  """
  attr :home_team, :map, required: true
  attr :away_team, :map, required: true
  attr :status, :map, required: true

  def game_header(assigns) do
    ~H"""
    <div class="game-header featured-card p-4">
      <div class="flex items-center justify-between">
        <%!-- Away Team --%>
        <div class="flex-1 flex items-center gap-3">
          <div
            class="w-12 h-12 sm:w-16 sm:h-16 rounded-lg flex items-center justify-center"
            style={"background-color: ##{@away_team.color || "333"}20"}
          >
            <img
              :if={@away_team.logo}
              src={@away_team.logo}
              alt={@away_team.name}
              class="w-10 h-10 sm:w-12 sm:h-12 object-contain"
            />
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wider">Away</div>
            <div class="font-bold text-lg sm:text-xl">{@away_team.abbreviation}</div>
            <div class="text-xs text-base-content/60 hidden sm:block">{@away_team.name}</div>
          </div>
        </div>

        <%!-- Score & Status --%>
        <div class="text-center px-4">
          <div class="flex items-center gap-3 sm:gap-6">
            <span class="text-3xl sm:text-5xl font-bold font-mono">{@away_team.score}</span>
            <span class="text-base-content/30 text-xl">-</span>
            <span class="text-3xl sm:text-5xl font-bold font-mono">{@home_team.score}</span>
          </div>
          <.game_status status={@status} />
        </div>

        <%!-- Home Team --%>
        <div class="flex-1 flex items-center gap-3 justify-end">
          <div class="text-right">
            <div class="text-xs text-base-content/50 uppercase tracking-wider">Home</div>
            <div class="font-bold text-lg sm:text-xl">{@home_team.abbreviation}</div>
            <div class="text-xs text-base-content/60 hidden sm:block">{@home_team.name}</div>
          </div>
          <div
            class="w-12 h-12 sm:w-16 sm:h-16 rounded-lg flex items-center justify-center"
            style={"background-color: ##{@home_team.color || "333"}20"}
          >
            <img
              :if={@home_team.logo}
              src={@home_team.logo}
              alt={@home_team.name}
              class="w-10 h-10 sm:w-12 sm:h-12 object-contain"
            />
          </div>
        </div>
      </div>

      <%!-- Quick Stats Row --%>
      <div class="flex justify-center gap-6 sm:gap-12 mt-4 pt-4 border-t border-base-300/50 text-xs">
        <div class="text-center">
          <div class="font-mono font-bold">{Map.get(@away_team, :shots) || 0}</div>
          <div class="text-base-content/50">SOG</div>
        </div>
        <div class="text-center">
          <div class="font-mono font-bold">{Map.get(@home_team, :shots) || 0}</div>
        </div>
        <div class="text-center">
          <div class="font-mono font-bold">{Map.get(@away_team, :hits) || 0}</div>
          <div class="text-base-content/50">HITS</div>
        </div>
        <div class="text-center">
          <div class="font-mono font-bold">{Map.get(@home_team, :hits) || 0}</div>
        </div>
        <div class="text-center">
          <div class="font-mono font-bold">{Map.get(@away_team, :faceoff_pct) || "—"}</div>
          <div class="text-base-content/50">FO%</div>
        </div>
        <div class="text-center">
          <div class="font-mono font-bold">{Map.get(@home_team, :faceoff_pct) || "—"}</div>
        </div>
      </div>
    </div>
    """
  end

  defp game_status(assigns) do
    ~H"""
    <div class="mt-1">
      <%= case @status.state do %>
        <% "pre" -> %>
          <span class="text-xs bg-base-200 px-2 py-1 rounded">PREGAME</span>
        <% "in" -> %>
          <div class="flex items-center justify-center gap-2">
            <span class="live-indicator"></span>
            <span class="text-xs font-bold text-success">
              {period_label(@status.period)} · {@status.clock}
            </span>
          </div>
        <% "post" -> %>
          <span class="text-xs bg-base-200 px-2 py-1 rounded">FINAL</span>
        <% _ -> %>
          <span class="text-xs text-base-content/50">{@status.state}</span>
      <% end %>
    </div>
    """
  end

  defp period_label(1), do: "1st"
  defp period_label(2), do: "2nd"
  defp period_label(3), do: "3rd"
  defp period_label(4), do: "OT"
  defp period_label(5), do: "SO"
  defp period_label(n) when n > 5, do: "#{n - 3}OT"
  defp period_label(_), do: "—"

  @doc """
  Ice rink SVG with play markers.
  """
  attr :plays, :list, default: []
  attr :home_team, :map, required: true
  attr :away_team, :map, required: true

  def ice_rink(assigns) do
    ~H"""
    <div class="data-card p-3">
      <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-2">
        Ice Rink
      </div>
      <div class="ice-rink-container aspect-[200/85] w-full">
        <svg viewBox="0 0 200 85" class="w-full h-full" preserveAspectRatio="xMidYMid meet">
          <%!-- Ice surface with rounded corners (boards) --%>
          <rect x="0" y="0" width="200" height="85" rx="28" ry="28" fill="#f8fafc" stroke="#94a3b8" stroke-width="0.5" />

          <%!-- Center line (red) --%>
          <line x1="100" y1="0" x2="100" y2="85" stroke="#ef4444" stroke-width="1" />

          <%!-- Blue lines --%>
          <line x1="75" y1="0" x2="75" y2="85" stroke="#3b82f6" stroke-width="1" />
          <line x1="125" y1="0" x2="125" y2="85" stroke="#3b82f6" stroke-width="1" />

          <%!-- Goal lines --%>
          <line x1="11" y1="15" x2="11" y2="70" stroke="#ef4444" stroke-width="0.5" />
          <line x1="189" y1="15" x2="189" y2="70" stroke="#ef4444" stroke-width="0.5" />

          <%!-- Center circle --%>
          <circle cx="100" cy="42.5" r="15" fill="none" stroke="#3b82f6" stroke-width="0.5" />
          <circle cx="100" cy="42.5" r="1" fill="#3b82f6" />

          <%!-- Center ice faceoff dots --%>
          <circle cx="80" cy="42.5" r="1" fill="#ef4444" />
          <circle cx="120" cy="42.5" r="1" fill="#ef4444" />

          <%!-- Offensive zone faceoff circles (left) --%>
          <circle cx="31" cy="21" r="15" fill="none" stroke="#ef4444" stroke-width="0.5" />
          <circle cx="31" cy="21" r="1" fill="#ef4444" />
          <circle cx="31" cy="64" r="15" fill="none" stroke="#ef4444" stroke-width="0.5" />
          <circle cx="31" cy="64" r="1" fill="#ef4444" />

          <%!-- Offensive zone faceoff circles (right) --%>
          <circle cx="169" cy="21" r="15" fill="none" stroke="#ef4444" stroke-width="0.5" />
          <circle cx="169" cy="21" r="1" fill="#ef4444" />
          <circle cx="169" cy="64" r="15" fill="none" stroke="#ef4444" stroke-width="0.5" />
          <circle cx="169" cy="64" r="1" fill="#ef4444" />

          <%!-- Goal creases --%>
          <path d="M 11 36 L 17 36 A 6 6 0 0 1 17 49 L 11 49" fill="#93c5fd" fill-opacity="0.3" stroke="#3b82f6" stroke-width="0.5" />
          <path d="M 189 36 L 183 36 A 6 6 0 0 0 183 49 L 189 49" fill="#93c5fd" fill-opacity="0.3" stroke="#3b82f6" stroke-width="0.5" />

          <%!-- Goals --%>
          <rect x="6" y="38" width="5" height="9" fill="none" stroke="#6b7280" stroke-width="0.5" />
          <rect x="189" y="38" width="5" height="9" fill="none" stroke="#6b7280" stroke-width="0.5" />

          <%!-- Play markers --%>
          <%= for play <- @plays do %>
            <.play_marker play={play} home_team={@home_team} away_team={@away_team} />
          <% end %>
        </svg>
      </div>

      <%!-- Legend --%>
      <div class="flex items-center justify-center gap-4 mt-3 text-[10px] text-base-content/60">
        <div class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-full bg-green-500"></span>
          <span>Goal</span>
        </div>
        <div class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-full bg-blue-400"></span>
          <span>Shot</span>
        </div>
        <div class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-full bg-amber-500"></span>
          <span>Penalty</span>
        </div>
        <div class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-full bg-red-500"></span>
          <span>Hit</span>
        </div>
      </div>
    </div>
    """
  end

  defp play_marker(assigns) do
    color = play_color(assigns.play.type)
    opacity = play_opacity(assigns.play.type)
    size = play_size(assigns.play.type)

    team_color =
      if assigns.play.team_id == assigns.home_team.id do
        assigns.home_team.color
      else
        assigns.away_team.color
      end

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:opacity, opacity)
      |> assign(:size, size)
      |> assign(:team_color, team_color)

    ~H"""
    <circle
      :if={@play.x && @play.y}
      cx={@play.x}
      cy={@play.y}
      r={@size}
      fill={@color}
      fill-opacity={@opacity}
      stroke={"##{@team_color || "333"}"}
      stroke-width="0.5"
      class="play-marker"
    >
      <title>{@play.description}</title>
    </circle>
    """
  end

  defp play_color(:goal), do: "#22c55e"
  defp play_color(:shot), do: "#60a5fa"
  defp play_color(:penalty), do: "#f59e0b"
  defp play_color(:hit), do: "#ef4444"
  defp play_color(:faceoff), do: "#a855f7"
  defp play_color(_), do: "#6b7280"

  defp play_opacity(:goal), do: "0.9"
  defp play_opacity(_), do: "0.6"

  defp play_size(:goal), do: "4"
  defp play_size(:hit), do: "2.5"
  defp play_size(_), do: "2"

  @doc """
  Play type and period filter buttons.
  """
  attr :play_filter, :atom, required: true
  attr :period_filter, :any, required: true
  attr :current_period, :integer, default: 1
  attr :plays, :list, default: []

  def play_filters(assigns) do
    # Get periods that actually have plays (ESPN API only returns ~100 plays, so later periods may be missing)
    periods_with_data =
      assigns.plays
      |> Enum.map(& &1[:period])
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()
      |> Enum.sort()

    assigns = assign(assigns, :periods_with_data, periods_with_data)

    ~H"""
    <div class="data-card p-3">
      <div class="flex flex-wrap gap-2 justify-between">
        <%!-- Play type filters --%>
        <div class="flex flex-wrap gap-1">
          <.filter_button label="All" value="all" active={@play_filter == :all} event="filter_plays" param="type" />
          <.filter_button label="Goals" value="goal" active={@play_filter == :goal} event="filter_plays" param="type" />
          <.filter_button label="Shots" value="shot" active={@play_filter == :shot} event="filter_plays" param="type" />
          <.filter_button label="Penalties" value="penalty" active={@play_filter == :penalty} event="filter_plays" param="type" />
          <.filter_button label="Hits" value="hit" active={@play_filter == :hit} event="filter_plays" param="type" />
        </div>

        <%!-- Period filters - only show periods that have plays --%>
        <div class="flex flex-wrap gap-1">
          <.filter_button label="All" value="all" active={@period_filter == :all} event="filter_period" param="period" />
          <%= for p <- @periods_with_data do %>
            <.filter_button label={period_label(p)} value={to_string(p)} active={@period_filter == p} event="filter_period" param="period" />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp filter_button(assigns) do
    ~H"""
    <button
      phx-click={@event}
      phx-value-type={if @param == "type", do: @value}
      phx-value-period={if @param == "period", do: @value}
      class={"px-3 py-1.5 text-xs font-medium transition-colors cursor-pointer min-h-[44px] min-w-[44px] flex items-center justify-center " <>
        if @active do
          "bg-primary text-primary-content"
        else
          "bg-base-200 text-base-content/70 hover:bg-base-300"
        end}
    >
      {@label}
    </button>
    """
  end

  @doc """
  Side-by-side team stats comparison.
  """
  attr :home_team, :map, required: true
  attr :away_team, :map, required: true

  def team_stats_comparison(assigns) do
    ~H"""
    <div class="data-card p-3">
      <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-3">
        Team Stats
      </div>

      <div class="space-y-2">
        <.stat_row label="Shots" away={get_stat(@away_team, :shots)} home={get_stat(@home_team, :shots)} />
        <.stat_row label="Hits" away={get_stat(@away_team, :hits)} home={get_stat(@home_team, :hits)} />
        <.stat_row label="Blocked" away={get_stat(@away_team, :blocked)} home={get_stat(@home_team, :blocked)} />
        <.stat_row label="Giveaways" away={get_stat(@away_team, :giveaways)} home={get_stat(@home_team, :giveaways)} />
        <.stat_row label="Takeaways" away={get_stat(@away_team, :takeaways)} home={get_stat(@home_team, :takeaways)} />
        <.stat_row label="PIM" away={get_stat(@away_team, :penalty_minutes)} home={get_stat(@home_team, :penalty_minutes)} />
        <.stat_row label="PP" away={format_powerplay(@away_team)} home={format_powerplay(@home_team)} />
        <.stat_row label="FO%" away={get_stat(@away_team, :faceoff_pct, "—")} home={get_stat(@home_team, :faceoff_pct, "—")} />
      </div>
    </div>
    """
  end

  # Safely get a stat value from a team map, with default
  defp get_stat(team, key, default \\ 0) do
    Map.get(team, key) || default
  end

  defp stat_row(assigns) do
    ~H"""
    <div class="flex items-center text-xs">
      <div class="w-12 text-right font-mono">{@away}</div>
      <div class="flex-1 text-center text-base-content/50">{@label}</div>
      <div class="w-12 text-left font-mono">{@home}</div>
    </div>
    """
  end

  defp format_powerplay(team) do
    goals = Map.get(team, :powerplay_goals)
    opps = Map.get(team, :powerplay_opportunities)

    cond do
      is_number(goals) and is_number(opps) ->
        "#{trunc(goals)}/#{trunc(opps)}"
      is_binary(Map.get(team, :power_play)) ->
        team.power_play
      true ->
        "—"
    end
  end

  @doc """
  Scrollable play-by-play stream.
  """
  attr :plays, :list, default: []
  attr :home_team, :map, required: true
  attr :away_team, :map, required: true

  def play_by_play_stream(assigns) do
    # Reverse plays so newest appear first for live game experience
    plays = Enum.reverse(assigns.plays || [])
    assigns = assign(assigns, :reversed_plays, plays)

    ~H"""
    <div class="data-card p-3">
      <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-3">
        Play-by-Play
      </div>

      <div class="space-y-2 max-h-96 overflow-y-auto">
        <%= if @reversed_plays == [] do %>
          <div class="text-xs text-base-content/50 text-center py-4">
            No plays yet
          </div>
        <% else %>
          <%= for play <- Enum.take(@reversed_plays, 50) do %>
            <.play_item play={play} home_team={@home_team} away_team={@away_team} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp play_item(assigns) do
    team =
      if assigns.play.team_id == assigns.home_team.id do
        assigns.home_team
      else
        assigns.away_team
      end

    assigns = assign(assigns, :team, team)

    ~H"""
    <div class={"flex items-start gap-2 p-2 rounded text-xs " <> play_item_bg(@play.type)}>
      <div class="flex-shrink-0 flex flex-col items-center">
        <span class={"w-2 h-2 rounded-full " <> play_dot_class(@play.type)}></span>
        <span class="text-[10px] text-base-content/40 mt-0.5">{period_label(@play.period)}</span>
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-1.5 mb-0.5">
          <span class="font-bold" style={"color: ##{@team.color || "333"}"}>{@team.abbreviation}</span>
          <span class="text-base-content/40">{@play.time}</span>
        </div>
        <p class="text-base-content/70 break-words">{@play.description}</p>
      </div>
    </div>
    """
  end

  defp play_item_bg(:goal), do: "bg-green-500/10"
  defp play_item_bg(:penalty), do: "bg-amber-500/10"
  defp play_item_bg(_), do: "bg-base-200/50"

  defp play_dot_class(:goal), do: "bg-green-500"
  defp play_dot_class(:shot), do: "bg-blue-400"
  defp play_dot_class(:penalty), do: "bg-amber-500"
  defp play_dot_class(:hit), do: "bg-red-500"
  defp play_dot_class(:faceoff), do: "bg-purple-500"
  defp play_dot_class(_), do: "bg-base-content/30"

  @doc """
  Period-by-period scoring summary.
  """
  attr :boxscore, :map, required: true

  def period_scoring(assigns) do
    ~H"""
    <div :if={@boxscore[:period_scores] && @boxscore.period_scores != []} class="data-card p-3">
      <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-2">
        Scoring by Period
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-xs">
          <thead>
            <tr class="text-base-content/50">
              <th class="text-left py-1"></th>
              <%= for ps <- @boxscore.period_scores do %>
                <th class="text-center px-2 py-1">{period_label(ps.period)}</th>
              <% end %>
              <th class="text-center px-2 py-1 font-bold">T</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td class="py-1 font-medium">Away</td>
              <%= for ps <- @boxscore.period_scores do %>
                <td class="text-center px-2 py-1 font-mono">{ps.away}</td>
              <% end %>
              <td class="text-center px-2 py-1 font-mono font-bold">
                {Enum.sum(Enum.map(@boxscore.period_scores, & &1.away))}
              </td>
            </tr>
            <tr>
              <td class="py-1 font-medium">Home</td>
              <%= for ps <- @boxscore.period_scores do %>
                <td class="text-center px-2 py-1 font-mono">{ps.home}</td>
              <% end %>
              <td class="text-center px-2 py-1 font-mono font-bold">
                {Enum.sum(Enum.map(@boxscore.period_scores, & &1.home))}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @doc """
  Loading state while waiting for game data.
  """
  attr :game_id, :string, required: true

  def loading_state(assigns) do
    ~H"""
    <div class="data-card p-8 text-center">
      <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-primary mb-4"></div>
      <p class="text-base-content/60 text-sm">Loading game data...</p>
      <p class="text-base-content/40 text-xs mt-1">Game ID: {@game_id}</p>
    </div>
    """
  end

  @doc """
  Game header with loading state - shows teams and current period from game_info
  while waiting for detailed game_data to load.
  """
  attr :game_info, :map, required: true

  def game_header_loading(assigns) do
    ~H"""
    <div class="game-header featured-card p-4">
      <div class="flex items-center justify-between">
        <%!-- Away Team --%>
        <div class="flex-1 flex items-center gap-3">
          <div
            class="w-12 h-12 sm:w-16 sm:h-16 rounded-lg flex items-center justify-center"
            style={"background-color: ##{@game_info.away_team.color || "333"}20"}
          >
            <img
              :if={@game_info.away_team.logo}
              src={@game_info.away_team.logo}
              alt={@game_info.away_team.name}
              class="w-10 h-10 sm:w-12 sm:h-12 object-contain"
            />
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wider">Away</div>
            <div class="font-bold text-lg sm:text-xl">{@game_info.away_team.abbreviation}</div>
            <div class="text-xs text-base-content/60 hidden sm:block">{@game_info.away_team.name}</div>
          </div>
        </div>

        <%!-- Score & Status --%>
        <div class="text-center px-4">
          <div class="flex items-center gap-3 sm:gap-6">
            <span class="text-3xl sm:text-5xl font-bold font-mono">{@game_info.away_team.score || 0}</span>
            <span class="text-base-content/30 text-xl">-</span>
            <span class="text-3xl sm:text-5xl font-bold font-mono">{@game_info.home_team.score || 0}</span>
          </div>
          <div class="mt-1">
            <div class="flex items-center justify-center gap-2">
              <span class="live-indicator"></span>
              <span class="text-xs font-bold text-success">
                {@game_info.status.detail}
              </span>
            </div>
          </div>
        </div>

        <%!-- Home Team --%>
        <div class="flex-1 flex items-center gap-3 justify-end">
          <div class="text-right">
            <div class="text-xs text-base-content/50 uppercase tracking-wider">Home</div>
            <div class="font-bold text-lg sm:text-xl">{@game_info.home_team.abbreviation}</div>
            <div class="text-xs text-base-content/60 hidden sm:block">{@game_info.home_team.name}</div>
          </div>
          <div
            class="w-12 h-12 sm:w-16 sm:h-16 rounded-lg flex items-center justify-center"
            style={"background-color: ##{@game_info.home_team.color || "333"}20"}
          >
            <img
              :if={@game_info.home_team.logo}
              src={@game_info.home_team.logo}
              alt={@game_info.home_team.name}
              class="w-10 h-10 sm:w-12 sm:h-12 object-contain"
            />
          </div>
        </div>
      </div>

      <%!-- Loading indicator for stats --%>
      <div class="flex justify-center items-center gap-2 mt-4 pt-4 border-t border-base-300/50 text-xs text-base-content/40">
        <div class="inline-block animate-spin rounded-full h-3 w-3 border-b border-primary"></div>
        <span>Loading live stats...</span>
      </div>
    </div>
    """
  end

  # ============================================
  # PREGAME COMPONENTS
  # ============================================

  @doc """
  Pregame header with teams, scheduled time, and venue info.
  """
  attr :home_team, :map, required: true
  attr :away_team, :map, required: true
  attr :status, :map, required: true
  attr :venue, :map, default: nil
  attr :broadcasts, :list, default: []

  def pregame_header(assigns) do
    ~H"""
    <div class="game-header featured-card p-4">
      <div class="flex items-center justify-between">
        <%!-- Away Team --%>
        <div class="flex-1 flex items-center gap-3">
          <div
            class="w-12 h-12 sm:w-16 sm:h-16 rounded-lg flex items-center justify-center"
            style={"background-color: ##{@away_team.color || "333"}20"}
          >
            <img
              :if={@away_team.logo}
              src={@away_team.logo}
              alt={@away_team.name}
              class="w-10 h-10 sm:w-12 sm:h-12 object-contain"
            />
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wider">Away</div>
            <div class="font-bold text-lg sm:text-xl">{@away_team.abbreviation}</div>
            <div class="text-xs text-base-content/60 hidden sm:block">{@away_team.name}</div>
            <div :if={@away_team.records} class="text-[10px] text-base-content/40 font-mono">
              {get_record(@away_team.records)}
            </div>
          </div>
        </div>

        <%!-- VS & Time --%>
        <div class="text-center px-4">
          <div class="text-2xl sm:text-3xl font-bold text-base-content/20 mb-1">VS</div>
          <div class="text-xs bg-base-200 px-3 py-1.5 rounded">
            {@status.detail || "Scheduled"}
          </div>
        </div>

        <%!-- Home Team --%>
        <div class="flex-1 flex items-center gap-3 justify-end">
          <div class="text-right">
            <div class="text-xs text-base-content/50 uppercase tracking-wider">Home</div>
            <div class="font-bold text-lg sm:text-xl">{@home_team.abbreviation}</div>
            <div class="text-xs text-base-content/60 hidden sm:block">{@home_team.name}</div>
            <div :if={@home_team.records} class="text-[10px] text-base-content/40 font-mono">
              {get_record(@home_team.records)}
            </div>
          </div>
          <div
            class="w-12 h-12 sm:w-16 sm:h-16 rounded-lg flex items-center justify-center"
            style={"background-color: ##{@home_team.color || "333"}20"}
          >
            <img
              :if={@home_team.logo}
              src={@home_team.logo}
              alt={@home_team.name}
              class="w-10 h-10 sm:w-12 sm:h-12 object-contain"
            />
          </div>
        </div>
      </div>

      <%!-- Venue & Broadcast Info --%>
      <div class="flex justify-center items-center gap-4 mt-4 pt-4 border-t border-base-300/50 text-xs text-base-content/50">
        <div :if={@venue} class="flex items-center gap-1">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <span>{@venue.name}</span>
        </div>
        <div :if={@broadcasts != []} class="flex items-center gap-1">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
          </svg>
          <span>{Enum.join(@broadcasts, ", ")}</span>
        </div>
      </div>
    </div>
    """
  end

  defp get_record(records) when is_map(records), do: Map.get(records, "total", "")
  defp get_record(_), do: ""

  @doc """
  Countdown timer until game starts - scoreboard style.
  """
  attr :countdown, :integer, default: nil
  attr :scheduled_time, :string, default: nil

  def countdown_timer(assigns) do
    countdown = assigns.countdown
    has_valid_countdown = is_integer(countdown) && countdown > 0
    formatted = format_countdown_display(countdown)

    assigns =
      assigns
      |> assign(:formatted, formatted)
      |> assign(:has_valid_countdown, has_valid_countdown)

    ~H"""
    <div class="data-card p-6 text-center">
      <%= if @has_valid_countdown do %>
        <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-4">
          Puck Drop In
        </div>
        <%!-- Scoreboard style clock --%>
        <div class="scoreboard-clock inline-flex items-center justify-center bg-base-300 px-8 py-5 rounded-lg">
          <span class="text-5xl sm:text-7xl font-mono font-bold tabular-nums">{@formatted.hours}</span>
          <span class="text-5xl sm:text-7xl font-mono font-bold text-primary mx-1 animate-pulse">:</span>
          <span class="text-5xl sm:text-7xl font-mono font-bold tabular-nums">{@formatted.minutes}</span>
          <span class="text-5xl sm:text-7xl font-mono font-bold text-primary mx-1 animate-pulse">:</span>
          <span class="text-5xl sm:text-7xl font-mono font-bold tabular-nums text-accent">{@formatted.seconds}</span>
        </div>
        <div class="text-xs text-base-content/40 mt-3 font-mono tracking-widest">
          HR : MIN : SEC
        </div>
      <% else %>
        <%!-- Game starting soon - waiting for puck drop --%>
        <div class="text-xs font-bold uppercase tracking-wider text-success mb-4 flex items-center justify-center gap-2">
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75"></span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
          </span>
          Puck Drop Imminent
        </div>
        <div class="scoreboard-clock inline-flex items-center justify-center bg-base-300 px-8 py-5 rounded-lg border-2 border-success/30">
          <span class="text-5xl sm:text-7xl font-mono font-bold tabular-nums text-success">00</span>
          <span class="text-5xl sm:text-7xl font-mono font-bold text-success mx-1 animate-pulse">:</span>
          <span class="text-5xl sm:text-7xl font-mono font-bold tabular-nums text-success">00</span>
          <span class="text-5xl sm:text-7xl font-mono font-bold text-success mx-1 animate-pulse">:</span>
          <span class="text-5xl sm:text-7xl font-mono font-bold tabular-nums text-success">00</span>
        </div>
        <div class="flex items-center justify-center gap-2 mt-4 text-sm text-base-content/60">
          <span>Scheduled: {@scheduled_time || "Now"}</span>
        </div>
        <div class="text-xs text-base-content/40 mt-2 animate-pulse">
          Checking for game start...
        </div>
      <% end %>
    </div>
    """
  end

  # Format countdown for scoreboard display (HH:MM:SS)
  defp format_countdown_display(nil), do: %{hours: "00", minutes: "00", seconds: "00"}
  defp format_countdown_display(seconds) when seconds <= 0, do: %{hours: "00", minutes: "00", seconds: "00"}

  defp format_countdown_display(total_seconds) do
    hours = div(total_seconds, 3600)
    remaining = rem(total_seconds, 3600)
    minutes = div(remaining, 60)
    seconds = rem(remaining, 60)

    %{
      hours: pad_zero(hours),
      minutes: pad_zero(minutes),
      seconds: pad_zero(seconds)
    }
  end

  defp pad_zero(n) when n < 10, do: "0#{n}"
  defp pad_zero(n), do: to_string(n)

  @doc """
  Empty ice rink placeholder for pregame.
  """
  attr :countdown, :integer, default: nil

  def ice_rink_placeholder(assigns) do
    waiting_for_start = is_nil(assigns.countdown) || assigns.countdown <= 0

    assigns = assign(assigns, :waiting_for_start, waiting_for_start)

    ~H"""
    <div class="data-card p-3">
      <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-2">
        Ice Rink
      </div>
      <div class="ice-rink-container aspect-[200/85] w-full relative">
        <svg viewBox="0 0 200 85" class="w-full h-full opacity-50" preserveAspectRatio="xMidYMid meet">
          <%!-- Ice surface with rounded corners (boards) --%>
          <rect x="0" y="0" width="200" height="85" rx="28" ry="28" fill="#f8fafc" stroke="#94a3b8" stroke-width="0.5" />

          <%!-- Center line (red) --%>
          <line x1="100" y1="0" x2="100" y2="85" stroke="#ef4444" stroke-width="1" />

          <%!-- Blue lines --%>
          <line x1="75" y1="0" x2="75" y2="85" stroke="#3b82f6" stroke-width="1" />
          <line x1="125" y1="0" x2="125" y2="85" stroke="#3b82f6" stroke-width="1" />

          <%!-- Goal lines --%>
          <line x1="11" y1="15" x2="11" y2="70" stroke="#ef4444" stroke-width="0.5" />
          <line x1="189" y1="15" x2="189" y2="70" stroke="#ef4444" stroke-width="0.5" />

          <%!-- Center circle --%>
          <circle cx="100" cy="42.5" r="15" fill="none" stroke="#3b82f6" stroke-width="0.5" />
          <circle cx="100" cy="42.5" r="1" fill="#3b82f6" />

          <%!-- Center ice faceoff dots --%>
          <circle cx="80" cy="42.5" r="1" fill="#ef4444" />
          <circle cx="120" cy="42.5" r="1" fill="#ef4444" />

          <%!-- Offensive zone faceoff circles (left) --%>
          <circle cx="31" cy="21" r="15" fill="none" stroke="#ef4444" stroke-width="0.5" />
          <circle cx="31" cy="21" r="1" fill="#ef4444" />
          <circle cx="31" cy="64" r="15" fill="none" stroke="#ef4444" stroke-width="0.5" />
          <circle cx="31" cy="64" r="1" fill="#ef4444" />

          <%!-- Offensive zone faceoff circles (right) --%>
          <circle cx="169" cy="21" r="15" fill="none" stroke="#ef4444" stroke-width="0.5" />
          <circle cx="169" cy="21" r="1" fill="#ef4444" />
          <circle cx="169" cy="64" r="15" fill="none" stroke="#ef4444" stroke-width="0.5" />
          <circle cx="169" cy="64" r="1" fill="#ef4444" />

          <%!-- Goal creases --%>
          <path d="M 11 36 L 17 36 A 6 6 0 0 1 17 49 L 11 49" fill="#93c5fd" fill-opacity="0.3" stroke="#3b82f6" stroke-width="0.5" />
          <path d="M 189 36 L 183 36 A 6 6 0 0 0 183 49 L 189 49" fill="#93c5fd" fill-opacity="0.3" stroke="#3b82f6" stroke-width="0.5" />

          <%!-- Goals --%>
          <rect x="6" y="38" width="5" height="9" fill="none" stroke="#6b7280" stroke-width="0.5" />
          <rect x="189" y="38" width="5" height="9" fill="none" stroke="#6b7280" stroke-width="0.5" />
        </svg>

        <%!-- Overlay message --%>
        <div class="absolute inset-0 flex items-center justify-center">
          <%= if @waiting_for_start do %>
            <div class="bg-base-100/95 px-5 py-3 rounded-lg text-center">
              <div class="flex items-center justify-center gap-2 text-sm text-success font-medium">
                <span class="relative flex h-2 w-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75"></span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
                </span>
                Puck drop imminent
              </div>
              <div class="text-xs text-base-content/50 mt-1">
                Live stats will appear here
              </div>
            </div>
          <% else %>
            <div class="bg-base-100/90 px-4 py-2 rounded-lg text-sm text-base-content/60">
              Waiting for puck drop...
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Legend --%>
      <div class="flex items-center justify-center gap-4 mt-3 text-[10px] text-base-content/40">
        <div class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-full bg-green-500/30"></span>
          <span>Goal</span>
        </div>
        <div class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-full bg-blue-400/30"></span>
          <span>Shot</span>
        </div>
        <div class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-full bg-amber-500/30"></span>
          <span>Penalty</span>
        </div>
        <div class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-full bg-red-500/30"></span>
          <span>Hit</span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Team preview card for pregame showing records and basic info.
  """
  attr :home_team, :map, required: true
  attr :away_team, :map, required: true

  def pregame_team_preview(assigns) do
    ~H"""
    <div class="data-card p-3">
      <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-3">
        Matchup Preview
      </div>

      <div class="space-y-4">
        <%!-- Away Team --%>
        <div class="flex items-center gap-3">
          <div
            class="w-10 h-10 rounded flex items-center justify-center"
            style={"background-color: ##{@away_team.color || "333"}20"}
          >
            <img
              :if={@away_team.logo}
              src={@away_team.logo}
              alt={@away_team.name}
              class="w-8 h-8 object-contain"
            />
          </div>
          <div class="flex-1">
            <div class="font-medium text-sm">{@away_team.name}</div>
            <div :if={@away_team.records} class="text-xs text-base-content/50 font-mono">
              {get_record(@away_team.records)}
            </div>
          </div>
          <div class="text-xs text-base-content/40 uppercase">Away</div>
        </div>

        <div class="border-t border-base-300/50"></div>

        <%!-- Home Team --%>
        <div class="flex items-center gap-3">
          <div
            class="w-10 h-10 rounded flex items-center justify-center"
            style={"background-color: ##{@home_team.color || "333"}20"}
          >
            <img
              :if={@home_team.logo}
              src={@home_team.logo}
              alt={@home_team.name}
              class="w-8 h-8 object-contain"
            />
          </div>
          <div class="flex-1">
            <div class="font-medium text-sm">{@home_team.name}</div>
            <div :if={@home_team.records} class="text-xs text-base-content/50 font-mono">
              {get_record(@home_team.records)}
            </div>
          </div>
          <div class="text-xs text-base-content/40 uppercase">Home</div>
        </div>
      </div>
    </div>

    <div class="data-card p-3">
      <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-3">
        Play-by-Play
      </div>
      <div class="text-center py-8 text-base-content/40">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 mx-auto mb-2 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <p class="text-sm">Play-by-play will appear once the game starts</p>
      </div>
    </div>
    """
  end

  @doc """
  Game not found state.
  """
  attr :game_id, :string, required: true

  def game_not_found(assigns) do
    ~H"""
    <div class="data-card p-8 text-center">
      <svg xmlns="http://www.w3.org/2000/svg" class="h-12 w-12 mx-auto mb-4 text-base-content/30" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <h2 class="text-lg font-bold mb-2">Game Not Found</h2>
      <p class="text-base-content/60 text-sm mb-4">
        We couldn't find a game with ID: {@game_id}
      </p>
      <.link navigate="/nhl/live" class="btn btn-primary btn-sm">
        View Today's Games
      </.link>
    </div>
    """
  end
end
