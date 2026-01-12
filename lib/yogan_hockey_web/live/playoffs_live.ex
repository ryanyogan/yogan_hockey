defmodule YoganHockeyWeb.PlayoffsLive do
  @moduledoc """
  LiveView for the NHL Playoffs predictions with AI-powered analysis.
  Mobile-first design optimized for iPhone usage.

  Predictions are fully autonomous - generated on deploy if missing,
  and automatically regenerated when games end.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.Playoffs
  alias YoganHockey.Playoffs.PredictionServer
  alias YoganHockeyWeb.SEO

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(YoganHockey.PubSub, "playoffs:updates")
    end

    # Check if generation is already in progress
    generating = connected?(socket) && PredictionServer.generating?()

    {:ok,
     socket
     |> SEO.put_seo(
       title: "NHL Playoffs",
       description: "AI-powered NHL playoff predictions and bracket analysis. See Stanley Cup odds, conference predictions, and series matchup probabilities.",
       image: "/images/og/playoffs.svg",
       url: "/playoffs"
     )
     |> assign(:active_tab, :picture)
     |> assign(:generating, generating)
     |> assign_async(:playoff_picture, fn -> load_playoff_picture() end)}
  end

  @impl true
  def handle_async(:playoff_picture, {:ok, %{playoff_picture: nil}}, socket) do
    # No predictions yet - PredictionServer will handle generation
    {:noreply, assign(socket, :playoff_picture, %Phoenix.LiveView.AsyncResult{ok?: true, result: nil})}
  end

  @impl true
  def handle_async(:playoff_picture, {:ok, %{playoff_picture: picture}}, socket) do
    {:noreply, assign(socket, :playoff_picture, %Phoenix.LiveView.AsyncResult{ok?: true, result: picture})}
  end

  @impl true
  def handle_async(:playoff_picture, {:exit, reason}, socket) do
    {:noreply, assign(socket, :playoff_picture, %Phoenix.LiveView.AsyncResult{failed: reason})}
  end

  # PubSub handlers for autonomous generation
  @impl true
  def handle_info({:generation_started}, socket) do
    {:noreply, assign(socket, :generating, true)}
  end

  @impl true
  def handle_info({:playoff_picture_updated, picture}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> assign(:playoff_picture, %Phoenix.LiveView.AsyncResult{ok?: true, result: picture})}
  end

  @impl true
  def handle_info({:generation_failed, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> put_flash(:error, "Failed to generate predictions. Will retry automatically.")}
  end

  @impl true
  def handle_info({:prediction_updated, _series_id, _prediction}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:bracket_updated, _bracket}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_atom(tab))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Page Header with Tabs --%>
      <div class="section-header">
        <div class="flex items-center gap-2">
          <span class="section-title">Playoffs</span>
          <span class="ai-badge">AI</span>
        </div>
        <div class="flex items-center gap-1">
          <button
            phx-click="switch_tab"
            phx-value-tab="picture"
            class={["tab-pill", @active_tab == :picture && "active"]}
          >
            Predictions
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="bracket"
            class={["tab-pill", @active_tab == :bracket && "active"]}
          >
            Bracket
          </button>
        </div>
      </div>

      <%!-- Content --%>
      <%= case @playoff_picture do %>
        <% %Phoenix.LiveView.AsyncResult{loading: true} -> %>
          <.loading_state />

        <% %Phoenix.LiveView.AsyncResult{ok?: true, result: nil} -> %>
          <.generating_state generating={@generating} />

        <% %Phoenix.LiveView.AsyncResult{ok?: true, result: picture} when not is_nil(picture) -> %>
          <%= if @active_tab == :picture do %>
            <.predictions_view picture={picture} generating={@generating} />
          <% else %>
            <.bracket_view picture={picture} />
          <% end %>

        <% _ -> %>
          <.generating_state generating={@generating} />
      <% end %>
    </div>
    """
  end

  # --- Components ---

  defp loading_state(assigns) do
    ~H"""
    <div class="ai-generating-container">
      <div class="ai-brain-animation">
        <div class="brain-pulse"></div>
        <div class="brain-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M12 2a9 9 0 0 1 9 9c0 3.074-1.676 5.59-3.442 7.395a20.36 20.36 0 0 1-2.876 2.416l-.682.46-.682-.46a20.354 20.354 0 0 1-2.876-2.416C8.676 16.59 7 14.074 7 11a5 5 0 0 1 10 0" />
            <circle cx="12" cy="11" r="3" />
          </svg>
        </div>
      </div>
      <h3 class="ai-generating-title">Loading Predictions</h3>
      <p class="ai-generating-text">Fetching playoff analysis...</p>
    </div>
    """
  end

  attr :generating, :boolean, default: false

  defp generating_state(assigns) do
    ~H"""
    <div class="ai-generating-container">
      <div class="ai-brain-animation">
        <div class="brain-pulse"></div>
        <div class="brain-rings">
          <div class="ring ring-1"></div>
          <div class="ring ring-2"></div>
          <div class="ring ring-3"></div>
        </div>
        <div class="brain-icon generating">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M9.5 2A2.5 2.5 0 0 1 12 4.5v15a2.5 2.5 0 0 1-4.96.44 2.5 2.5 0 0 1-2.96-3.08 3 3 0 0 1-.34-5.58 2.5 2.5 0 0 1 1.32-4.24 2.5 2.5 0 0 1 1.98-3A2.5 2.5 0 0 1 9.5 2Z" />
            <path d="M14.5 2A2.5 2.5 0 0 0 12 4.5v15a2.5 2.5 0 0 0 4.96.44 2.5 2.5 0 0 0 2.96-3.08 3 3 0 0 0 .34-5.58 2.5 2.5 0 0 0-1.32-4.24 2.5 2.5 0 0 0-1.98-3A2.5 2.5 0 0 0 14.5 2Z" />
          </svg>
        </div>
      </div>
      <h3 class="ai-generating-title">
        <%= if @generating do %>
          Analyzing NHL Standings
        <% else %>
          Preparing Analysis
        <% end %>
      </h3>
      <p class="ai-generating-text">
        <%= if @generating do %>
          Claude AI is evaluating team statistics, historical performance, and playoff dynamics...
        <% else %>
          Predictions will generate automatically
        <% end %>
      </p>
      <div class="ai-progress-dots">
        <span class="dot"></span>
        <span class="dot"></span>
        <span class="dot"></span>
      </div>
    </div>
    """
  end

  attr :picture, :map, required: true
  attr :generating, :boolean, default: false

  defp predictions_view(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- AI Analysis Card --%>
      <section>
        <div class="data-card">
          <div class="data-card-header">
            <span class="data-card-title">AI Analysis</span>
            <span class="text-[10px] text-base-content/40 font-mono">
              {Calendar.strftime(@picture.generated_at, "%b %d, %H:%M")}
            </span>
          </div>
          <div class="p-4 space-y-3">
            <p class="text-sm text-base-content/80 leading-relaxed">{@picture.analysis}</p>
            <div class="flex items-center gap-2 pt-2 border-t border-base-300/50">
              <span class="text-[10px] text-base-content/50 uppercase tracking-wider">Cup Favorite</span>
              <span class="text-sm font-bold text-accent">{@picture.cup_favorite}</span>
            </div>
            <%= if @generating do %>
              <div class="flex items-center gap-2 text-xs text-primary">
                <span class="spinner-small"></span>
                <span>Updating predictions...</span>
              </div>
            <% end %>
          </div>
        </div>
      </section>

      <%!-- Conference Predictions --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <section>
          <.conference_predictions title="Eastern Conference" teams={@picture.eastern} />
        </section>
        <section>
          <.conference_predictions title="Western Conference" teams={@picture.western} />
        </section>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :teams, :list, required: true

  defp conference_predictions(assigns) do
    ~H"""
    <div class="data-card">
      <div class="data-card-header">
        <span class="data-card-title">{@title}</span>
        <span class="text-[10px] text-base-content/40">{length(@teams)} teams</span>
      </div>
      <div class="divide-y divide-base-300/50">
        <%= for team <- @teams do %>
          <.team_row team={team} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :team, :map, required: true

  defp team_row(assigns) do
    cup_pct = round(assigns.team.cup_win_prob * 100)
    assigns = assign(assigns, :cup_pct, cup_pct)

    ~H"""
    <div class="flex items-center gap-3 px-3 py-2.5 hover:bg-base-300/30 transition-colors">
      <%!-- Seed --%>
      <span class="w-5 text-[10px] text-base-content/40 font-mono">{@team.seed}</span>

      <%!-- Logo --%>
      <div class="w-6 h-6 flex-shrink-0">
        <img :if={@team[:logo]} src={@team.logo} alt={@team.team_name} class="w-full h-full object-contain" />
        <span :if={!@team[:logo]} class="text-[10px] font-bold text-base-content/40">{@team[:abbreviation] || "?"}</span>
      </div>

      <%!-- Team Name --%>
      <span class="flex-1 text-sm font-medium truncate">{@team.team_name}</span>

      <%!-- Probabilities --%>
      <div class="hidden sm:flex items-center gap-3 text-[10px] font-mono text-base-content/50">
        <div class="text-center">
          <div>{round(@team.playoff_prob * 100)}%</div>
          <div class="text-[8px] text-base-content/30">PLAY</div>
        </div>
        <div class="text-center">
          <div>{round(@team.conf_final_prob * 100)}%</div>
          <div class="text-[8px] text-base-content/30">CONF</div>
        </div>
      </div>

      <%!-- Cup Win % --%>
      <div class={"text-right font-mono font-bold text-sm #{cup_color_class(@cup_pct)}"}>
        {@cup_pct}%
        <div class="text-[8px] font-normal text-base-content/30">CUP</div>
      </div>
    </div>
    """
  end

  defp cup_color_class(pct) when pct >= 15, do: "text-success"
  defp cup_color_class(pct) when pct >= 8, do: "text-warning"
  defp cup_color_class(_), do: "text-base-content/50"

  attr :picture, :map, required: true

  defp bracket_view(assigns) do
    # Build full bracket from predicted teams
    eastern = assigns.picture.eastern
    western = assigns.picture.western

    # Build all rounds for both conferences
    bracket = build_full_bracket(eastern, western)

    # Get predicted champion
    finals = hd(Enum.at(bracket.rounds, 3).matchups)
    champion = get_predicted_winner(finals)

    assigns =
      assigns
      |> assign(:bracket, bracket)
      |> assign(:champion, champion)
      |> assign(:finals, finals)

    ~H"""
    <div class="space-y-6" id="bracket-view" phx-hook="BracketRoundSelector">
      <%!-- Predicted Champion Card --%>
      <section>
        <div class="data-card">
          <div class="data-card-header">
            <span class="data-card-title">Predicted Champion</span>
            <span class="text-[10px] text-base-content/40">Stanley Cup Winner</span>
          </div>
          <div class="p-4">
            <div class="flex items-center justify-center gap-4">
              <div class="text-4xl">🏆</div>
              <div class="flex items-center gap-3">
                <img :if={@champion[:logo]} src={@champion.logo} class="w-12 h-12" />
                <div>
                  <div class="font-bold text-lg">{@champion.team_name}</div>
                  <div class="text-xs text-base-content/50">
                    {round(if @finals.team1 == @champion, do: @finals.team1_win_prob * 100, else: @finals.team2_win_prob * 100)}% chance to win Cup
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Round Selector --%>
      <div class="flex items-center gap-1 border-b border-base-300 pb-2">
        <button
          :for={{round, idx} <- Enum.with_index(@bracket.rounds, 1)}
          class={"tab-pill #{if idx == 1, do: "active"}"}
          data-round={idx}
        >
          {round.name}
        </button>
      </div>

      <%!-- Round Panels --%>
      <div class="round-panels">
        <%= for {round, idx} <- Enum.with_index(@bracket.rounds, 1) do %>
          <div class={"round-panel #{if idx == 1, do: "active"}"} data-round={idx}>
            <%= if idx <= 3 do %>
              <%!-- Conference matchups in grid --%>
              <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <.round_conference_card title="Eastern Conference" matchups={round.eastern} />
                <.round_conference_card title="Western Conference" matchups={round.western} />
              </div>
            <% else %>
              <%!-- Stanley Cup Final --%>
              <.stanley_cup_final matchup={hd(round.matchups)} />
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Bracket Path Overview --%>
      <section>
        <div class="data-card">
          <div class="data-card-header">
            <span class="data-card-title">Bracket Overview</span>
          </div>
          <div class="p-4">
            <div class="grid grid-cols-4 gap-2 text-center">
              <%= for {round, idx} <- Enum.with_index(@bracket.rounds, 1) do %>
                <div class="space-y-1">
                  <div class="text-[10px] font-medium uppercase tracking-wider text-base-content/50">{round.name}</div>
                  <div class="text-lg font-mono font-bold text-primary">
                    {if idx == 4, do: 1, else: length(round.eastern) + length(round.western)}
                  </div>
                  <div class="text-[9px] text-base-content/40">matchups</div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :matchups, :list, required: true

  defp round_conference_card(assigns) do
    ~H"""
    <div class="data-card">
      <div class="data-card-header">
        <span class="data-card-title">{@title}</span>
        <span class="text-[10px] text-base-content/40">{length(@matchups)} series</span>
      </div>
      <div class="divide-y divide-base-300/50">
        <%= for matchup <- @matchups do %>
          <.series_matchup_row matchup={matchup} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :matchup, :map, required: true

  defp series_matchup_row(assigns) do
    ~H"""
    <div :if={@matchup} class="p-3 space-y-2">
      <.series_team_row team={@matchup.team1} win_prob={@matchup.team1_win_prob} />
      <div class="flex items-center gap-2 px-6">
        <div class="flex-1 h-px bg-base-300/50"></div>
        <span class="text-[9px] text-base-content/30 uppercase">vs</span>
        <div class="flex-1 h-px bg-base-300/50"></div>
      </div>
      <.series_team_row team={@matchup.team2} win_prob={@matchup.team2_win_prob} />
    </div>
    """
  end

  attr :team, :map, required: true
  attr :win_prob, :float, required: true

  defp series_team_row(assigns) do
    pct = round(assigns.win_prob * 100)
    is_favorite = pct >= 50
    assigns = assign(assigns, pct: pct, is_favorite: is_favorite)

    ~H"""
    <div class={"flex items-center gap-3 #{if @is_favorite, do: "font-medium"}"}>
      <span class="w-4 text-[10px] text-base-content/40 font-mono">{@team.seed}</span>
      <img :if={@team[:logo]} src={@team.logo} class="w-6 h-6" />
      <span class="flex-1 text-sm truncate">{@team[:abbreviation] || @team.team_name}</span>
      <div class="flex items-center gap-2">
        <div class="w-16 h-1.5 bg-base-300/50 overflow-hidden">
          <div
            class={"h-full #{if @is_favorite, do: "bg-success", else: "bg-base-content/20"}"}
            style={"width: #{@pct}%"}
          ></div>
        </div>
        <span class={"text-xs font-mono #{if @is_favorite, do: "text-success", else: "text-base-content/40"}"}>{@pct}%</span>
      </div>
    </div>
    """
  end

  attr :matchup, :map, required: true

  defp stanley_cup_final(assigns) do
    ~H"""
    <div :if={@matchup} class="data-card">
      <div class="data-card-header">
        <span class="data-card-title">Stanley Cup Final</span>
        <span class="text-2xl">🏆</span>
      </div>
      <div class="p-6">
        <div class="flex items-center justify-center gap-8">
          <%!-- Team 1 --%>
          <div class="text-center space-y-2">
            <img :if={@matchup.team1[:logo]} src={@matchup.team1.logo} class="w-16 h-16 mx-auto" />
            <div class="font-bold">{@matchup.team1[:abbreviation] || @matchup.team1.team_name}</div>
            <div class="text-xs text-base-content/50">Eastern Champion</div>
            <div class={"text-lg font-mono font-bold #{if @matchup.team1_win_prob >= 0.5, do: "text-success", else: "text-base-content/50"}"}>
              {round(@matchup.team1_win_prob * 100)}%
            </div>
          </div>

          <%!-- VS --%>
          <div class="text-base-content/30 text-sm font-bold">VS</div>

          <%!-- Team 2 --%>
          <div class="text-center space-y-2">
            <img :if={@matchup.team2[:logo]} src={@matchup.team2.logo} class="w-16 h-16 mx-auto" />
            <div class="font-bold">{@matchup.team2[:abbreviation] || @matchup.team2.team_name}</div>
            <div class="text-xs text-base-content/50">Western Champion</div>
            <div class={"text-lg font-mono font-bold #{if @matchup.team2_win_prob >= 0.5, do: "text-success", else: "text-base-content/50"}"}>
              {round(@matchup.team2_win_prob * 100)}%
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Build complete bracket structure with all 4 rounds
  defp build_full_bracket(eastern, western) do
    # Round 1: 1v8, 2v7, 3v6, 4v5 for each conference
    r1_east = [
      build_matchup(Enum.at(eastern, 0), Enum.at(eastern, 7)),
      build_matchup(Enum.at(eastern, 1), Enum.at(eastern, 6)),
      build_matchup(Enum.at(eastern, 2), Enum.at(eastern, 5)),
      build_matchup(Enum.at(eastern, 3), Enum.at(eastern, 4))
    ]

    r1_west = [
      build_matchup(Enum.at(western, 0), Enum.at(western, 7)),
      build_matchup(Enum.at(western, 1), Enum.at(western, 6)),
      build_matchup(Enum.at(western, 2), Enum.at(western, 5)),
      build_matchup(Enum.at(western, 3), Enum.at(western, 4))
    ]

    # Round 2: Winners play (bracket style - 1/8 winner vs 4/5 winner, 2/7 vs 3/6)
    r2_east = [
      build_matchup(get_predicted_winner(Enum.at(r1_east, 0)), get_predicted_winner(Enum.at(r1_east, 3))),
      build_matchup(get_predicted_winner(Enum.at(r1_east, 1)), get_predicted_winner(Enum.at(r1_east, 2)))
    ]

    r2_west = [
      build_matchup(get_predicted_winner(Enum.at(r1_west, 0)), get_predicted_winner(Enum.at(r1_west, 3))),
      build_matchup(get_predicted_winner(Enum.at(r1_west, 1)), get_predicted_winner(Enum.at(r1_west, 2)))
    ]

    # Conference Finals
    r3_east = [
      build_matchup(get_predicted_winner(Enum.at(r2_east, 0)), get_predicted_winner(Enum.at(r2_east, 1)))
    ]

    r3_west = [
      build_matchup(get_predicted_winner(Enum.at(r2_west, 0)), get_predicted_winner(Enum.at(r2_west, 1)))
    ]

    # Stanley Cup Final
    east_champ = get_predicted_winner(hd(r3_east))
    west_champ = get_predicted_winner(hd(r3_west))
    finals = build_matchup(east_champ, west_champ)

    %{
      rounds: [
        %{name: "First Round", eastern: r1_east, western: r1_west},
        %{name: "Second Round", eastern: r2_east, western: r2_west},
        %{name: "Conf. Finals", eastern: r3_east, western: r3_west},
        %{name: "Stanley Cup", eastern: [], western: [], matchups: [finals]}
      ]
    }
  end

  defp get_predicted_winner(nil), do: nil
  defp get_predicted_winner(%{team1: t1, team2: t2, team1_win_prob: p1, team2_win_prob: p2}) do
    if p1 >= p2, do: t1, else: t2
  end

  defp build_matchup(team1, team2) when is_nil(team1) or is_nil(team2), do: nil

  defp build_matchup(team1, team2) do
    # Calculate relative win probability
    total_round2 = team1.round2_prob + team2.round2_prob
    team1_win = if total_round2 > 0, do: team1.round2_prob / total_round2, else: 0.5
    team2_win = 1 - team1_win

    %{
      team1: team1,
      team2: team2,
      team1_win_prob: team1_win,
      team2_win_prob: team2_win
    }
  end

  defp load_playoff_picture do
    case Playoffs.get_playoff_picture() do
      {:ok, picture} -> {:ok, %{playoff_picture: picture}}
      {:error, _reason} -> {:ok, %{playoff_picture: nil}}
    end
  end
end
