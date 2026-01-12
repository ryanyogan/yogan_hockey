defmodule YoganHockeyWeb.HockeyComponents do
  @moduledoc """
  ESPN-style hockey UI components.

  This module serves as the main entry point for hockey-related components.
  Components are organized into domain-specific modules:

  - `YoganHockeyWeb.ScoreboardComponents` - Live game scores and game cards
  - `YoganHockeyWeb.PlayerComponents` - Player cards, stats tables, favorites
  - `YoganHockeyWeb.StandingsComponents` - Standings widgets and team grids

  All components are re-exported here for backwards compatibility.
  """
  use YoganHockeyWeb, :html

  # Re-export all components from domain-specific modules
  defdelegate scoreboard_ticker(assigns), to: YoganHockeyWeb.ScoreboardComponents
  defdelegate game_card(assigns), to: YoganHockeyWeb.ScoreboardComponents

  defdelegate featured_player(assigns), to: YoganHockeyWeb.PlayerComponents
  defdelegate stats_table(assigns), to: YoganHockeyWeb.PlayerComponents
  defdelegate player_card(assigns), to: YoganHockeyWeb.PlayerComponents
  defdelegate player_card_skeleton(assigns), to: YoganHockeyWeb.PlayerComponents
  defdelegate favorite_button(assigns), to: YoganHockeyWeb.PlayerComponents
  defdelegate player_search(assigns), to: YoganHockeyWeb.PlayerComponents
  defdelegate empty_favorites(assigns), to: YoganHockeyWeb.PlayerComponents

  defdelegate standings_widget(assigns), to: YoganHockeyWeb.StandingsComponents
  defdelegate standings_table(assigns), to: YoganHockeyWeb.StandingsComponents
  defdelegate team_grid(assigns), to: YoganHockeyWeb.StandingsComponents

  defdelegate playoff_bracket(assigns), to: YoganHockeyWeb.BracketComponents
  defdelegate bracket_round(assigns), to: YoganHockeyWeb.BracketComponents
  defdelegate series_matchup(assigns), to: YoganHockeyWeb.BracketComponents
  defdelegate prediction_card(assigns), to: YoganHockeyWeb.BracketComponents

  # ============================================
  # UTILITY COMPONENTS
  # ============================================

  @doc """
  Renders a section header.
  """
  attr :title, :string, required: true
  attr :link_text, :string, default: nil
  attr :link_to, :string, default: nil

  def section_header(assigns) do
    ~H"""
    <div class="section-header">
      <span class="section-title">{@title}</span>
      <.link :if={@link_to} navigate={@link_to} class="section-link">{@link_text}</.link>
    </div>
    """
  end

  @doc """
  Renders a loading skeleton.
  """
  attr :class, :string, default: ""

  def loading_skeleton(assigns) do
    ~H"""
    <div class={["loading-skeleton h-24", @class]}></div>
    """
  end

  @doc """
  Renders a stat box.
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :string, default: ""

  def stat_box(assigns) do
    ~H"""
    <div class={["text-center p-3 bg-base-200 border border-base-300", @class]}>
      <div class="text-2xl font-mono font-bold">{@value}</div>
      <div class="text-[10px] uppercase tracking-wider text-base-content/50 mt-1">{@label}</div>
    </div>
    """
  end
end
