defmodule YoganHockeyWeb.PlayersLive do
  @moduledoc """
  Browse and search NHL players, manage favorites.
  """
  use YoganHockeyWeb, :live_view

  alias YoganHockey.NHL

  import YoganHockeyWeb.HockeyComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Players")
     |> assign(:favorite_ids, [])
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:search_loading, false)
     |> assign(:favorites_loading, true)
     |> assign(:favorite_players, [])}
  end

  @impl true
  def handle_event("favorites_loaded", %{"player_ids" => player_ids}, socket) do
    # Load player data asynchronously
    socket =
      socket
      |> assign(:favorite_ids, player_ids)
      |> assign_async(:favorite_players, fn ->
        players = NHL.get_players(player_ids)
        {:ok, %{favorite_players: players}}
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("favorites_updated", %{"player_ids" => player_ids}, socket) do
    # Reload favorites after toggle
    socket =
      socket
      |> assign(:favorite_ids, player_ids)
      |> assign_async(:favorite_players, fn ->
        players = NHL.get_players(player_ids)
        {:ok, %{favorite_players: players}}
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_favorite", %{"id" => player_id}, socket) do
    # Push event to JS hook to update localStorage
    {:noreply, push_event(socket, "toggle_favorite", %{player_id: player_id})}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) when is_binary(query) and byte_size(query) >= 2 do
    # Use start_async for non-blocking search
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_loading, true)
     |> cancel_async(:search_results)
     |> start_async(:search_results, fn -> NHL.search_players(query) end)}
  end

  @impl true
  def handle_event("search", params, socket) do
    # Handle empty query or short queries - extract query from params
    query = params["query"] || ""

    {:noreply,
     socket
     |> cancel_async(:search_results)
     |> assign(:search_query, query)
     |> assign(:search_results, [])
     |> assign(:search_loading, false)}
  end

  @impl true
  def handle_async(:search_results, {:ok, {:ok, results}}, socket) do
    {:noreply,
     socket
     |> assign(:search_results, results)
     |> assign(:search_loading, false)}
  end

  @impl true
  def handle_async(:search_results, {:ok, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:search_results, [])
     |> assign(:search_loading, false)}
  end

  @impl true
  def handle_async(:search_results, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :search_loading, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="players-page" phx-hook="FavoritePlayers" class="space-y-6">
      <.section_header title="Find Players" />

      <%!-- Search --%>
      <.player_search
        results={@search_results}
        query={@search_query}
        loading={@search_loading}
        favorite_ids={@favorite_ids}
      />

      <%!-- Favorites Section --%>
      <section>
        <.section_header title="Your Favorites" />

        <%= case @favorite_players do %>
          <% %Phoenix.LiveView.AsyncResult{loading: true} -> %>
            <%!-- Loading skeleton --%>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.player_card_skeleton :for={_ <- 1..min(length(@favorite_ids), 4)} />
            </div>

          <% %Phoenix.LiveView.AsyncResult{ok?: true, result: players} when players != [] -> %>
            <%!-- Loaded favorites --%>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.player_card
                :for={player <- players}
                player={player}
                favorited={player.id in @favorite_ids}
              />
            </div>

          <% _ -> %>
            <%!-- Empty or error state --%>
            <.empty_favorites />
        <% end %>
      </section>

      <%!-- Browse Teams Link --%>
      <section class="text-center py-4">
        <p class="text-sm text-base-content/50 mb-2">
          Browse team rosters to find players
        </p>
        <.link navigate={~p"/nhl"} class="text-primary hover:underline text-sm">
          View all teams
        </.link>
      </section>
    </div>
    """
  end
end
