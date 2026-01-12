defmodule YoganHockey.Cache do
  @moduledoc """
  ETS-based cache for storing hockey data.

  Provides a simple key-value store with automatic table creation
  and common cache operations for storing API responses.
  """

  @tables [
    :nhl_live_scores,
    :nhl_teams,
    :nhl_standings,
    :nhl_team_stats,
    :nhl_injuries,
    :player_cache,
    :yogan_stats,
    :del2_team,
    :playoffs,
    :playoffs_predictions,
    :live_game_predictions
  ]

  @doc """
  Creates all ETS tables used by the application.
  Called during application startup.
  """
  def init do
    Enum.each(@tables, fn table ->
      :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
    end)

    :ok
  end

  @doc """
  Gets a value from the specified cache table.
  Returns `nil` if the key doesn't exist.
  """
  @spec get(atom(), term()) :: term() | nil
  def get(table, key) do
    case :ets.whereis(table) do
      :undefined -> nil
      _ ->
        case :ets.lookup(table, key) do
          [{^key, value}] -> value
          [] -> nil
        end
    end
  end

  @doc """
  Gets a value from cache, or calls the function to compute and store it.
  """
  @spec get_or_put(atom(), term(), (-> term())) :: term()
  def get_or_put(table, key, fun) do
    case get(table, key) do
      nil ->
        value = fun.()
        put(table, key, value)
        value

      value ->
        value
    end
  end

  @doc """
  Stores a value in the specified cache table.
  """
  @spec put(atom(), term(), term()) :: :ok
  def put(table, key, value) do
    # Ensure table exists (handles hot code reload during development)
    ensure_table(table)
    :ets.insert(table, {key, value})
    :ok
  end

  defp ensure_table(table) do
    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
      _ ->
        :ok
    end
  end

  @doc """
  Deletes a key from the specified cache table.
  """
  @spec delete(atom(), term()) :: :ok
  def delete(table, key) do
    case :ets.whereis(table) do
      :undefined -> :ok
      _ -> :ets.delete(table, key)
    end
    :ok
  end

  @doc """
  Returns all values from the specified cache table.
  """
  @spec all(atom()) :: [term()]
  def all(table) do
    case :ets.whereis(table) do
      :undefined -> []
      _ ->
        :ets.tab2list(table)
        |> Enum.map(fn {_key, value} -> value end)
    end
  end

  @doc """
  Clears all entries from the specified cache table.
  """
  @spec clear(atom()) :: :ok
  def clear(table) do
    case :ets.whereis(table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(table)
    end
    :ok
  end

  @doc """
  Returns the list of cache table names.
  """
  @spec tables() :: [atom()]
  def tables, do: @tables
end
