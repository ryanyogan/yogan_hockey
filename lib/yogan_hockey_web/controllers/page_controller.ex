defmodule YoganHockeyWeb.PageController do
  use YoganHockeyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
