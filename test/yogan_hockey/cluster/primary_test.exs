defmodule YoganHockey.Cluster.PrimaryTest do
  @moduledoc """
  Tests for the Primary module which handles distributed operations.

  These tests verify:
  - Primary region detection
  - RPC forwarding logic
  - Node discovery
  """
  use ExUnit.Case, async: false

  alias YoganHockey.Cluster.Primary

  setup do
    # Store original env vars
    original_fly_region = System.get_env("FLY_REGION")
    original_primary_region = System.get_env("PRIMARY_REGION")

    on_exit(fn ->
      # Restore original env vars
      if original_fly_region do
        System.put_env("FLY_REGION", original_fly_region)
      else
        System.delete_env("FLY_REGION")
      end

      if original_primary_region do
        System.put_env("PRIMARY_REGION", original_primary_region)
      else
        System.delete_env("PRIMARY_REGION")
      end
    end)

    :ok
  end

  describe "primary?/0" do
    test "returns true when FLY_REGION is nil (local development)" do
      System.delete_env("FLY_REGION")
      System.delete_env("PRIMARY_REGION")

      assert Primary.primary?() == true
    end

    test "returns true when FLY_REGION matches PRIMARY_REGION" do
      System.put_env("FLY_REGION", "dfw")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == true
    end

    test "returns true when FLY_REGION matches default primary (dfw)" do
      System.put_env("FLY_REGION", "dfw")
      System.delete_env("PRIMARY_REGION")

      assert Primary.primary?() == true
    end

    test "returns false when FLY_REGION does not match PRIMARY_REGION" do
      System.put_env("FLY_REGION", "ewr")
      System.put_env("PRIMARY_REGION", "dfw")

      assert Primary.primary?() == false
    end

    test "returns false when FLY_REGION does not match default primary" do
      System.put_env("FLY_REGION", "lhr")
      System.delete_env("PRIMARY_REGION")

      assert Primary.primary?() == false
    end
  end

  describe "primary_region/0" do
    test "returns PRIMARY_REGION env var when set" do
      System.put_env("PRIMARY_REGION", "ord")

      assert Primary.primary_region() == "ord"
    end

    test "returns default 'dfw' when PRIMARY_REGION not set" do
      System.delete_env("PRIMARY_REGION")

      assert Primary.primary_region() == "dfw"
    end
  end

  describe "primary_node/0" do
    test "returns Node.self() when on primary region" do
      System.delete_env("FLY_REGION")
      System.delete_env("PRIMARY_REGION")

      assert Primary.primary_node() == Node.self()
    end

    test "returns nil when not on primary and no other nodes connected" do
      System.put_env("FLY_REGION", "ewr")
      System.put_env("PRIMARY_REGION", "dfw")

      # No other nodes connected in test environment
      assert Primary.primary_node() == nil
    end
  end

  describe "on_primary/3" do
    test "executes locally when on primary region" do
      System.delete_env("FLY_REGION")
      System.delete_env("PRIMARY_REGION")

      # Should execute String.upcase locally
      result = Primary.on_primary(String, :upcase, ["hello"])

      assert result == "HELLO"
    end

    test "executes locally with complex function" do
      System.delete_env("FLY_REGION")

      # Test with a function that returns a tuple
      result = Primary.on_primary(Enum, :split, [[1, 2, 3, 4, 5], 3])

      assert result == {[1, 2, 3], [4, 5]}
    end

    test "returns error when not on primary and no primary node available" do
      System.put_env("FLY_REGION", "ewr")
      System.put_env("PRIMARY_REGION", "dfw")

      result = Primary.on_primary(String, :upcase, ["hello"])

      assert result == {:error, :no_primary_available}
    end
  end

  describe "cast_to_primary/3" do
    test "executes via Task.Supervisor when on primary" do
      System.delete_env("FLY_REGION")
      System.delete_env("PRIMARY_REGION")

      # Create an agent to track if function was called
      {:ok, agent} = Agent.start_link(fn -> false end)

      result = Primary.cast_to_primary(Agent, :update, [agent, fn _ -> true end])

      # cast_to_primary returns {:ok, pid} when starting a task
      assert match?({:ok, _pid}, result)

      # Wait for the task to complete
      Process.sleep(50)

      # Verify the agent was updated
      assert Agent.get(agent, & &1) == true

      Agent.stop(agent)
    end

    test "returns error when not on primary and no primary available" do
      System.put_env("FLY_REGION", "ewr")
      System.put_env("PRIMARY_REGION", "dfw")

      result = Primary.cast_to_primary(IO, :puts, ["test"])

      assert result == {:error, :no_primary_available}
    end
  end

  describe "node_region/1" do
    test "returns nil for invalid node" do
      # Non-existent node returns nil (caught in node_region/1)
      result = Primary.node_region(:nonexistent@nowhere)

      # node_region catches errors and returns nil
      assert result == nil
    end
  end
end
