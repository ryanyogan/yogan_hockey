defmodule YoganHockeyWeb.Layouts do
  @moduledoc """
  ESPN-style layouts for YoganHockey.
  """
  use YoganHockeyWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the ESPN-style app layout with header, footer, and flash messages.
  Used as the layout for all LiveViews via live_session in router.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :inner_content, :any, required: true, doc: "the inner content rendered by LiveView"
  attr :current_scope, :map, default: nil

  def app(assigns) do
    ~H"""
    <%!-- ESPN-style Header --%>
    <header class="sticky top-0 z-50 bg-base-200 border-b border-base-300">
      <%!-- Top Bar --%>
      <div class="bg-base-300">
        <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center justify-between h-8 overflow-hidden">
          <div class="flex items-center gap-4 text-[10px] uppercase tracking-wider flex-shrink-0 mt-7 sm:mt-0">
            <.link navigate={~p"/nhl?tab=teams"} class="text-base-content/60 hover:text-primary transition-colors">
              NHL
            </.link>
            <.link navigate={~p"/yogan"} class="text-base-content/60 hover:text-primary transition-colors">
              DEL
            </.link>
          </div>
          <div class="flex-shrink-0">
            <.theme_toggle />
          </div>
        </div>
      </div>

      <%!-- Main Nav --%>
      <nav class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-12">
          <%!-- Logo --%>
          <.link navigate={~p"/"} class="flex items-center gap-1 group">
            <span class="font-mono font-bold text-sm tracking-tighter uppercase">
              <span class="text-primary">YOGAN</span><span class="text-base-content/80">HOCKEY</span>
            </span>
          </.link>

          <%!-- Desktop Nav --%>
          <div class="hidden md:flex items-center">
            <.link navigate={~p"/nhl"} class="nav-link">Standings</.link>
            <.link navigate={~p"/nhl?tab=teams"} class="nav-link">Teams</.link>
            <.link navigate={~p"/players"} class="nav-link">Players</.link>
            <.link navigate={~p"/playoffs"} class="nav-link">Playoffs</.link>
            <.link navigate={~p"/nhl/live"} class="nav-link">
              <span class="live-indicator">Live Scores</span>
            </.link>
          </div>

          <%!-- Mobile Menu Button --%>
          <label for="mobile-menu" class="md:hidden btn btn-ghost btn-sm p-2 cursor-pointer">
            <.icon name="hero-bars-3" class="w-5 h-5" />
          </label>
        </div>
      </nav>
    </header>

    <%!-- Mobile Menu --%>
    <input type="checkbox" id="mobile-menu" class="hidden peer" />
    <div
      id="mobile-menu-panel"
      phx-hook="MobileMenu"
      class="fixed inset-0 z-40 hidden peer-checked:flex flex-col bg-base-100 md:hidden"
    >
      <div class="flex items-center justify-between h-14 px-4 border-b border-base-300 bg-base-200">
        <span class="font-bold text-lg">Menu</span>
        <label for="mobile-menu" class="btn btn-ghost p-3 cursor-pointer">
          <.icon name="hero-x-mark" class="w-6 h-6" />
        </label>
      </div>
      <nav class="flex-1 flex flex-col justify-center px-6 py-8">
        <.link navigate={~p"/nhl"} class="mobile-nav-link">Standings</.link>
        <.link navigate={~p"/nhl?tab=teams"} class="mobile-nav-link">Teams</.link>
        <.link navigate={~p"/players"} class="mobile-nav-link">Players</.link>
        <.link navigate={~p"/playoffs"} class="mobile-nav-link">Playoffs</.link>
        <.link navigate={~p"/nhl/live"} class="mobile-nav-link">
          <span class="live-indicator">Live Scores</span>
        </.link>
      </nav>
    </div>

    <%!-- Main Content --%>
    <main class="min-h-screen bg-base-100">
      <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-4 sm:py-6">
        {@inner_content}
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
    <div id={@id} aria-live="polite" class="fixed top-16 right-4 z-50 space-y-2">
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
    <div class="flex items-center gap-0.5 bg-base-100 p-0.5 rounded-sm flex-shrink-0">
      <button
        class="p-1 sm:p-1.5 hover:bg-base-300 transition-colors cursor-pointer"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light"
      >
        <.icon name="hero-sun-micro" class="w-3 h-3 sm:w-3.5 sm:h-3.5" />
      </button>
      <button
        class="p-1 sm:p-1.5 hover:bg-base-300 transition-colors cursor-pointer"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark"
      >
        <.icon name="hero-moon-micro" class="w-3 h-3 sm:w-3.5 sm:h-3.5" />
      </button>
    </div>
    """
  end
end
