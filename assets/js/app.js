// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

// Hooks
const Hooks = {};

// FavoritePlayers hook - manages localStorage for favorite player IDs
Hooks.FavoritePlayers = {
  mounted() {
    // Send favorites to LiveView on mount
    const favorites = JSON.parse(
      localStorage.getItem("favorite_players") || "[]",
    );
    this.pushEvent("favorites_loaded", { player_ids: favorites });

    // Listen for toggle events from LiveView
    this.handleEvent("toggle_favorite", ({ player_id }) => {
      let favorites = JSON.parse(
        localStorage.getItem("favorite_players") || "[]",
      );

      if (favorites.includes(player_id)) {
        favorites = favorites.filter((id) => id !== player_id);
      } else {
        favorites.push(player_id);
      }

      localStorage.setItem("favorite_players", JSON.stringify(favorites));
      this.pushEvent("favorites_updated", { player_ids: favorites });
    });

    this.handleEvent("update_favorites", ({ player_ids }) => {
      localStorage.setItem("favorite_players", JSON.stringify(player_ids));
    });
  },
};

// PlayerSearch hook removed - using phx-debounce on input instead

// BracketRoundSelector hook - handles round tab switching
Hooks.BracketRoundSelector = {
  mounted() {
    const container = this.el;
    // Support both .round-tab and .tab-pill selectors
    const tabs = container.querySelectorAll("[data-round]");
    const panels = container.querySelectorAll(".round-panel");

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        const roundNum = tab.dataset.round;

        // Update active tab
        tabs.forEach((t) => t.classList.remove("active"));
        tab.classList.add("active");

        // Show corresponding panel
        panels.forEach((p) => {
          if (p.dataset.round === roundNum) {
            p.classList.add("active");
          } else {
            p.classList.remove("active");
          }
        });
      });
    });
  },
};

// MobileMenu hook - closes menu on LiveView navigation
Hooks.MobileMenu = {
  mounted() {
    this.checkbox = document.getElementById("mobile-menu");

    // Close menu when LiveView navigation starts
    this.navigationHandler = () => {
      if (this.checkbox) {
        this.checkbox.checked = false;
      }
    };

    window.addEventListener("phx:page-loading-start", this.navigationHandler);
  },

  destroyed() {
    window.removeEventListener(
      "phx:page-loading-start",
      this.navigationHandler,
    );
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
