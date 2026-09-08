defmodule NervesHubWeb.Live.LocalTimezoneTest do
  @moduledoc """
  End-to-end cover for rendering timestamps in the viewer's zone: the browser
  reports a zone, and the page shows local time rather than UTC.
  """

  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Scripts
  alias NervesHubWeb.Components.DateTimes

  @zone "Pacific/Auckland"

  setup %{conn: conn, user: user, org: org, product: product} do
    {:ok, script} = Scripts.create(product, user, %{name: "MOTD", text: "NervesMOTD.print()"})

    [conn: conn, path: "/org/#{org.name}/#{product.name}/scripts", script: script]
  end

  # The scripts table names the zone in its column header, so the cells carry no
  # zone label of their own.
  defp expected(script, zone) do
    DateTimes.to_local_string(script.updated_at, zone, :datetime, false)
  end

  test "the connected render uses the zone from the socket connect params", %{
    conn: conn,
    path: path,
    script: script
  } do
    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"time_zone" => @zone})
      |> live(path)

    assert render(view) =~ expected(script, @zone)
  end

  test "the static render uses the zone cookie, so the first paint isn't UTC", %{
    conn: conn,
    path: path,
    script: script
  } do
    html =
      conn
      |> Phoenix.ConnTest.put_req_cookie("time_zone", @zone)
      |> get(path)
      |> html_response(200)

    assert html =~ expected(script, @zone)
  end

  test "falls back to UTC when the browser hasn't reported a zone", %{
    conn: conn,
    path: path,
    script: script
  } do
    {:ok, view, _html} = live(conn, path)

    assert render(view) =~ expected(script, "Etc/UTC")
  end

  test "a zone the time zone database doesn't know falls back to UTC", %{
    conn: conn,
    path: path,
    script: script
  } do
    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"time_zone" => "Mars/Olympus_Mons"})
      |> live(path)

    assert render(view) =~ expected(script, "Etc/UTC")
  end
end
