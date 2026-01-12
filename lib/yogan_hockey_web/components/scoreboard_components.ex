defmodule YoganHockeyWeb.ScoreboardComponents do
  @moduledoc """
  Components for displaying live game scores and game cards.
  """
  use YoganHockeyWeb, :html

  import YoganHockeyWeb.Helpers.StatsHelpers, only: [period_display: 1]

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

      game.status.completed ->
        "Final"

      true ->
        game.status.detail || ""
    end
  end

  # ============================================
  # GAME CARD (ESPN-Style)
  # ============================================

  @doc """
  Renders an ESPN-style game card.
  """
  attr :game, :map, required: true
  attr :class, :string, default: ""
  attr :prediction, :map, default: nil

  def game_card(assigns) do
    assigns = assign(assigns, :predicted_winner_abbrev, get_predicted_winner(assigns[:prediction]))

    ~H"""
    <div class={[game_card_class(@game), @class]}>
      <div class="game-card-header">
        <span :if={@game.status.state == "in"} class="live-indicator">Live</span>
        <span :if={@game.status.completed} class="text-base-content/50">Final</span>
        <span :if={@game.status.state == "pre"} class="text-base-content/50">{@game.status.detail}</span>
        <span :if={@game.broadcasts != []} class="text-base-content/40 truncate max-w-[100px]">
          {Enum.join(@game.broadcasts, ", ")}
        </span>
      </div>
      <div class="game-card-body">
        <%!-- Away Team --%>
        <div class="game-team-row">
          <div class="game-team-info">
            <img :if={@game.away_team.logo} src={@game.away_team.logo} class="game-team-logo" />
            <span class={[
              "game-team-name",
              highlight_team?(@game, @prediction, @game.away_team.abbreviation) && "text-info"
            ]}>
              {@game.away_team.abbreviation}
            </span>
            <span :if={@game.away_team.records} class="game-team-record">
              {get_record(@game.away_team.records)}
            </span>
          </div>
          <span class={["game-score", @game.away_team.winner && "winner"]}>
            {@game.away_team.score || "-"}
          </span>
        </div>

        <%!-- Prediction Progress Bar (only for non-completed games with predictions) --%>
        <div :if={@prediction && !@game.status.completed} class="relative flex items-center my-1.5 px-1">
          <div class="h-[1px] w-full flex">
            <div class="bg-info" style={"width: #{prediction_bar_percent(@prediction)}%"}></div>
            <div class="bg-base-200" style={"width: #{100 - prediction_bar_percent(@prediction)}%"}></div>
          </div>
          <span
            class="absolute -translate-x-1/2 text-[9px] text-base-content/50 font-mono bg-base-100 px-1"
            style={"left: calc(#{prediction_bar_percent(@prediction)}% + 0.25rem)"}
          >
            {@prediction.predicted_winner} {format_probability(@prediction.winner_probability)}
          </span>
        </div>

        <%!-- Home Team --%>
        <div class="game-team-row">
          <div class="game-team-info">
            <img :if={@game.home_team.logo} src={@game.home_team.logo} class="game-team-logo" />
            <span class={[
              "game-team-name",
              highlight_team?(@game, @prediction, @game.home_team.abbreviation) && "text-info"
            ]}>
              {@game.home_team.abbreviation}
            </span>
            <span :if={@game.home_team.records} class="game-team-record">
              {get_record(@game.home_team.records)}
            </span>
          </div>
          <span class={["game-score", @game.home_team.winner && "winner"]}>
            {@game.home_team.score || "-"}
          </span>
        </div>
      </div>
      <div class="game-status flex justify-between items-center">
        <span :if={@game.status.state == "in"} class="font-mono text-error">
          {period_display(@game.status.period)} {@game.status.display_clock || ""}
        </span>
        <span :if={@game.status.state != "in"}></span>
        <span :if={@game.venue} class="text-base-content/50 truncate">{@game.venue.name}</span>
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

  defp get_predicted_winner(nil), do: nil
  defp get_predicted_winner(%{predicted_winner: winner}), do: winner

  # Determines if a team should be highlighted (blue text)
  # For completed games: highlight the actual winner
  # For in-progress/scheduled: highlight the predicted winner
  defp highlight_team?(game, prediction, team_abbrev) do
    cond do
      game.status.completed ->
        # Show actual winner for completed games
        (game.away_team.winner && game.away_team.abbreviation == team_abbrev) ||
          (game.home_team.winner && game.home_team.abbreviation == team_abbrev)

      prediction != nil ->
        # Show predicted winner for non-completed games
        prediction.predicted_winner == team_abbrev

      true ->
        false
    end
  end

  defp prediction_bar_percent(%{winner_probability: prob}) when is_float(prob) do
    round(prob * 100)
  end

  defp prediction_bar_percent(_), do: 50

  defp format_probability(prob) when is_float(prob) do
    "#{round(prob * 100)}%"
  end

  defp format_probability(_), do: ""
end
