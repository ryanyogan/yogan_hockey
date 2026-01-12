defmodule YoganHockeyWeb.NHLLive do
  @moduledoc """
  NHL Hub - ESPN-style standings and teams page.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.NHL
  alias YoganHockeyWeb.SEO

  import YoganHockeyWeb.HockeyComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:teams")
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:standings")
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")
    end

    teams = NHL.list_teams()
    standings = NHL.list_standings()
    live_games = NHL.list_live_scores()

    {:ok,
     socket
     |> SEO.put_seo(
       title: "NHL Standings & Teams",
       description: "Complete NHL standings by conference and division. Browse all 32 teams, view records, and track playoff races.",
       image: "/images/og/standings.svg",
       url: "/nhl"
     )
     |> assign(:teams, teams)
     |> assign(:standings, standings)
     |> assign(:live_games, live_games)
     |> assign(:tab, "standings")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"] || "standings"
    # Validate tab value
    tab = if tab in ["standings", "teams"], do: tab, else: "standings"
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/nhl?tab=#{tab}")}
  end

  @impl true
  def handle_info({:teams_updated, teams}, socket) do
    {:noreply, assign(socket, :teams, teams)}
  end

  def handle_info({:standings_updated, standings}, socket) do
    {:noreply, assign(socket, :standings, standings)}
  end

  def handle_info({:live_scores_updated, games}, socket) do
    {:noreply, assign(socket, :live_games, games)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Scoreboard Ticker --%>
      <.scoreboard_ticker games={@live_games} />

      <%!-- Page Header --%>
      <div class="section-header">
        <span class="section-title text-lg">NHL</span>
        <div class="flex items-center gap-2">
          <button
            phx-click="switch_tab"
            phx-value-tab="standings"
            class={["text-xs px-3 py-1 cursor-pointer", @tab == "standings" && "bg-primary text-primary-content", @tab != "standings" && "bg-base-300"]}
          >
            Standings
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="teams"
            class={["text-xs px-3 py-1 cursor-pointer", @tab == "teams" && "bg-primary text-primary-content", @tab != "teams" && "bg-base-300"]}
          >
            Teams
          </button>
        </div>
      </div>

      <%!-- Standings Tab --%>
      <div :if={@tab == "standings"} class="space-y-6">
        <%= if Enum.empty?(@standings) do %>
          <div class="data-card p-8 text-center">
            <div class="loading-skeleton h-64"></div>
          </div>
        <% else %>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <%= for {division, teams} <- group_standings_by_division(@standings) do %>
              <.standings_table division={division} teams={teams} />
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Teams Tab --%>
      <div :if={@tab == "teams"} class="space-y-6">
        <%= if Enum.empty?(@teams) do %>
          <div class="team-grid">
            <div :for={_ <- 1..32} class="loading-skeleton aspect-square"></div>
          </div>
        <% else %>
          <.team_grid teams={@teams} />
        <% end %>
      </div>
    </div>
    """
  end

  defp group_standings_by_division(standings) do
    standings
    |> Enum.group_by(& &1.conference)
    |> Enum.map(fn {conf, teams} ->
      sorted = Enum.sort_by(teams, fn t ->
        points = t.stats["points"] || 0
        -points
      end)
      {conf, sorted}
    end)
    |> Enum.sort_by(fn {conf, _} -> conf end)
  end
end
