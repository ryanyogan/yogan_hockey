defmodule YoganHockey.GamePlay.GamePlaySupervisor do
  @moduledoc """
  DynamicSupervisor for per-game GamePlayServer processes.

  Spawns one GamePlayServer per active game being viewed.
  Servers are started on-demand when viewers connect and
  shut down automatically when no viewers remain.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: YoganHockey.GamePlaySupervisor)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
