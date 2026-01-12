defmodule YoganHockey.CacheTest do
  use ExUnit.Case, async: false

  alias YoganHockey.Cache

  @test_table :cache_test_table

  setup do
    # Create a test table
    if :ets.whereis(@test_table) != :undefined do
      :ets.delete(@test_table)
    end

    :ets.new(@test_table, [:set, :public, :named_table, read_concurrency: true])

    on_exit(fn ->
      if :ets.whereis(@test_table) != :undefined do
        :ets.delete(@test_table)
      end
    end)

    :ok
  end

  describe "get/2" do
    test "returns nil for non-existent key" do
      assert Cache.get(@test_table, :nonexistent) == nil
    end

    test "returns stored value" do
      :ets.insert(@test_table, {:my_key, "my_value"})
      assert Cache.get(@test_table, :my_key) == "my_value"
    end

    test "returns nil for undefined table" do
      assert Cache.get(:nonexistent_table, :key) == nil
    end

    test "handles complex keys" do
      :ets.insert(@test_table, {{:team_details, "123"}, %{name: "Team"}})
      assert Cache.get(@test_table, {:team_details, "123"}) == %{name: "Team"}
    end
  end

  describe "put/3" do
    test "stores value in table" do
      assert Cache.put(@test_table, :key, "value") == :ok
      assert Cache.get(@test_table, :key) == "value"
    end

    test "overwrites existing value" do
      Cache.put(@test_table, :key, "first")
      Cache.put(@test_table, :key, "second")
      assert Cache.get(@test_table, :key) == "second"
    end

    test "stores complex values" do
      value = %{roster: [%{name: "Player 1"}], stats: %{wins: 10}}
      Cache.put(@test_table, :team, value)
      assert Cache.get(@test_table, :team) == value
    end
  end

  describe "get_or_put/3" do
    test "returns cached value without calling function" do
      Cache.put(@test_table, :cached, "existing")

      result =
        Cache.get_or_put(@test_table, :cached, fn ->
          raise "Should not be called"
        end)

      assert result == "existing"
    end

    test "calls function and caches result for missing key" do
      result = Cache.get_or_put(@test_table, :new_key, fn -> "computed" end)

      assert result == "computed"
      assert Cache.get(@test_table, :new_key) == "computed"
    end

    test "function is only called once for same key" do
      # This tests that subsequent calls return cached value
      counter = :counters.new(1, [:atomics])

      Cache.get_or_put(@test_table, :counted, fn ->
        :counters.add(counter, 1, 1)
        "result"
      end)

      Cache.get_or_put(@test_table, :counted, fn ->
        :counters.add(counter, 1, 1)
        "result2"
      end)

      assert :counters.get(counter, 1) == 1
    end
  end

  describe "delete/2" do
    test "removes key from table" do
      Cache.put(@test_table, :to_delete, "value")
      assert Cache.delete(@test_table, :to_delete) == :ok
      assert Cache.get(@test_table, :to_delete) == nil
    end

    test "returns ok for non-existent key" do
      assert Cache.delete(@test_table, :never_existed) == :ok
    end
  end

  describe "all/1" do
    test "returns all values" do
      Cache.put(@test_table, :a, 1)
      Cache.put(@test_table, :b, 2)

      values = Cache.all(@test_table)
      assert Enum.sort(values) == [1, 2]
    end

    test "returns empty list for empty table" do
      assert Cache.all(@test_table) == []
    end
  end

  describe "clear/1" do
    test "removes all entries" do
      Cache.put(@test_table, :a, 1)
      Cache.put(@test_table, :b, 2)

      assert Cache.clear(@test_table) == :ok
      assert Cache.all(@test_table) == []
    end

    test "works on empty table" do
      assert Cache.clear(@test_table) == :ok
    end
  end

  describe "tables/0" do
    test "returns list of configured table names" do
      tables = Cache.tables()
      assert is_list(tables)
      assert :nhl_teams in tables
      assert :nhl_live_scores in tables
      assert :player_cache in tables
    end
  end
end
