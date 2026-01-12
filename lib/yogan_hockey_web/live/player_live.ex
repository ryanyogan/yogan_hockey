defmodule YoganHockeyWeb.PlayerLive do
  @moduledoc """
  Player detail page - similar layout to Andrew Yogan's page.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.NHL

  import YoganHockeyWeb.HockeyComponents
  import YoganHockeyWeb.Helpers.StatsHelpers

  @impl true
  def mount(%{"id" => player_id}, _session, socket) do
    case NHL.get_player(player_id) do
      {:ok, player} ->
        # Check if player is injured
        injury = NHL.get_player_injury(player_id)

        {:ok,
         socket
         |> assign(:page_title, player.name)
         |> assign(:player, player)
         |> assign(:injury, injury)
         |> assign(:favorite_ids, [])
         |> assign(:error, nil)}

      {:error, _reason} ->
        {:ok,
         socket
         |> assign(:page_title, "Player Not Found")
         |> assign(:player, nil)
         |> assign(:injury, nil)
         |> assign(:favorite_ids, [])
         |> assign(:error, "Player not found")}
    end
  end

  @impl true
  def handle_event("favorites_loaded", %{"player_ids" => player_ids}, socket) do
    {:noreply, assign(socket, :favorite_ids, player_ids)}
  end

  @impl true
  def handle_event("favorites_updated", %{"player_ids" => player_ids}, socket) do
    {:noreply, assign(socket, :favorite_ids, player_ids)}
  end

  @impl true
  def handle_event("toggle_favorite", %{"id" => player_id}, socket) do
    {:noreply, push_event(socket, "toggle_favorite", %{player_id: player_id})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="player-page" phx-hook="FavoritePlayers" class="space-y-6">
      <%= if @error do %>
        <div class="data-card p-6 text-center">
          <p class="text-error mb-4">{@error}</p>
          <.link navigate={~p"/players"} class="text-primary hover:underline">
            Back to players
          </.link>
        </div>
      <% else %>
        <%!-- Player Header Card --%>
        <div class="featured-card p-6">
          <span class="featured-badge">NHL</span>
          <div class="relative z-10 flex flex-col lg:flex-row gap-6">
            <%!-- Avatar --%>
            <div class="w-24 h-24 lg:w-32 lg:h-32 bg-base-300 flex items-center justify-center shrink-0 overflow-hidden">
              <img :if={@player.headshot} src={@player.headshot} alt={@player.name} class="w-full h-full object-cover" />
              <span :if={!@player.headshot} class="text-5xl">🏒</span>
            </div>

            <%!-- Info --%>
            <div class="flex-1">
              <div class="flex items-center gap-3 mb-2">
                <h1 class="text-2xl lg:text-3xl font-bold">{@player.name}</h1>
                <span :if={@player[:position]} class="text-xs bg-primary/20 text-primary px-2 py-0.5 font-mono">
                  {@player[:position]}
                </span>
                <.favorite_button
                  player_id={@player.id}
                  favorited={@player.id in @favorite_ids}
                  class="ml-auto"
                />
              </div>
              <p :if={@player[:team]} class="text-base-content/60 mb-4">
                <.link :if={@player[:team][:id] && @player[:team][:id] != ""} navigate={~p"/nhl/teams/#{@player[:team][:id]}"} class="hover:text-primary">
                  {@player[:team][:name]}
                </.link>
                <span :if={!@player[:team][:id] || @player[:team][:id] == ""}>{@player[:team][:name]}</span>
                <span :if={@player[:jersey]} class="text-base-content/40"> · #{@player[:jersey]}</span>
              </p>

              <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                <div :if={@player[:birth_date]}>
                  <span class="text-base-content/50">Born</span>
                  <div class="font-medium">{format_date(@player[:birth_date])}</div>
                </div>
                <div :if={@player[:birth_place]}>
                  <span class="text-base-content/50">Birthplace</span>
                  <div class="font-medium">{@player[:birth_place]}</div>
                </div>
                <div :if={@player[:height]}>
                  <span class="text-base-content/50">Height</span>
                  <div class="font-medium">{@player[:height]}</div>
                </div>
                <div :if={@player[:shoots]}>
                  <span class="text-base-content/50">Shoots</span>
                  <div class="font-medium">{@player[:shoots]}</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Injury Status --%>
        <.injury_badge :if={@injury} injury={@injury} />

        <%!-- Current Season Stats --%>
        <section :if={@player[:current_season_stats]}>
          <.section_header title="Current Season" />
          <div class="grid grid-cols-3 sm:grid-cols-6 gap-2">
            <.stat_box label="GP" value={@player[:current_season_stats][:games_played] || 0} />
            <.stat_box label="G" value={@player[:current_season_stats][:goals] || 0} />
            <.stat_box label="A" value={@player[:current_season_stats][:assists] || 0} />
            <.stat_box label="PTS" value={@player[:current_season_stats][:points] || 0} class="bg-primary/10 border-primary/30" />
            <.stat_box label="PIM" value={@player[:current_season_stats][:penalty_minutes] || 0} />
            <.stat_box label="+/-" value={format_plus_minus(@player[:current_season_stats][:plus_minus])} />
          </div>

          <%!-- Additional stats --%>
          <div :if={@player[:current_season_stats][:shots]} class="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-2">
            <.stat_box label="SOG" value={@player[:current_season_stats][:shots] || 0} />
            <.stat_box label="PPG" value={@player[:current_season_stats][:power_play_goals] || 0} />
            <.stat_box label="PPA" value={@player[:current_season_stats][:power_play_assists] || 0} />
            <.stat_box label="GWG" value={@player[:current_season_stats][:game_winning_goals] || 0} />
          </div>
        </section>

        <%!-- Career Stats Table --%>
        <section :if={@player[:career_seasons] && @player[:career_seasons] != []}>
          <div class="data-card">
            <%!-- Header with totals --%>
            <div class="flex items-center justify-between px-3 py-2 border-b border-base-300 bg-base-200/50">
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold uppercase tracking-wider">Career</span>
                <span class="text-xs text-base-content/50">({length(@player[:career_seasons])} seasons)</span>
              </div>
              <div class="flex items-center gap-3 text-xs font-mono">
                <span class="text-base-content/50">{career_total(@player[:career_seasons], :games_played)} GP</span>
                <span>{career_total(@player[:career_seasons], :goals)} G</span>
                <span>{career_total(@player[:career_seasons], :assists)} A</span>
                <span class="font-bold text-primary">{career_total(@player[:career_seasons], :points)} PTS</span>
                <span class="text-base-content/50">{points_per_game(@player[:career_seasons])} PPG</span>
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
            <.stats_table stats={@player[:career_seasons]} />
          </div>
        </section>

        <%!-- Team Info --%>
        <section :if={@player[:team] && @player[:team][:id] && @player[:team][:id] != ""}>
          <.section_header title="Current Team" />
          <.link navigate={~p"/nhl/teams/#{@player[:team][:id]}"} class="data-card p-4 flex items-center gap-4 hover:border-primary/50 transition-colors">
            <div class="w-16 h-16 bg-base-300 flex items-center justify-center overflow-hidden">
              <img :if={@player[:team][:logo]} src={@player[:team][:logo]} alt={@player[:team][:name]} class="w-12 h-12 object-contain" />
              <span :if={!@player[:team][:logo]} class="text-3xl">🏒</span>
            </div>
            <div>
              <h3 class="font-bold text-lg">{@player[:team][:name]}</h3>
              <p :if={@player[:team][:abbreviation]} class="text-sm text-base-content/60">{@player[:team][:abbreviation]}</p>
            </div>
          </.link>
        </section>

        <%!-- Back Link --%>
        <div class="text-center">
          <.link navigate={~p"/players"} class="text-primary hover:underline text-sm">
            Back to players
          </.link>
        </div>
      <% end %>
    </div>
    """
  end
end
