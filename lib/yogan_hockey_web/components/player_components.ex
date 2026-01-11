defmodule YoganHockeyWeb.PlayerComponents do
  @moduledoc """
  Components for displaying player information, stats, and favorites.
  """
  use YoganHockeyWeb, :html

  import YoganHockeyWeb.Helpers.StatsHelpers,
    only: [format_plus_minus: 1, plus_minus_class: 1, get_team_name: 1]

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
    ppg =
      if assigns.stats.games_played > 0 do
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
  # PLAYER CARD COMPONENTS
  # ============================================

  @doc """
  Renders a compact player card with favorite button.
  """
  attr :player, :map, required: true
  attr :favorited, :boolean, default: false
  attr :show_favorite, :boolean, default: true
  attr :class, :string, default: ""

  def player_card(assigns) do
    ~H"""
    <div class={["player-card", @class]}>
      <.link navigate={~p"/players/#{@player.id}"} class="player-card-content">
        <div class="player-headshot">
          <img :if={@player.headshot} src={@player.headshot} alt={@player.name} />
          <div :if={!@player.headshot} class="player-headshot-placeholder">
            <span class="text-2xl">🏒</span>
          </div>
        </div>
        <div class="player-info">
          <div class="player-name">{@player.name}</div>
          <div class="player-team">
            <span :if={@player.team}>{get_team_name(@player.team)}</span>
            <span :if={@player.position} class="player-position">· {@player.position}</span>
          </div>
          <div :if={@player.current_season_stats} class="player-stats">
            <span>{@player.current_season_stats.games_played || 0} GP</span>
            <span>{@player.current_season_stats.goals || 0} G</span>
            <span>{@player.current_season_stats.assists || 0} A</span>
            <span class="font-bold">{@player.current_season_stats.points || 0} PTS</span>
          </div>
        </div>
      </.link>
      <.favorite_button :if={@show_favorite} player_id={@player.id} favorited={@favorited} />
    </div>
    """
  end

  @doc """
  Renders a skeleton loading card matching player_card dimensions.
  """
  attr :class, :string, default: ""

  def player_card_skeleton(assigns) do
    ~H"""
    <div class={["player-card skeleton", @class]}>
      <div class="player-card-content">
        <div class="player-headshot skeleton-avatar"></div>
        <div class="player-info">
          <div class="skeleton-line w-3/4 h-4 mb-2"></div>
          <div class="skeleton-line w-1/2 h-3 mb-2"></div>
          <div class="skeleton-line w-full h-3"></div>
        </div>
      </div>
      <div class="skeleton-btn"></div>
    </div>
    """
  end

  @doc """
  Renders a favorite (heart) toggle button.
  """
  attr :player_id, :string, required: true
  attr :favorited, :boolean, default: false
  attr :class, :string, default: ""

  def favorite_button(assigns) do
    ~H"""
    <button
      phx-click="toggle_favorite"
      phx-value-id={@player_id}
      class={["favorite-btn cursor-pointer", @favorited && "active", @class]}
      title={if @favorited, do: "Remove from favorites", else: "Add to favorites"}
    >
      <svg
        :if={!@favorited}
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
        class="w-5 h-5"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12z"
        />
      </svg>
      <svg
        :if={@favorited}
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="currentColor"
        class="w-5 h-5"
      >
        <path d="M11.645 20.91l-.007-.003-.022-.012a15.247 15.247 0 01-.383-.218 25.18 25.18 0 01-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0112 5.052 5.5 5.5 0 0116.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 01-4.244 3.17 15.247 15.247 0 01-.383.219l-.022.012-.007.004-.003.001a.752.752 0 01-.704 0l-.003-.001z" />
      </svg>
    </button>
    """
  end

  @doc """
  Renders a search input with dropdown results for player search.
  """
  attr :results, :list, default: []
  attr :query, :string, default: ""
  attr :loading, :boolean, default: false
  attr :favorite_ids, :list, default: []
  attr :class, :string, default: ""

  def player_search(assigns) do
    ~H"""
    <div id="player-search" phx-hook="PlayerSearch" class={["player-search", @class]}>
      <div class="search-input-wrapper">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="search-icon"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z"
          />
        </svg>
        <input
          type="text"
          placeholder="Search NHL players..."
          class="search-input"
          value={@query}
          phx-debounce="300"
        />
        <div :if={@loading} class="search-spinner"></div>
      </div>
      <div :if={@results != [] and @query != ""} class="search-dropdown">
        <div :for={player <- @results} class="search-result">
          <.link navigate={~p"/players/#{player.id}"} class="search-result-link">
            <div class="search-result-avatar">
              <img :if={player.headshot} src={player.headshot} alt={player.name} />
              <span :if={!player.headshot}>🏒</span>
            </div>
            <div class="search-result-info">
              <div class="search-result-name">{player.name}</div>
              <div class="search-result-team">
                {get_team_name(player.team)} · {player.position}
              </div>
            </div>
          </.link>
          <.favorite_button player_id={player.id} favorited={player.id in @favorite_ids} />
        </div>
        <div :if={@results == [] and @query != ""} class="search-empty">
          No players found for "{@query}"
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty favorites state with a call-to-action.
  """
  attr :class, :string, default: ""

  def empty_favorites(assigns) do
    ~H"""
    <div class={["empty-favorites", @class]}>
      <p class="text-sm text-base-content/50">No favorite players yet</p>
      <.link navigate={~p"/players"} class="text-primary text-sm hover:underline">
        Browse players to add favorites
      </.link>
    </div>
    """
  end
end
