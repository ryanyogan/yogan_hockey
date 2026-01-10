defmodule YoganHockey.HTTP.ReqAdapter do
  @moduledoc """
  HTTP adapter implementation using Req.

  Provides JSON and HTML fetching capabilities with proper error handling.
  """

  @behaviour YoganHockey.HTTP.Adapter

  require Logger

  @default_headers [
    {"user-agent", "YoganHockey/1.0 (Hockey Stats App)"},
    {"accept", "application/json"}
  ]

  @html_headers [
    {"user-agent", "Mozilla/5.0 (compatible; YoganHockey/1.0)"},
    {"accept", "text/html"}
  ]

  @impl true
  def get_json(url, headers \\ [], opts \\ []) do
    merged_headers = merge_headers(@default_headers, headers)

    req_opts =
      Keyword.merge(
        [
          url: url,
          headers: merged_headers,
          receive_timeout: Keyword.get(opts, :timeout, 15_000)
        ],
        Keyword.drop(opts, [:timeout])
      )

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("HTTP #{status} from #{url}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_html(url, headers \\ [], opts \\ []) do
    merged_headers = merge_headers(@html_headers, headers)

    req_opts =
      Keyword.merge(
        [
          url: url,
          headers: merged_headers,
          receive_timeout: Keyword.get(opts, :timeout, 15_000),
          decode_body: false
        ],
        Keyword.drop(opts, [:timeout])
      )

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("HTTP #{status} from #{url}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp merge_headers(defaults, custom) do
    custom_keys = Enum.map(custom, fn {k, _} -> String.downcase(k) end)

    defaults
    |> Enum.reject(fn {k, _} -> String.downcase(k) in custom_keys end)
    |> Enum.concat(custom)
  end
end
