defmodule YoganHockey.HTTP.MockAdapter do
  @moduledoc """
  Mock HTTP adapter for testing.
  Uses Agent to store expected responses.
  """

  @behaviour YoganHockey.HTTP.Adapter

  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
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
  Sets the expected response for a URL pattern.
  The pattern can be a substring of the URL.
  """
  def expect(url_pattern, response) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, url_pattern, response)
    end)
  end

  @doc """
  Clears all expectations.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  @impl true
  def get_json(url, _headers \\ [], _opts \\ []) do
    find_response(url)
  end

  @impl true
  def get_html(url, _headers \\ [], _opts \\ []) do
    find_response(url)
  end

  defp find_response(url) do
    expectations = Agent.get(__MODULE__, & &1)

    # Find first matching pattern (substring match)
    Enum.find_value(expectations, {:error, {:no_mock_found, url}}, fn {pattern, response} ->
      if String.contains?(url, pattern), do: response
    end)
  end
end
