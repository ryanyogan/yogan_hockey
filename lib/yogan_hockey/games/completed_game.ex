defmodule YoganHockey.Games.CompletedGame do
  @moduledoc """
  Schema for persisting completed NHL game data.

  Stores full game data including play-by-play, team stats, and boxscores
  as a JSON blob for flexibility and fast writes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:game_id, :string, autogenerate: false}
  schema "completed_games" do
    field :home_team_id, :string
    field :away_team_id, :string
    field :home_team_name, :string
    field :away_team_name, :string
    field :home_score, :integer
    field :away_score, :integer
    field :game_date, :utc_datetime
    field :game_data, :map

    timestamps()
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :game_id,
      :home_team_id,
      :away_team_id,
      :home_team_name,
      :away_team_name,
      :home_score,
      :away_score,
      :game_date,
      :game_data
    ])
    |> validate_required([:game_id, :home_team_id, :away_team_id, :game_data])
  end
end
