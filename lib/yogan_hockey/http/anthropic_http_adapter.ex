defmodule YoganHockey.HTTP.AnthropicHTTPAdapter do
  @moduledoc """
  HTTP adapter implementation for the Anthropic API.

  Makes requests to the Claude API for AI-powered predictions.
  """

  @behaviour YoganHockey.HTTP.AnthropicAdapter

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @default_model "claude-sonnet-4-20250514"
  @default_max_tokens 1024

  @impl true
  def chat_completion(messages, opts \\ []) do
    api_key = Application.get_env(:yogan_hockey, :anthropic_api_key)

    if is_nil(api_key) do
      Logger.warning("Anthropic API key not configured")
      {:error, :api_key_not_configured}
    else
      do_request(messages, api_key, opts)
    end
  end

  defp do_request(messages, api_key, opts) do
    model = Keyword.get(opts, :model, @default_model)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    system = Keyword.get(opts, :system)

    headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_version}
    ]

    body =
      %{
        model: model,
        max_tokens: max_tokens,
        messages: messages
      }
      |> maybe_add_system(system)
      |> Jason.encode!()

    case Req.post(url: @api_url, headers: headers, body: body, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        extract_response(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Anthropic API error #{status}: #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Anthropic HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_add_system(body, nil), do: body
  defp maybe_add_system(body, system), do: Map.put(body, :system, system)

  defp extract_response(%{"content" => [%{"type" => "text", "text" => text} | _]}) do
    {:ok, text}
  end

  defp extract_response(body) do
    Logger.error("Unexpected Anthropic response format: #{inspect(body)}")
    {:error, :unexpected_response_format}
  end
end
