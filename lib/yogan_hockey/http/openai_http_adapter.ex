defmodule YoganHockey.HTTP.OpenAIHTTPAdapter do
  @moduledoc """
  HTTP adapter implementation for the OpenAI API.

  Makes requests to the OpenAI API for AI-powered predictions.
  """

  @behaviour YoganHockey.HTTP.OpenAIAdapter

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-5.5"
  @default_max_tokens 1024

  @impl true
  def chat_completion(messages, opts \\ []) do
    api_key = Application.get_env(:yogan_hockey, :openai_api_key)

    if is_nil(api_key) do
      Logger.warning("OpenAI API key not configured")
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
      {"authorization", "Bearer #{api_key}"}
    ]

    all_messages = prepend_system_message(messages, system)

    body =
      %{
        model: model,
        max_completion_tokens: max_tokens,
        messages: all_messages
      }
      |> Jason.encode!()

    case Req.post(url: @api_url, headers: headers, body: body, receive_timeout: 120_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        extract_response(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("OpenAI API error #{status}: #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("OpenAI HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp prepend_system_message(messages, nil), do: messages

  defp prepend_system_message(messages, system) do
    [%{role: "system", content: system} | messages]
  end

  defp extract_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, content}
  end

  defp extract_response(body) do
    Logger.error("Unexpected OpenAI response format: #{inspect(body)}")
    {:error, :unexpected_response_format}
  end
end
