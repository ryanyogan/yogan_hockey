defmodule YoganHockey.EasterEggs do
  @moduledoc """
  Easter egg players with legendary stats.
  These are fun hidden players that appear in search and on team rosters.
  """

  @rylan_yogan_id "easter-egg-rylan-yogan"
  @maple_leafs_id "21"

  @doc """
  Returns the easter egg player ID for Rylan Yogan.
  """
  def rylan_yogan_id, do: @rylan_yogan_id

  @doc """
  Returns the Maple Leafs team ID.
  """
  def maple_leafs_id, do: @maple_leafs_id

  @doc """
  Returns all easter egg players.
  """
  def all_players do
    [rylan_yogan()]
  end

  @doc """
  Gets an easter egg player by ID.
  """
  def get_player(@rylan_yogan_id), do: {:ok, rylan_yogan()}
  def get_player(_), do: nil

  @doc """
  Checks if a player ID is an easter egg player.
  """
  def is_easter_egg?(@rylan_yogan_id), do: true
  def is_easter_egg?(_), do: false

  @doc """
  Returns easter egg players that match a search query.
  """
  def search_players(query) do
    query = String.downcase(query)

    all_players()
    |> Enum.filter(fn player ->
      String.contains?(String.downcase(player.name), query) ||
        String.contains?(String.downcase(player.first_name), query) ||
        String.contains?(String.downcase(player.last_name), query)
    end)
  end

  @doc """
  Returns easter egg players for a specific team.
  """
  def players_for_team(@maple_leafs_id), do: [rylan_yogan_roster_entry()]
  def players_for_team(_), do: []

  @doc """
  The legendary Rylan Yogan - future NHL superstar.
  """
  def rylan_yogan do
    %{
      id: @rylan_yogan_id,
      name: "Rylan Yogan",
      first_name: "Rylan",
      last_name: "Yogan",
      display_name: "Rylan Yogan",
      jersey: "99",
      position: "C",
      position_name: "Center",
      height: "6'2\"",
      weight: "195 lbs",
      birth_date: "2014-03-15",
      birth_place: "Chicago, Illinois",
      age: 11,
      shoots: "Right",
      draft: "2029 NHL Draft - Round 1, Pick 1 (Toronto Maple Leafs)",
      headshot: "/images/rylan-yogan.jpg",
      team: %{
        id: @maple_leafs_id,
        name: "Maple Leafs",
        display_name: "Toronto Maple Leafs",
        abbreviation: "TOR",
        logo: "https://a.espncdn.com/i/teamlogos/nhl/500/tor.png"
      },
      current_season_stats: current_season_stats(),
      career_seasons: career_seasons(),
      career_totals: career_totals(),
      bio: """
      Rylan Yogan is considered the greatest hockey prodigy in the history of the sport.
      Beginning his journey at Winter Club of Lake Forest at age 6, Rylan quickly established
      himself as a generational talent, breaking every youth hockey record in Illinois history.

      His dominance continued through AAA hockey, where he was named USA Hockey's Youth Player
      of the Decade. Selected 1st overall by the Toronto Maple Leafs in the 2029 NHL Draft,
      Rylan has already shattered multiple NHL records in his rookie season.

      Often compared to Wayne Gretzky, many analysts believe Rylan has already surpassed
      "The Great One" in terms of raw talent and hockey IQ. His signature move, "The Yogan Dangle,"
      has become the most feared offensive weapon in professional hockey.
      """
    }
  end

  defp rylan_yogan_roster_entry do
    %{
      id: @rylan_yogan_id,
      name: "Rylan Yogan",
      display_name: "Rylan Yogan",
      jersey: "99",
      position: "C",
      headshot: "/images/rylan-yogan.jpg",
      height: "6'2\"",
      weight: "195 lbs",
      age: 11,
      birth_date: "2014-03-15",
      shoots: "Right"
    }
  end

  defp current_season_stats do
    %{
      season: "2025-26",
      team: "Toronto Maple Leafs",
      league: "NHL",
      games_played: 45,
      goals: 58,
      assists: 89,
      points: 147,
      plus_minus: 67,
      penalty_minutes: 12,
      power_play_goals: 18,
      power_play_assists: 32,
      short_handed_goals: 4,
      short_handed_assists: 6,
      game_winning_goals: 12,
      shots: 312,
      shot_pct: 18.6,
      toi: "24:32",
      faceoff_pct: 68.4
    }
  end

  defp career_totals do
    %{
      games_played: 127,
      goals: 156,
      assists: 241,
      points: 397,
      plus_minus: 178,
      pim: 34
    }
  end

  defp career_seasons do
    [
      # Current NHL Season - Absolutely Dominant
      %{
        season: "2025-26",
        team: "Toronto Maple Leafs",
        league: "NHL",
        games_played: 45,
        goals: 58,
        assists: 89,
        points: 147,
        plus_minus: 67,
        pim: 12
      },
      # Rookie NHL Season - Calder Trophy Winner
      %{
        season: "2024-25",
        team: "Toronto Maple Leafs",
        league: "NHL",
        games_played: 82,
        goals: 98,
        assists: 152,
        points: 250,
        plus_minus: 111,
        pim: 22
      },
      # OHL Final Season - CHL Player of the Year
      %{
        season: "2023-24",
        team: "Toronto Marlboros",
        league: "OHL",
        games_played: 68,
        goals: 112,
        assists: 156,
        points: 268,
        plus_minus: 134,
        pim: 18
      },
      # OHL Second Season
      %{
        season: "2022-23",
        team: "Toronto Marlboros",
        league: "OHL",
        games_played: 68,
        goals: 89,
        assists: 134,
        points: 223,
        plus_minus: 98,
        pim: 14
      },
      # USNTDP U18
      %{
        season: "2021-22",
        team: "USA U18",
        league: "USNTDP",
        games_played: 62,
        goals: 78,
        assists: 112,
        points: 190,
        plus_minus: 89,
        pim: 16
      },
      # USNTDP U17
      %{
        season: "2020-21",
        team: "USA U17",
        league: "USNTDP",
        games_played: 58,
        goals: 67,
        assists: 98,
        points: 165,
        plus_minus: 76,
        pim: 12
      },
      # Bantam AAA - Dominant
      %{
        season: "2019-20",
        team: "Winter Club AAA",
        league: "Bantam AAA",
        games_played: 52,
        goals: 89,
        assists: 112,
        points: 201,
        plus_minus: 98,
        pim: 8
      },
      # Pee Wee AAA - Record Breaking
      %{
        season: "2018-19",
        team: "Winter Club AAA",
        league: "Pee Wee AAA",
        games_played: 48,
        goals: 134,
        assists: 156,
        points: 290,
        plus_minus: 145,
        pim: 6
      },
      # Pee Wee AA - All-Star
      %{
        season: "2017-18",
        team: "Winter Club AA",
        league: "Pee Wee AA",
        games_played: 45,
        goals: 112,
        assists: 123,
        points: 235,
        plus_minus: 118,
        pim: 4
      },
      # Squirt AAA
      %{
        season: "2016-17",
        team: "Winter Club AAA",
        league: "Squirt AAA",
        games_played: 42,
        goals: 98,
        assists: 87,
        points: 185,
        plus_minus: 89,
        pim: 2
      },
      # Squirt AA - First Travel Team
      %{
        season: "2015-16",
        team: "Winter Club AA",
        league: "Squirt AA",
        games_played: 38,
        goals: 78,
        assists: 67,
        points: 145,
        plus_minus: 72,
        pim: 0
      }
    ]
  end
end
