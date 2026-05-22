defmodule YoganHockey.HTTP.MockOpenAIAdapter do
  @moduledoc """
  Mock OpenAI adapter for testing AI prediction functionality.
  Uses Agent to store expected responses.
  """

  @behaviour YoganHockey.HTTP.OpenAIAdapter

  def start_link do
    Agent.start_link(fn -> %{responses: [], call_count: 0} end, name: __MODULE__)
  end

  def stop do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid when is_pid(pid) ->
        try do
          Agent.stop(__MODULE__)
        catch
          :exit, _ -> :ok
        end
    end
  end

  @doc """
  Sets the response to return for the next chat_completion call.
  Can be called multiple times to queue responses.
  """
  def expect(response) do
    Agent.update(__MODULE__, fn state ->
      %{state | responses: state.responses ++ [response]}
    end)
  end

  @doc """
  Returns the number of times chat_completion was called.
  """
  def call_count do
    Agent.get(__MODULE__, & &1.call_count)
  end

  @doc """
  Clears all expectations and resets call count.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{responses: [], call_count: 0} end)
  end

  @impl true
  def chat_completion(_messages, _opts \\ []) do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :mock_not_running}

      _pid ->
        Agent.get_and_update(__MODULE__, fn state ->
          new_count = state.call_count + 1

          case state.responses do
            [] ->
              {default_response(), %{state | call_count: new_count}}

            [response | rest] ->
              {response, %{state | responses: rest, call_count: new_count}}
          end
        end)
    end
  end

  defp default_response do
    {:ok, ~s|{"winner": "TOR", "win_probability": 65, "loser": "MTL", "lose_probability": 35}|}
  end
end
