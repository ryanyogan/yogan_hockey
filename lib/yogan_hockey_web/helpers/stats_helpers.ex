defmodule YoganHockeyWeb.Helpers.StatsHelpers do
  @moduledoc """
  Shared helper functions for formatting and calculating hockey statistics.

  These functions are used across multiple LiveViews and components to ensure
  consistent formatting of stats like +/-, dates, career totals, etc.
  """

  @doc """
  Formats a plus/minus value with the appropriate sign.

  ## Examples

      iex> format_plus_minus(5)
      "+5"

      iex> format_plus_minus(-3)
      "-3"

      iex> format_plus_minus(0)
      "0"

      iex> format_plus_minus(nil)
      "0"
  """
  @spec format_plus_minus(integer() | nil) :: String.t()
  def format_plus_minus(value) when is_integer(value) and value > 0, do: "+#{value}"
  def format_plus_minus(value) when is_integer(value), do: "#{value}"
  def format_plus_minus(_), do: "0"

  @doc """
  Returns the CSS class for a plus/minus value.

  ## Examples

      iex> plus_minus_class(5)
      "text-success"

      iex> plus_minus_class(-3)
      "text-error"

      iex> plus_minus_class(0)
      ""
  """
  @spec plus_minus_class(integer() | nil) :: String.t()
  def plus_minus_class(value) when is_integer(value) and value > 0, do: "text-success"
  def plus_minus_class(value) when is_integer(value) and value < 0, do: "text-error"
  def plus_minus_class(_), do: ""

  @doc """
  Calculates the sum of a stat across all seasons.

  ## Examples

      iex> career_total([%{goals: 10}, %{goals: 15}], :goals)
      25

      iex> career_total([%{goals: nil}, %{goals: 5}], :goals)
      5
  """
  @spec career_total([map()], atom()) :: integer()
  def career_total(stats, key) when is_list(stats) do
    Enum.reduce(stats, 0, fn season, acc ->
      acc + (Map.get(season, key) || 0)
    end)
  end
  def career_total(_, _), do: 0

  @doc """
  Calculates points per game from career stats.

  ## Examples

      iex> points_per_game([%{games_played: 80, points: 100}])
      1.25

      iex> points_per_game([])
      0.0
  """
  @spec points_per_game([map()]) :: float()
  def points_per_game(stats) when is_list(stats) do
    total_games = career_total(stats, :games_played)
    total_points = career_total(stats, :points)
    if total_games > 0, do: Float.round(total_points / total_games, 2), else: 0.0
  end
  def points_per_game(_), do: 0.0

  @doc """
  Formats an ISO8601 date string to a human-readable format.

  ## Examples

      iex> format_date("2024-01-15")
      "January 15, 2024"

      iex> format_date(nil)
      nil
  """
  @spec format_date(String.t() | nil) :: String.t() | nil
  def format_date(nil), do: nil
  def format_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> date_string
    end
  end
  def format_date(date), do: date

  @doc """
  Formats a DateTime to a human-readable format with time.

  ## Examples

      iex> format_datetime(~U[2024-01-15 14:30:00Z])
      "January 15, 2024 at 14:30 UTC"
  """
  @spec format_datetime(DateTime.t() | nil) :: String.t() | nil
  def format_datetime(nil), do: nil
  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %H:%M UTC")
  end
  def format_datetime(_), do: nil

  @doc """
  Formats a short date from a DateTime or ISO string.

  ## Examples

      iex> format_short_date("2024-01-15T14:30:00Z")
      "Jan 15"
  """
  @spec format_short_date(String.t() | DateTime.t() | nil) :: String.t()
  def format_short_date(nil), do: ""
  def format_short_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d")
  end
  def format_short_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> Calendar.strftime(datetime, "%b %d")
      _ -> date_string
    end
  end
  def format_short_date(_), do: ""

  @doc """
  Extracts a stat value from a stats map, returning a display-friendly value.

  ## Examples

      iex> get_stat(%{"wins" => 45}, "wins")
      45

      iex> get_stat(%{"pct" => 0.567}, "pct")
      1 # rounded

      iex> get_stat(nil, "wins")
      "-"
  """
  @spec get_stat(map() | nil, String.t() | atom()) :: integer() | String.t()
  def get_stat(nil, _key), do: "-"
  def get_stat(stats, key) when is_map(stats) do
    case Map.get(stats, key) do
      nil -> "-"
      value when is_float(value) -> round(value)
      value -> value
    end
  end
  def get_stat(_, _), do: "-"

  @doc """
  Extracts team name from various team map formats.

  ## Examples

      iex> get_team_name(%{name: "Edmonton Oilers"})
      "Edmonton Oilers"

      iex> get_team_name(%{abbreviation: "EDM"})
      "EDM"

      iex> get_team_name("Some Team")
      "Some Team"
  """
  @spec get_team_name(map() | String.t() | nil) :: String.t()
  def get_team_name(%{name: name}) when is_binary(name) and name != "", do: name
  def get_team_name(%{abbreviation: abbr}) when is_binary(abbr) and abbr != "", do: abbr
  def get_team_name(name) when is_binary(name), do: name
  def get_team_name(_), do: "NHL"

  @doc """
  Formats a number with sign for goal differential.

  ## Examples

      iex> format_diff(15)
      "+15"

      iex> format_diff(-5)
      "-5"
  """
  @spec format_diff(number() | nil) :: String.t()
  def format_diff(n) when is_number(n) and n > 0, do: "+#{round(n)}"
  def format_diff(n) when is_number(n), do: "#{round(n)}"
  def format_diff(_), do: "-"

  @doc """
  Returns the CSS class for a goal differential value.
  """
  @spec diff_class(number() | nil) :: String.t()
  def diff_class(n) when is_number(n) and n > 0, do: "text-success"
  def diff_class(n) when is_number(n) and n < 0, do: "text-error"
  def diff_class(_), do: ""

  @doc """
  Converts a period number to display format.

  ## Examples

      iex> period_display(1)
      "1st"

      iex> period_display(4)
      "OT"

      iex> period_display(6)
      "2OT"
  """
  @spec period_display(integer() | nil) :: String.t()
  def period_display(1), do: "1st"
  def period_display(2), do: "2nd"
  def period_display(3), do: "3rd"
  def period_display(4), do: "OT"
  def period_display(5), do: "SO"
  def period_display(n) when is_integer(n) and n > 5, do: "#{n - 3}OT"
  def period_display(_), do: ""
end
