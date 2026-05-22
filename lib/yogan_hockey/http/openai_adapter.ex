defmodule YoganHockey.HTTP.OpenAIAdapter do
  @moduledoc """
  Behaviour for OpenAI API calls.

  This abstraction allows for easy testing and swapping of implementations.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type response :: {:ok, String.t()} | {:error, term()}

  @doc """
  Sends a chat completion request to the OpenAI API.

  Returns the text response from the model.
  """
  @callback chat_completion(messages :: [message()], opts :: keyword()) :: response()
end
