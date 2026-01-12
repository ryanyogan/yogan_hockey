defmodule YoganHockeyWeb.Router do
  use YoganHockeyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YoganHockeyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", YoganHockeyWeb do
    pipe_through :browser

    live_session :default, layout: {YoganHockeyWeb.Layouts, :app} do
      live "/", DashboardLive, :index
      live "/yogan", YoganLive, :index
      live "/nhl", NHLLive, :index
      live "/nhl/live", LiveScoresLive, :index
      live "/nhl/teams/:id", TeamLive, :show
      live "/players", PlayersLive, :index
      live "/players/:id", PlayerLive, :show
      live "/playoffs", PlayoffsLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:yogan_hockey, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: YoganHockeyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
