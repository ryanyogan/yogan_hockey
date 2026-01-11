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

  def game_card(assigns) do
    ~H"""
    <div class={[game_card_class(@game), @class]}>
      <div class="game-card-header">
        <span :if={@game.status.state == "in"} class="live-indicator">Live</span>
        <span :if={@game.status.completed} class="text-base-content/50">Final</span>
        <span :if={@game.status.state == "pre"} class="text-base-content/50">{@game.status.detail}</span>
        <span :if={@game.broadcasts != []} class="text-base-content/40">
          {Enum.join(@game.broadcasts, ", ")}
        </span>
      </div>
      <div class="game-card-body">
        <%!-- Away Team --%>
        <div class="game-team-row">
          <div class="game-team-info">
            <img :if={@game.away_team.logo} src={@game.away_team.logo} class="game-team-logo" />
            <span class="game-team-name">{@game.away_team.abbreviation}</span>
            <span :if={@game.away_team.records} class="game-team-record">
              {get_record(@game.away_team.records)}
            </span>
          </div>
          <span class={["game-score", @game.away_team.winner && "winner"]}>
            {@game.away_team.score || "-"}
          </span>
        </div>
        <%!-- Home Team --%>
        <div class="game-team-row">
          <div class="game-team-info">
            <img :if={@game.home_team.logo} src={@game.home_team.logo} class="game-team-logo" />
            <span class="game-team-name">{@game.home_team.abbreviation}</span>
            <span :if={@game.home_team.records} class="game-team-record">
              {get_record(@game.home_team.records)}
            </span>
          </div>
          <span class={["game-score", @game.home_team.winner && "winner"]}>
            {@game.home_team.score || "-"}
          </span>
        </div>
      </div>
      <div :if={@game.status.state == "in"} class="game-status live">
        {period_display(@game.status.period)} - {@game.status.display_clock || ""}
      </div>
      <div :if={@game.venue} class="game-status">
        {@game.venue.name}
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
end
