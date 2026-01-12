defmodule YoganHockeyWeb.BracketComponents do
  @moduledoc """
  Components for displaying NHL playoff brackets with AI predictions.
  """
  use YoganHockeyWeb, :html

  # ============================================
  # PLAYOFF BRACKET
  # ============================================

  @doc """
  Renders the full playoff bracket with all 4 rounds.
  """
  attr :bracket, :map, required: true
  attr :predictions, :map, default: %{}
  attr :class, :string, default: ""

  def playoff_bracket(assigns) do
    ~H"""
    <div class={["playoff-bracket", @class]}>
      <div class="bracket-container">
        <%= for {round, idx} <- Enum.with_index(@bracket.rounds) do %>
          <.bracket_round
            round={round}
            predictions={@predictions}
            round_idx={idx}
            total_rounds={length(@bracket.rounds)}
          />
        <% end %>
      </div>
      <div :if={@bracket[:is_sample]} class="bracket-notice">
        <span class="text-warning">Showing sample bracket - Playoffs not yet started</span>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single round column of matchups.
  """
  attr :round, :map, required: true
  attr :predictions, :map, default: %{}
  attr :round_idx, :integer, required: true
  attr :total_rounds, :integer, required: true

  def bracket_round(assigns) do
    ~H"""
    <div class="bracket-round" data-round={@round_idx}>
      <div class="round-header">
        <span class="round-name">{@round.name}</span>
      </div>
      <div class="round-matchups">
        <%= for matchup <- @round.matchups do %>
          <.series_matchup
            matchup={matchup}
            prediction={Map.get(@predictions, matchup.id)}
          />
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders an individual series matchup with prediction.
  """
  attr :matchup, :map, required: true
  attr :prediction, :map, default: nil

  def series_matchup(assigns) do
    ~H"""
    <div class={["series-matchup", matchup_status_class(@matchup.status)]}>
      <%= if @matchup.home && @matchup.away do %>
        <.team_row
          team={@matchup.home}
          wins={@matchup.home_wins}
          win_prob={@prediction && @prediction.home_win_prob}
          is_winner={@matchup.status == :completed && @matchup.home_wins == 4}
        />
        <div class="matchup-divider">
          <span class="vs-text">vs</span>
        </div>
        <.team_row
          team={@matchup.away}
          wins={@matchup.away_wins}
          win_prob={@prediction && @prediction.away_win_prob}
          is_winner={@matchup.status == :completed && @matchup.away_wins == 4}
        />
        <.prediction_tooltip :if={@prediction} prediction={@prediction} />
      <% else %>
        <.empty_matchup />
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a team row within a matchup.
  """
  attr :team, :map, required: true
  attr :wins, :integer, default: 0
  attr :win_prob, :float, default: nil
  attr :is_winner, :boolean, default: false

  def team_row(assigns) do
    ~H"""
    <div class={["team-row", @is_winner && "winner"]}>
      <div class="team-info">
        <div class="team-logo">
          <img :if={@team.logo} src={@team.logo} alt={@team.name} />
          <span :if={!@team.logo} class="team-abbrev">{@team.abbreviation}</span>
        </div>
        <div class="team-details">
          <span class="team-seed" :if={@team.seed}>({@team.seed})</span>
          <span class="team-name">{@team.abbreviation || @team.name}</span>
        </div>
      </div>
      <div class="team-score">
        <span class="series-wins">{@wins}</span>
        <.win_probability :if={@win_prob} prob={@win_prob} />
      </div>
    </div>
    """
  end

  @doc """
  Renders a win probability badge.
  """
  attr :prob, :float, required: true

  def win_probability(assigns) do
    prob_pct = round(assigns.prob * 100)
    assigns = assign(assigns, prob_pct: prob_pct)

    ~H"""
    <span class={["win-prob", prob_class(@prob_pct)]}>
      {@prob_pct}%
    </span>
    """
  end

  @doc """
  Renders a prediction tooltip with reasoning.
  """
  attr :prediction, :map, required: true

  def prediction_tooltip(assigns) do
    ~H"""
    <div class="prediction-tooltip">
      <div class="tooltip-trigger">
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456z" />
        </svg>
      </div>
      <div class="tooltip-content">
        <div class="tooltip-header">AI Prediction</div>
        <div class="tooltip-body">
          <p :if={@prediction.reasoning}>{@prediction.reasoning}</p>
          <p :if={@prediction.predicted_winner} class="predicted-winner">
            Predicted: {@prediction.predicted_winner} in {@prediction.predicted_games || "?"} games
          </p>
          <p class="tooltip-model">Model: {@prediction.model}</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty/TBD matchup placeholder.
  """
  def empty_matchup(assigns) do
    ~H"""
    <div class="empty-matchup">
      <div class="tbd-row">
        <span class="tbd-text">TBD</span>
      </div>
      <div class="matchup-divider">
        <span class="vs-text">vs</span>
      </div>
      <div class="tbd-row">
        <span class="tbd-text">TBD</span>
      </div>
    </div>
    """
  end

  # ============================================
  # PREDICTION CARD
  # ============================================

  @doc """
  Renders a detailed prediction card for a series.
  """
  attr :matchup, :map, required: true
  attr :prediction, :map, required: true

  def prediction_card(assigns) do
    ~H"""
    <div class="prediction-card">
      <div class="prediction-header">
        <span class="prediction-title">AI Series Prediction</span>
        <span class="prediction-model">{@prediction.model}</span>
      </div>
      <div class="prediction-matchup">
        <div class="prediction-team">
          <span class="team-name">{@matchup.home.name}</span>
          <span class={["team-prob", prob_class(round(@prediction.home_win_prob * 100))]}>
            {round(@prediction.home_win_prob * 100)}%
          </span>
        </div>
        <span class="vs">vs</span>
        <div class="prediction-team">
          <span class="team-name">{@matchup.away.name}</span>
          <span class={["team-prob", prob_class(round(@prediction.away_win_prob * 100))]}>
            {round(@prediction.away_win_prob * 100)}%
          </span>
        </div>
      </div>
      <div :if={@prediction.reasoning} class="prediction-reasoning">
        <p>{@prediction.reasoning}</p>
      </div>
      <div :if={@prediction.predicted_winner} class="prediction-outcome">
        <span class="outcome-label">Predicted outcome:</span>
        <span class="outcome-value">{@prediction.predicted_winner} in {@prediction.predicted_games || "?"}</span>
      </div>
      <div class="prediction-timestamp">
        Generated: {format_time(@prediction.generated_at)}
      </div>
    </div>
    """
  end

  # ============================================
  # HELPER FUNCTIONS
  # ============================================

  defp matchup_status_class(:completed), do: "completed"
  defp matchup_status_class(:in_progress), do: "in-progress"
  defp matchup_status_class(:scheduled), do: "scheduled"
  defp matchup_status_class(_), do: "pending"

  defp prob_class(pct) when pct >= 70, do: "high-prob"
  defp prob_class(pct) when pct >= 50, do: "medium-prob"
  defp prob_class(_), do: "low-prob"

  defp format_time(nil), do: "N/A"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M UTC")
  end
end
