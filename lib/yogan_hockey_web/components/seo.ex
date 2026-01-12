defmodule YoganHockeyWeb.SEO do
  @moduledoc """
  SEO helper functions for meta tags and OpenGraph data.

  Use `put_seo/2` in LiveView mount to set all SEO-related assigns.
  """

  import Phoenix.Component, only: [assign: 3]

  @base_url "https://yoganhockey.com"
  @site_name "YoganHockey"
  @default_image "/images/og/default.svg"

  @doc """
  Assigns SEO metadata to the socket.

  ## Options
    * `:title` - Page title (required)
    * `:description` - Meta description
    * `:image` - OpenGraph image path (relative to base URL)
    * `:url` - Canonical URL path
    * `:type` - OpenGraph type (default: "website")

  ## Example

      socket
      |> SEO.put_seo(
        title: "Live Scores",
        description: "Real-time NHL game scores and updates",
        image: "/images/og/live-scores.svg",
        url: "/nhl/live"
      )
  """
  def put_seo(socket, opts) do
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description, default_description())
    image = Keyword.get(opts, :image, @default_image)
    url = Keyword.get(opts, :url, "/")
    type = Keyword.get(opts, :type, "website")

    socket
    |> assign(:page_title, title)
    |> assign(:meta_description, description)
    |> assign(:og_title, title)
    |> assign(:og_description, description)
    |> assign(:og_image, full_url(image))
    |> assign(:og_url, full_url(url))
    |> assign(:og_type, type)
    |> assign(:twitter_card, "summary_large_image")
  end

  @doc """
  Updates just the title (useful for dynamic pages like player/team).
  """
  def put_title(socket, title) do
    socket
    |> assign(:page_title, title)
    |> assign(:og_title, title)
  end

  @doc """
  Returns the full URL for a path.
  """
  def full_url(path) when is_binary(path) do
    if String.starts_with?(path, "http") do
      path
    else
      @base_url <> path
    end
  end

  def base_url, do: @base_url
  def site_name, do: @site_name

  defp default_description do
    "Real-time NHL scores, standings, and comprehensive hockey statistics. " <>
      "Track your favorite players and teams with live updates."
  end
end
