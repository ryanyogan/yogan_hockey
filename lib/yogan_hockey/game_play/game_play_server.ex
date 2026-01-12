defmodule YoganHockey.GamePlay.GamePlayServer do
  @moduledoc """
  Per-game GenServer for live game data.

  Polls ESPN API every 15 seconds while viewers are present.
  Automatically shuts down after 60 seconds with no viewers.
  """
  use GenServer

  require Logger

  alias YoganHockey.Cache
  alias YoganHockey.NHL.APIClient
  alias YoganHockey.NHL.Parsers

  @poll_interval :timer.seconds(15)
  @shutdown_grace_period :timer.seconds(60)

  # Client API

  @doc """
  Starts a GamePlayServer for the given game ID.
  """
  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  @doc """
  Returns the via tuple for Registry lookup.
  """
  def via_tuple(game_id) do
    {:via, Registry, {YoganHockey.GamePlayRegistry, game_id}}
  end

  @doc """
  Registers a viewer process for the given game.
  Starts the server if not already running.
  """
  def register_viewer(game_id, viewer_pid) do
    case Registry.lookup(YoganHockey.GamePlayRegistry, game_id) do
      [{pid, _}] ->
        GenServer.call(pid, {:register_viewer, viewer_pid})

      [] ->
        case DynamicSupervisor.start_child(
               YoganHockey.GamePlaySupervisor,
               {__MODULE__, game_id}
             ) do
          {:ok, pid} ->
            GenServer.call(pid, {:register_viewer, viewer_pid})

          {:error, {:already_started, pid}} ->
            GenServer.call(pid, {:register_viewer, viewer_pid})

          error ->
            Logger.error("Failed to start GamePlayServer for #{game_id}: #{inspect(error)}")
            error
        end
    end
  end

  @doc """
  Unregisters a viewer process.
  """
  def unregister_viewer(game_id, viewer_pid) do
    case Registry.lookup(YoganHockey.GamePlayRegistry, game_id) do
      [{pid, _}] -> GenServer.cast(pid, {:unregister_viewer, viewer_pid})
      [] -> :ok
    end
  end

  @doc """
  Gets the current game data.
  """
  def get_game_data(game_id) do
    Cache.get(:game_play_data, game_id)
  end

  # Server Callbacks

  @impl true
  def init(game_id) do
    Logger.info("Starting GamePlayServer for game #{game_id}")

    state = %{
      game_id: game_id,
      viewers: MapSet.new(),
      monitors: %{},
      shutdown_timer: nil
    }

    # Initial fetch
    send(self(), :poll)

    {:ok, state}
  end

  @impl true
  def handle_call({:register_viewer, viewer_pid}, _from, state) do
    state = cancel_shutdown_timer(state)

    if MapSet.member?(state.viewers, viewer_pid) do
      {:reply, :ok, state}
    else
      ref = Process.monitor(viewer_pid)

      Logger.debug("Viewer registered for game #{state.game_id}, total: #{MapSet.size(state.viewers) + 1}")

      state = %{
        state
        | viewers: MapSet.put(state.viewers, viewer_pid),
          monitors: Map.put(state.monitors, ref, viewer_pid)
      }

      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:unregister_viewer, viewer_pid}, state) do
    {:noreply, remove_viewer(state, viewer_pid)}
  end

  @impl true
  def handle_info(:poll, state) do
    if MapSet.size(state.viewers) > 0 do
      fetch_and_broadcast(state.game_id)
      schedule_poll()
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      viewer_pid ->
        state = %{state | monitors: Map.delete(state.monitors, ref)}
        {:noreply, remove_viewer(state, viewer_pid)}
    end
  end

  @impl true
  def handle_info(:shutdown_check, state) do
    if MapSet.size(state.viewers) == 0 do
      Logger.info("Shutting down GamePlayServer for game #{state.game_id} (no viewers)")
      {:stop, :normal, state}
    else
      {:noreply, %{state | shutdown_timer: nil}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Cache.delete(:game_play_data, state.game_id)
    :ok
  end

  # Private Functions

  defp remove_viewer(state, viewer_pid) do
    if MapSet.member?(state.viewers, viewer_pid) do
      viewers = MapSet.delete(state.viewers, viewer_pid)

      Logger.debug("Viewer unregistered from game #{state.game_id}, remaining: #{MapSet.size(viewers)}")

      state = %{state | viewers: viewers}

      if MapSet.size(viewers) == 0 do
        schedule_shutdown(state)
      else
        state
      end
    else
      state
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp schedule_shutdown(state) do
    state = cancel_shutdown_timer(state)
    timer_ref = Process.send_after(self(), :shutdown_check, @shutdown_grace_period)
    %{state | shutdown_timer: timer_ref}
  end

  defp cancel_shutdown_timer(%{shutdown_timer: nil} = state), do: state

  defp cancel_shutdown_timer(%{shutdown_timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | shutdown_timer: nil}
  end

  defp fetch_and_broadcast(game_id) do
    case APIClient.get_game_summary(game_id) do
      {:ok, data} ->
        game_data = Parsers.parse_game_summary(data)
        Cache.put(:game_play_data, game_id, game_data)

        Phoenix.PubSub.broadcast(
          YoganHockey.PubSub,
          "game_play:#{game_id}",
          {:game_play_updated, game_data}
        )

      {:error, reason} ->
        Logger.warning("Failed to fetch game summary for #{game_id}: #{inspect(reason)}")
    end
  end
end
