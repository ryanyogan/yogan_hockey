defmodule YoganHockey.Cluster.Primary do
  @moduledoc """
  Utilities for primary-region operations.

  In a multi-region deployment, SQLite writes must happen on the primary.
  This module provides helpers to forward write operations via RPC.

  ## Architecture

  - Primary region: Has SQLite volume, runs GenServer singletons
  - Replica regions: Serve web requests, use RPC for database writes

  ## Usage

      # Check if current node is primary
      Primary.primary?()

      # Execute function on primary node
      Primary.on_primary(MyModule, :my_function, [arg1, arg2])
  """

  require Logger

  @doc """
  Returns true if this node is in the primary region.

  Returns true in local development (no FLY_REGION set).
  """
  def primary? do
    System.get_env("FLY_REGION") == primary_region() or
      System.get_env("FLY_REGION") == nil
  end

  @doc """
  Returns the configured primary region from PRIMARY_REGION env var.
  Defaults to "dfw" if not set.
  """
  def primary_region do
    System.get_env("PRIMARY_REGION", "dfw")
  end

  @doc """
  Returns a node in the primary region, or nil if none connected.

  If already on primary, returns Node.self().
  """
  def primary_node do
    if primary?() do
      Node.self()
    else
      Node.list()
      |> Enum.find(fn node ->
        node_region(node) == primary_region()
      end)
    end
  end

  @doc """
  Returns the region of a remote node by querying its FLY_REGION env var.
  Returns nil if the node is unreachable or RPC fails.
  """
  def node_region(node) do
    case :rpc.call(node, System, :get_env, ["FLY_REGION"], 5000) do
      {:badrpc, _reason} -> nil
      region -> region
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  @doc """
  Execute a function on the primary node.

  If already on primary, executes locally.
  If on a replica, forwards the call via :rpc.call/5.

  Returns {:error, :no_primary_available} if no primary node is connected.

  ## Examples

      # Forward database write to primary
      Primary.on_primary(YoganHockey.Games, :do_save_completed_game, [game_data])
  """
  def on_primary(module, function, args, timeout \\ 10_000) do
    if primary?() do
      apply(module, function, args)
    else
      case primary_node() do
        nil ->
          Logger.warning("No primary node available for RPC call to #{module}.#{function}")
          {:error, :no_primary_available}

        node ->
          Logger.debug("Forwarding #{module}.#{function} to primary node #{node}")
          :rpc.call(node, module, function, args, timeout)
      end
    end
  end

  @doc """
  Execute a function on the primary node asynchronously.

  Returns immediately without waiting for the result.
  """
  def cast_to_primary(module, function, args) do
    if primary?() do
      Task.Supervisor.start_child(
        YoganHockey.TaskSupervisor,
        fn -> apply(module, function, args) end
      )
    else
      case primary_node() do
        nil ->
          Logger.warning("No primary node available for RPC cast to #{module}.#{function}")
          {:error, :no_primary_available}

        node ->
          :rpc.cast(node, module, function, args)
          :ok
      end
    end
  end
end
