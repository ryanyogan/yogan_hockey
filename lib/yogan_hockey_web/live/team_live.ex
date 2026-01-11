defmodule YoganHockeyWeb.TeamLive do
  @moduledoc """
  Team detail page - ESPN-style team view.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.NHL

  import YoganHockeyWeb.HockeyComponents

  @impl true
  def mount(%{"id" => team_id}, _session, socket) do
    case NHL.get_team_details(team_id) do
      {:ok, team} ->
        basic_team = NHL.get_team(team_id)
        standings = get_team_standings(team_id)
        schedule = get_team_schedule(team_id)

        {:ok,
         socket
         |> assign(:page_title, team.display_name || team.name)
         |> assign(:team, team)
         |> assign(:basic_team, basic_team)
         |> assign(:standings, standings)
         |> assign(:schedule, schedule)
         |> assign(:tab, "schedule")
         |> assign(:favorite_ids, [])}

      {:error, _reason} ->
        {:ok,
         socket
         |> assign(:page_title, "Team Not Found")
         |> assign(:team, nil)
         |> assign(:basic_team, nil)
         |> assign(:standings, nil)
         |> assign(:schedule, nil)
         |> assign(:tab, "schedule")
         |> assign(:favorite_ids, [])}
    end
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
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
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
              <div class="text-xl font-mono font-bold text-success">{get_stat(@standings, "wins")}</div>
              <div class="text-[10px] uppercase text-base-content/50">W</div>
            </div>
            <div class="text-center">
              <div class="text-xl font-mono font-bold text-error">{get_stat(@standings, "losses")}</div>
              <div class="text-[10px] uppercase text-base-content/50">L</div>
            </div>
            <div class="text-center">
              <div class="text-xl font-mono font-bold">{get_stat(@standings, "otLosses")}</div>
              <div class="text-[10px] uppercase text-base-content/50">OTL</div>
            </div>
            <div class="text-center">
              <div class="text-xl font-mono font-bold text-primary">{get_stat(@standings, "points")}</div>
              <div class="text-[10px] uppercase text-base-content/50">PTS</div>
            </div>
          </div>
        </div>

        <%!-- Tab Navigation --%>
        <div class="flex gap-2">
          <button
            phx-click="switch_tab"
            phx-value-tab="schedule"
            class={["text-xs px-4 py-2", @tab == "schedule" && "bg-primary text-primary-content", @tab != "schedule" && "bg-base-300"]}
          >
            Schedule
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="roster"
            class={["text-xs px-4 py-2", @tab == "roster" && "bg-primary text-primary-content", @tab != "roster" && "bg-base-300"]}
          >
            Roster
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="stats"
            class={["text-xs px-4 py-2", @tab == "stats" && "bg-primary text-primary-content", @tab != "stats" && "bg-base-300"]}
          >
            Stats
          </button>
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
              <table class="standings-table">
                <thead>
                  <tr>
                    <th class="stat w-12">#</th>
                    <th>Player</th>
                    <th class="stat">Pos</th>
                    <th class="stat w-12"></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={player <- sort_roster(@team.roster)}>
                    <td class="stat font-bold text-primary">{player.jersey || "-"}</td>
                    <td>
                      <.link navigate={~p"/players/#{player.id}"} class="flex items-center gap-2 hover:text-primary transition-colors">
                        <div class="w-6 h-6 bg-base-300 overflow-hidden shrink-0">
                          <img :if={player.headshot} src={player.headshot} class="w-full h-full object-cover" />
                        </div>
                        <span class="text-sm font-medium">{player.display_name || player.name}</span>
                      </.link>
                    </td>
                    <td class="stat text-base-content/60">{player.position || "-"}</td>
                    <td class="stat">
                      <.favorite_button player_id={to_string(player.id)} favorited={to_string(player.id) in @favorite_ids} />
                    </td>
                  </tr>
                </tbody>
              </table>
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
                <div class="text-2xl font-mono font-bold">{get_stat(@standings, "gamesPlayed")}</div>
                <div class="text-[10px] uppercase text-base-content/50">Games Played</div>
              </div>
              <div class="text-center">
                <div class="text-2xl font-mono font-bold">{format_number(get_stat(@standings, "goalsFor"))}</div>
                <div class="text-[10px] uppercase text-base-content/50">Goals For</div>
              </div>
              <div class="text-center">
                <div class="text-2xl font-mono font-bold">{format_number(get_stat(@standings, "goalsAgainst"))}</div>
                <div class="text-[10px] uppercase text-base-content/50">Goals Against</div>
              </div>
              <div class="text-center">
                <div class={["text-2xl font-mono font-bold", diff_class(get_stat(@standings, "pointDifferential"))]}>
                  {format_diff(get_stat(@standings, "pointDifferential"))}
                </div>
                <div class="text-[10px] uppercase text-base-content/50">Diff</div>
              </div>
            </div>
          </div>
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

  defp get_stat(nil, _key), do: "-"
  defp get_stat(%{stats: stats}, key) when is_map(stats) do
    case Map.get(stats, key) do
      nil -> "-"
      value when is_float(value) -> round(value)
      value -> value
    end
  end
  defp get_stat(_, _), do: "-"

  defp format_number(n) when is_number(n), do: round(n)
  defp format_number(n), do: n

  defp format_diff(n) when is_number(n) and n > 0, do: "+#{round(n)}"
  defp format_diff(n) when is_number(n), do: "#{round(n)}"
  defp format_diff(_), do: "-"

  defp diff_class(n) when is_number(n) and n > 0, do: "text-success"
  defp diff_class(n) when is_number(n) and n < 0, do: "text-error"
  defp diff_class(_), do: ""

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
