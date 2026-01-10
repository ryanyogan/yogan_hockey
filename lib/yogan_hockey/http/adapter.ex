defmodule YoganHockey.HTTP.Adapter do
  @moduledoc """
  Behaviour for HTTP adapters.

  This abstraction allows for easy testing and swapping of HTTP clients.
  The default implementation uses Req.
  """

  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type options :: keyword()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Performs a GET request and returns parsed JSON.
  """
  @callback get_json(url(), headers(), options()) :: response()

  @doc """
  Performs a GET request and returns raw HTML.
  """
  @callback get_html(url(), headers(), options()) :: {:ok, String.t()} | {:error, term()}
end
