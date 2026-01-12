defmodule YoganHockeyWeb.TeamLive do
  @moduledoc """
  Team detail page - ESPN-style team view.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.NHL
  alias YoganHockeyWeb.SEO

  import YoganHockeyWeb.Helpers.StatsHelpers, only: [format_diff: 1, diff_class: 1, get_stat: 2]
  import YoganHockeyWeb.PlayerComponents, only: [injury_row: 1]

  @impl true
  def mount(%{"id" => team_id}, _session, socket) do
    case NHL.get_team_details(team_id) do
      {:ok, team} ->
        basic_team = NHL.get_team(team_id)
        standings = get_team_standings(team_id)
        schedule = get_team_schedule(team_id)
        injuries = NHL.get_injuries_for_team(team_id)

        # Trigger background refresh to update cache with fresh data
        if connected?(socket) do
          refresh_team_in_background(team_id)
        end

        team_name = team.display_name || team.name
        description = "#{team_name} schedule, roster, stats, and injury reports. Get the latest on your favorite NHL team."

        {:ok,
         socket
         |> SEO.put_seo(
           title: team_name,
           description: description,
           image: "/images/og/team.svg",
           url: "/nhl/teams/#{team_id}"
         )
         |> assign(:team_id, team_id)
         |> assign(:team, team)
         |> assign(:basic_team, basic_team)
         |> assign(:standings, standings)
         |> assign(:schedule, schedule)
         |> assign(:injuries, injuries)
         |> assign(:favorite_ids, [])}

      {:error, _reason} ->
        {:ok,
         socket
         |> SEO.put_seo(
           title: "Team Not Found",
           description: "The requested team could not be found.",
           url: "/nhl/teams/#{team_id}"
         )
         |> assign(:team_id, team_id)
         |> assign(:team, nil)
         |> assign(:basic_team, nil)
         |> assign(:standings, nil)
         |> assign(:schedule, nil)
         |> assign(:injuries, [])
         |> assign(:favorite_ids, [])}
    end
  end

  @valid_tabs ~w(schedule roster stats injuries)

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @valid_tabs, do: params["tab"], else: "schedule"
    {:noreply, assign(socket, :tab, tab)}
  end

  # Refresh team data in background and send update to LiveView
  defp refresh_team_in_background(team_id) do
    pid = self()

    Task.start(fn ->
      case NHL.refresh_team_details(team_id) do
        {:ok, team} ->
          send(pid, {:team_refreshed, team})

        {:error, _reason} ->
          :ok
      end
    end)
  end

  defp get_team_standings(team_id) do
    NHL.list_standings()
    |> Enum.find(fn entry -> to_string(entry.team.id) == to_string(team_id) end)
  end

  defp get_team_schedule(team_id) do
    case NHL.get_team_schedule(team_id) do
      {:ok, schedule} -> schedule
      _ -> %{past_games: [], upcoming_games: []}
    end
  end

  @impl true
  def handle_info({:team_refreshed, team}, socket) do
    # Update the team data with fresh data from background refresh
    {:noreply, assign(socket, :team, team)}
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
    <div id="team-page" phx-hook="FavoritePlayers" class="space-y-6">
      <%= if @team do %>
        <%!-- Team Header --%>
        <div class="data-card p-4">
          <div class="flex items-center gap-4">
            <div
              class="w-20 h-20 sm:w-24 sm:h-24 p-2 shrink-0"
              style={"background-color: ##{@team.color || "333"}15;"}
            >
              <img :if={@team.logo} src={@team.logo} class="w-full h-full object-contain" />
            </div>
            <div class="flex-1 min-w-0">
              <h1 class="text-xl sm:text-2xl font-bold truncate">{@team.display_name || @team.name}</h1>
              <p class="text-sm text-base-content/60">{@team.location}</p>
              <p :if={@standings} class="text-xs text-base-content/40 mt-1">
                {@standings.conference} · {@standings.division}
              </p>
            </div>
          </div>

          <%!-- Stats Row --%>
          <div :if={@standings} class="grid grid-cols-4 gap-2 mt-4 pt-4 border-t border-base-300">
            <div class="text-center">
              <div class="text-xl font-mono font-bold text-success">{get_stat(@standings.stats, "wins")}</div>
              <div class="text-[10px] uppercase text-base-content/50">W</div>
            </div>
            <div class="text-center">
              <div class="text-xl font-mono font-bold text-error">{get_stat(@standings.stats, "losses")}</div>
              <div class="text-[10px] uppercase text-base-content/50">L</div>
            </div>
            <div class="text-center">
              <div class="text-xl font-mono font-bold">{get_stat(@standings.stats, "otLosses")}</div>
              <div class="text-[10px] uppercase text-base-content/50">OTL</div>
            </div>
            <div class="text-center">
              <div class="text-xl font-mono font-bold text-primary">{get_stat(@standings.stats, "points")}</div>
              <div class="text-[10px] uppercase text-base-content/50">PTS</div>
            </div>
          </div>
        </div>

        <%!-- Tab Navigation --%>
        <div class="flex gap-2">
          <.link
            patch={~p"/nhl/teams/#{@team_id}"}
            class={["text-xs px-4 py-2", @tab == "schedule" && "bg-primary text-primary-content", @tab != "schedule" && "bg-base-300"]}
          >
            Schedule
          </.link>
          <.link
            patch={~p"/nhl/teams/#{@team_id}?tab=roster"}
            class={["text-xs px-4 py-2", @tab == "roster" && "bg-primary text-primary-content", @tab != "roster" && "bg-base-300"]}
          >
            Roster
          </.link>
          <.link
            patch={~p"/nhl/teams/#{@team_id}?tab=stats"}
            class={["text-xs px-4 py-2", @tab == "stats" && "bg-primary text-primary-content", @tab != "stats" && "bg-base-300"]}
          >
            Stats
          </.link>
          <.link
            patch={~p"/nhl/teams/#{@team_id}?tab=injuries"}
            class={["text-xs px-4 py-2", @tab == "injuries" && "bg-primary text-primary-content", @tab != "injuries" && "bg-base-300"]}
          >
            Injuries
            <span :if={@injuries != []} class="ml-1 text-error">({length(@injuries)})</span>
          </.link>
        </div>

        <%!-- Schedule Tab --%>
        <div :if={@tab == "schedule" && @schedule} class="space-y-4">
          <%!-- Upcoming Games --%>
          <div :if={@schedule.upcoming_games != []} class="data-card">
            <div class="data-card-header">
              <span class="data-card-title">Upcoming ({length(@schedule.upcoming_games)})</span>
            </div>
            <div class="divide-y divide-base-300/50">
              <div :for={game <- Enum.take(@schedule.upcoming_games, 10)} class="px-3 py-2 flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="text-xs text-base-content/50 w-16">
                    {format_game_date(game.date)}
                  </div>
                  <div class="flex items-center gap-2">
                    <img :if={game.opponent.logo} src={game.opponent.logo} class="w-5 h-5 object-contain" />
                    <span class="text-sm font-medium">
                      {if game.is_home, do: "vs", else: "@"} {game.opponent.abbreviation}
                    </span>
                  </div>
                </div>
                <div class="text-xs text-base-content/50">
                  {game.date_display}
                </div>
              </div>
            </div>
          </div>

          <%!-- Past Games --%>
          <div :if={@schedule.past_games != []} class="data-card">
            <div class="data-card-header">
              <span class="data-card-title">Recent Results</span>
            </div>
            <div class="divide-y divide-base-300/50">
              <div :for={game <- Enum.take(@schedule.past_games, 15)} class="px-3 py-2 flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="text-xs text-base-content/50 w-16">
                    {format_game_date(game.date)}
                  </div>
                  <div class="flex items-center gap-2">
                    <img :if={game.opponent.logo} src={game.opponent.logo} class="w-5 h-5 object-contain" />
                    <span class="text-sm font-medium">
                      {if game.is_home, do: "vs", else: "@"} {game.opponent.abbreviation}
                    </span>
                  </div>
                </div>
                <div class="flex items-center gap-2 text-sm font-mono">
                  <span class={result_class(game)}>{result_text(game)}</span>
                  <span>{game.our_score}-{game.opponent_score}</span>
                </div>
              </div>
            </div>
          </div>

          <div :if={@schedule.upcoming_games == [] && @schedule.past_games == []} class="data-card p-8 text-center">
            <p class="text-base-content/60">No schedule data available</p>
          </div>
        </div>

        <%!-- Roster Tab --%>
        <div :if={@tab == "roster"}>
          <%= if @team.roster && length(@team.roster) > 0 do %>
            <div class="data-card">
              <div class="data-card-header">
                <span class="data-card-title">Roster ({length(@team.roster)})</span>
              </div>
              <%!-- Column labels --%>
              <div class="flex items-center px-3 py-1.5 bg-base-300/30 text-[10px] uppercase tracking-wider text-base-content/60 border-b border-base-300">
                <span class="w-10 text-center">#</span>
                <span class="flex-1">Player</span>
                <span class="w-12 text-center">Pos</span>
                <span class="w-10"></span>
              </div>
              <%!-- Roster rows --%>
              <div class="divide-y divide-base-300/50">
                <div :for={player <- sort_roster(@team.roster)} class="flex items-center px-3 py-2 hover:bg-base-300/30 transition-colors">
                  <span class="w-10 text-center font-mono font-bold text-primary text-sm">{player.jersey || "-"}</span>
                  <.link navigate={~p"/players/#{player.id}"} class="flex-1 flex items-center gap-2 min-w-0 hover:text-primary transition-colors">
                    <div class="w-6 h-6 bg-base-300 overflow-hidden shrink-0">
                      <img :if={player.headshot} src={player.headshot} class="w-full h-full object-cover" />
                    </div>
                    <span class="text-sm font-medium truncate">{player.display_name || player.name}</span>
                  </.link>
                  <span class="w-12 text-center text-xs text-base-content/60">{player.position || "-"}</span>
                  <div class="w-10 flex justify-center">
                    <button
                      phx-click="toggle_favorite"
                      phx-value-id={to_string(player.id)}
                      class={["cursor-pointer text-base-content/40 hover:text-error transition-colors", to_string(player.id) in @favorite_ids && "text-error"]}
                      title={if to_string(player.id) in @favorite_ids, do: "Remove from favorites", else: "Add to favorites"}
                    >
                      <svg :if={to_string(player.id) not in @favorite_ids} xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12z" />
                      </svg>
                      <svg :if={to_string(player.id) in @favorite_ids} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
                        <path d="M11.645 20.91l-.007-.003-.022-.012a15.247 15.247 0 01-.383-.218 25.18 25.18 0 01-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0112 5.052 5.5 5.5 0 0116.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 01-4.244 3.17 15.247 15.247 0 01-.383.219l-.022.012-.007.004-.003.001a.752.752 0 01-.704 0l-.003-.001z" />
                      </svg>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <div class="data-card p-8 text-center">
              <p class="text-base-content/60">No roster data available</p>
            </div>
          <% end %>
        </div>

        <%!-- Stats Tab --%>
        <div :if={@tab == "stats" && @standings}>
          <div class="data-card">
            <div class="data-card-header">
              <span class="data-card-title">Season Statistics</span>
            </div>
            <div class="p-4 grid grid-cols-2 sm:grid-cols-4 gap-4">
              <div class="text-center">
                <div class="text-2xl font-mono font-bold">{get_stat(@standings.stats, "gamesPlayed")}</div>
                <div class="text-[10px] uppercase text-base-content/50">Games Played</div>
              </div>
              <div class="text-center">
                <div class="text-2xl font-mono font-bold">{get_stat(@standings.stats, "goalsFor")}</div>
                <div class="text-[10px] uppercase text-base-content/50">Goals For</div>
              </div>
              <div class="text-center">
                <div class="text-2xl font-mono font-bold">{get_stat(@standings.stats, "goalsAgainst")}</div>
                <div class="text-[10px] uppercase text-base-content/50">Goals Against</div>
              </div>
              <div class="text-center">
                <div class={["text-2xl font-mono font-bold", diff_class(get_stat(@standings.stats, "pointDifferential"))]}>
                  {format_diff(get_stat(@standings.stats, "pointDifferential"))}
                </div>
                <div class="text-[10px] uppercase text-base-content/50">Diff</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Injuries Tab --%>
        <div :if={@tab == "injuries"}>
          <%= if @injuries != [] do %>
            <div class="data-card">
              <div class="data-card-header">
                <span class="data-card-title">Injured Players ({length(@injuries)})</span>
              </div>
              <div class="divide-y divide-base-300/50">
                <.injury_row :for={injury <- @injuries} injury={injury} class="" />
              </div>
            </div>
          <% else %>
            <div class="data-card p-8 text-center">
              <div class="text-4xl mb-2">💪</div>
              <p class="text-base-content/60">No injuries reported</p>
            </div>
          <% end %>
        </div>

        <%!-- Next Game --%>
        <div :if={@team.next_event} class="data-card p-4">
          <div class="text-[10px] uppercase tracking-wider text-base-content/50 mb-2">Next Game</div>
          <div class="font-bold">{@team.next_event.name}</div>
          <div class="text-sm text-base-content/60">{format_event_date(@team.next_event.date)}</div>
        </div>

        <%!-- Back Link --%>
        <.link navigate={~p"/nhl"} class="inline-flex items-center gap-1 text-sm text-primary hover:underline">
          <.icon name="hero-arrow-left" class="w-4 h-4" />
          Back to NHL
        </.link>
      <% else %>
        <%!-- Not Found --%>
        <div class="data-card p-12 text-center">
          <div class="text-5xl mb-4">🏒</div>
          <h2 class="text-xl font-bold mb-2">Team Not Found</h2>
          <p class="text-base-content/60 mb-6">We couldn't find this team.</p>
          <.link navigate={~p"/nhl"} class="btn btn-primary btn-sm">View All Teams</.link>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_event_date(nil), do: ""
  defp format_event_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> Calendar.strftime(datetime, "%A, %B %d at %I:%M %p")
      _ -> date_string
    end
  end

  defp sort_roster(roster) when is_list(roster) do
    Enum.sort_by(roster, fn player ->
      jersey = player.jersey || "99"
      String.pad_leading(to_string(jersey), 3, "0")
    end)
  end
  defp sort_roster(_), do: []

  # Schedule helpers
  defp format_game_date(nil), do: ""
  defp format_game_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> Calendar.strftime(datetime, "%b %d")
      _ -> date_string
    end
  end

  defp result_class(game) do
    cond do
      game.winner == true -> "text-success font-bold"
      game.winner == false -> "text-error font-bold"
      true -> ""
    end
  end

  defp result_text(game) do
    cond do
      game.winner == true -> "W"
      game.winner == false -> "L"
      true -> "-"
    end
  end
end
