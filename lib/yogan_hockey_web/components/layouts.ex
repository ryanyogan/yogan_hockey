defmodule YoganHockeyWeb.Layouts do
  @moduledoc """
  ESPN-style layouts for YoganHockey.
  """
  use YoganHockeyWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the ESPN-style app layout.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- ESPN-style Header --%>
    <header class="sticky top-0 z-50 bg-base-200 border-b border-base-300">
      <%!-- Top Bar --%>
      <div class="bg-base-300">
        <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center justify-between h-8">
          <div class="flex items-center gap-4 text-[10px] uppercase tracking-wider text-base-content/60">
            <span>NHL</span>
            <span>DEL2</span>
          </div>
          <div class="flex items-center gap-2">
            <.theme_toggle />
          </div>
        </div>
      </div>

      <%!-- Main Nav --%>
      <nav class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-12">
          <%!-- Logo --%>
          <a href="/" class="flex items-center gap-2 font-bold text-lg tracking-tight">
            <span class="text-xl">🏒</span>
            <span class="hidden sm:inline">YoganHockey</span>
          </a>

          <%!-- Desktop Nav --%>
          <div class="hidden md:flex items-center">
            <.link navigate={~p"/"} class="nav-link">Scores</.link>
            <.link navigate={~p"/nhl"} class="nav-link">Standings</.link>
            <.link navigate={~p"/nhl"} class="nav-link">Teams</.link>
            <.link navigate={~p"/yogan"} class="nav-link">Yogan</.link>
            <.link navigate={~p"/nhl/live"} class="nav-link">
              <span class="live-indicator">Live</span>
            </.link>
          </div>

          <%!-- Mobile Menu Button --%>
          <label for="mobile-menu" class="md:hidden btn btn-ghost btn-sm p-2">
            <.icon name="hero-bars-3" class="w-5 h-5" />
          </label>
        </div>
      </nav>
    </header>

    <%!-- Mobile Menu --%>
    <input type="checkbox" id="mobile-menu" class="hidden peer" />
    <div class="fixed inset-0 z-40 hidden peer-checked:flex flex-col bg-base-100 md:hidden">
      <div class="flex items-center justify-between h-12 px-4 border-b border-base-300">
        <span class="font-bold">Menu</span>
        <label for="mobile-menu" class="btn btn-ghost btn-sm p-2">
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </label>
      </div>
      <div class="flex-1 p-4 space-y-1">
        <label for="mobile-menu">
          <.link navigate={~p"/"} class="block p-3 hover:bg-base-200 font-medium">
            Scores
          </.link>
        </label>
        <label for="mobile-menu">
          <.link navigate={~p"/nhl"} class="block p-3 hover:bg-base-200 font-medium">
            Standings
          </.link>
        </label>
        <label for="mobile-menu">
          <.link navigate={~p"/nhl"} class="block p-3 hover:bg-base-200 font-medium">
            Teams
          </.link>
        </label>
        <label for="mobile-menu">
          <.link navigate={~p"/yogan"} class="block p-3 hover:bg-base-200 font-medium">
            Andrew Yogan
          </.link>
        </label>
        <label for="mobile-menu">
          <.link navigate={~p"/nhl/live"} class="block p-3 hover:bg-base-200 font-medium">
            <span class="live-indicator">Live Scores</span>
          </.link>
        </label>
      </div>
    </div>

    <%!-- Main Content --%>
    <main class="min-h-screen bg-base-100">
      <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-4 sm:py-6">
        {render_slot(@inner_block)}
      </div>
    </main>

    <%!-- Minimal Footer --%>
    <footer class="bg-base-200 border-t border-base-300 py-4">
      <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center justify-between text-xs text-base-content/50">
        <span>YoganHockey &copy; {DateTime.utc_now().year}</span>
        <span>Data: ESPN & Elite Prospects</span>
      </div>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Theme toggle component.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-1 bg-base-100 p-0.5">
      <button
        class="p-1.5 hover:bg-base-300 transition-colors"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light"
      >
        <.icon name="hero-sun-micro" class="w-3.5 h-3.5" />
      </button>
      <button
        class="p-1.5 hover:bg-base-300 transition-colors"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark"
      >
        <.icon name="hero-moon-micro" class="w-3.5 h-3.5" />
      </button>
    </div>
    """
  end
end
