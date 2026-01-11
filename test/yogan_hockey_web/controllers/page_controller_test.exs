defmodule YoganHockeyWeb.PageControllerTest do
  use YoganHockeyWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "YoganHockey"
  end
end
