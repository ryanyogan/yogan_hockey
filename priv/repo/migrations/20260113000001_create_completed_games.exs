defmodule YoganHockey.Repo.Migrations.CreateCompletedGames do
  use Ecto.Migration

  def change do
    create table(:completed_games, primary_key: false) do
      add :game_id, :string, primary_key: true
      add :home_team_id, :string, null: false
      add :away_team_id, :string, null: false
      add :home_team_name, :string
      add :away_team_name, :string
      add :home_score, :integer
      add :away_score, :integer
      add :game_date, :utc_datetime
      add :game_data, :map, null: false

      timestamps()
    end

    create index(:completed_games, [:home_team_id])
    create index(:completed_games, [:away_team_id])
    create index(:completed_games, [:game_date])
  end
end
