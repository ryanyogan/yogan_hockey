defmodule YoganHockeyWeb.DashboardLive do
  @moduledoc """
  Dashboard LiveView - ESPN-style hockey dashboard.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.NHL
  alias YoganHockey.DEL2
  alias YoganHockey.LiveGames.PredictionServer
  alias YoganHockeyWeb.SEO

  import YoganHockeyWeb.HockeyComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:standings")
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "yogan:stats")
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "live_games:predictions")
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:injuries")
    end

    games = NHL.list_live_scores()

    # Request predictions for games (async)
    if connected?(socket) do
      PredictionServer.ensure_predictions(games)
    end

    # Get existing predictions (may be empty initially)
    predictions = PredictionServer.get_all_predictions()

    # Get injury counts by team_id (populated by InjuriesServer on boot)
    injuries = build_injury_counts()

    {:ok,
     socket
     |> SEO.put_seo(
       title: "Live NHL Stats & Player Tracking",
       description: "Real-time NHL scores, standings, and stats. Track your favorite players, view live game updates, and follow Andrew Yogan's career.",
       image: "/images/og/default.svg",
       url: "/"
     )
     |> assign(:live_games, games)
     |> assign(:predictions, predictions)
     |> assign(:injuries, injuries)
     |> assign(:standings, NHL.list_standings())
     |> assign(:yogan, DEL2.get_yogan_player())
     |> assign(:yogan_current, DEL2.get_yogan_current_season())
     |> assign(:teams, NHL.list_teams())
     |> assign(:favorite_ids, [])
     |> assign(:favorite_players, nil)}
  end

  # Handle favorites loaded from localStorage
  @impl true
  def handle_event("favorites_loaded", %{"player_ids" => player_ids}, socket) do
    # Show max 2 favorites on dashboard
    display_ids = Enum.take(player_ids, 2)

    socket =
      socket
      |> assign(:favorite_ids, player_ids)
      |> assign_async(:favorite_players, fn ->
        players = NHL.get_players(display_ids)
        {:ok, %{favorite_players: players}}
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("favorites_updated", %{"player_ids" => player_ids}, socket) do
    display_ids = Enum.take(player_ids, 2)

    socket =
      socket
      |> assign(:favorite_ids, player_ids)
      |> assign_async(:favorite_players, fn ->
        players = NHL.get_players(display_ids)
        {:ok, %{favorite_players: players}}
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_favorite", %{"id" => player_id}, socket) do
    {:noreply, push_event(socket, "toggle_favorite", %{player_id: player_id})}
  end

  @impl true
  def handle_info({:live_scores_updated, games}, socket) do
    {:noreply, assign(socket, :live_games, games)}
  end

  def handle_info({:standings_updated, standings}, socket) do
    {:noreply, assign(socket, :standings, standings)}
  end

  def handle_info({:yogan_stats_updated, stats}, socket) do
    {:noreply,
     socket
     |> assign(:yogan, stats.player)
     |> assign(:yogan_current, stats.current_season)}
  end

  def handle_info({:prediction_updated, game_id, prediction}, socket) do
    predictions = Map.put(socket.assigns.predictions, game_id, prediction)
    {:noreply, assign(socket, :predictions, predictions)}
  end

  def handle_info({:injuries_updated, _injuries}, socket) do
    injuries = build_injury_counts()
    {:noreply, assign(socket, :injuries, injuries)}
  end

  defp build_injury_counts do
    NHL.list_injuries()
    |> Enum.group_by(& &1.team_id)
    |> Enum.map(fn {team_id, injuries} -> {team_id, length(injuries)} end)
    |> Enum.into(%{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dashboard" phx-hook="FavoritePlayers" class="space-y-6">
      <%!-- Scoreboard Ticker --%>
      <section>
        <.scoreboard_ticker games={@live_games} />
      </section>

      <%!-- Main Content Grid --%>
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Left Column: Featured + Games --%>
        <div class="lg:col-span-2 space-y-6">
          <%!-- Featured Player: Andrew Yogan --%>
          <section>
            <.section_header title="Featured Player" link_text="Full Stats" link_to={~p"/yogan"} />
            <.featured_player player={@yogan} stats={@yogan_current} />
          </section>

          <%!-- Favorite Players --%>
          <section>
            <.section_header title="Your Favorites" link_text="All Players" link_to={~p"/players"} />
            <%= case @favorite_players do %>
              <% %Phoenix.LiveView.AsyncResult{loading: true} -> %>
                <%!-- Loading skeleton --%>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <.player_card_skeleton :for={_ <- 1..min(length(@favorite_ids), 2)} />
                </div>

              <% %Phoenix.LiveView.AsyncResult{ok?: true, result: players} when players != [] -> %>
                <%!-- Loaded favorites --%>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <.player_card
                    :for={player <- players}
                    player={player}
                    favorited={player.id in @favorite_ids}
                  />
                </div>

              <% _ -> %>
                <%!-- Empty state --%>
                <.empty_favorites />
            <% end %>
          </section>

          <%!-- Today's Games --%>
          <section>
            <.section_header title="Today's Games" link_text="All Scores" link_to={~p"/nhl/live"} />
            <%= if Enum.empty?(@live_games) do %>
              <div class="data-card p-8 text-center">
                <div class="text-4xl mb-2">🏒</div>
                <p class="text-base-content/60">No games scheduled today</p>
              </div>
            <% else %>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <.game_card :for={game <- Enum.take(@live_games, 6)} game={game} prediction={@predictions[game.id]} injuries={@injuries} />
              </div>
            <% end %>
          </section>

          <%!-- All Teams --%>
          <section>
            <.section_header title="NHL Teams" link_text="All Teams" link_to={~p"/nhl"} />
            <%= if Enum.empty?(@teams) do %>
              <div class="team-grid">
                <div :for={_ <- 1..16} class="loading-skeleton aspect-square"></div>
              </div>
            <% else %>
              <.team_grid teams={@teams} />
            <% end %>
          </section>
        </div>

        <%!-- Right Column: Standings --%>
        <div class="space-y-6">
          <%!-- Standings Widget --%>
          <%= if Enum.empty?(@standings) do %>
            <div class="data-card">
              <div class="data-card-header">
                <span class="data-card-title">Standings</span>
              </div>
              <div class="p-4">
                <div class="loading-skeleton h-64"></div>
              </div>
            </div>
          <% else %>
            <.standings_widget standings={@standings} />
          <% end %>

          <%!-- Quick Links --%>
          <div class="data-card">
            <div class="data-card-header">
              <span class="data-card-title">Quick Links</span>
            </div>
            <div class="p-3 space-y-2">
              <.link navigate={~p"/nhl/live"} class="flex items-center justify-between p-2 hover:bg-base-300 transition-colors">
                <span class="text-sm font-medium">Live Scores</span>
                <span class="live-indicator">Live</span>
              </.link>
              <.link navigate={~p"/nhl"} class="flex items-center justify-between p-2 hover:bg-base-300 transition-colors">
                <span class="text-sm font-medium">Full Standings</span>
                <.icon name="hero-chevron-right" class="w-4 h-4 text-base-content/40" />
              </.link>
              <.link navigate={~p"/yogan"} class="flex items-center justify-between p-2 hover:bg-base-300 transition-colors">
                <span class="text-sm font-medium">Andrew Yogan Stats</span>
                <.icon name="hero-chevron-right" class="w-4 h-4 text-base-content/40" />
              </.link>
            </div>
          </div>

          <%!-- Live Games Count --%>
          <div class="data-card p-4">
            <div class="flex items-center justify-between">
              <div>
                <div class="text-2xl font-mono font-bold">{live_game_count(@live_games)}</div>
                <div class="text-[10px] uppercase tracking-wider text-base-content/50">Live Games</div>
              </div>
              <div>
                <div class="text-2xl font-mono font-bold">{length(@live_games)}</div>
                <div class="text-[10px] uppercase tracking-wider text-base-content/50">Total Games</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp live_game_count(games) do
    games |> Enum.count(&(&1.status.state == "in"))
  end
end
