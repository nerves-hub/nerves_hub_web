defmodule NervesHubWeb.MaintenanceEndpointTest do
  # Changes application config, and leaves the database sandbox unchecked out so
  # that anything reaching for the Repo fails the test.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias NervesHubWeb.MaintenanceEndpoint

  @status_page_url "https://status.example.com/"

  setup do
    start_supervised!(MaintenanceEndpoint)

    previous = Application.get_env(:nerves_hub, :status_page_url)
    Application.put_env(:nerves_hub, :status_page_url, @status_page_url)
    on_exit(fn -> Application.put_env(:nerves_hub, :status_page_url, previous) end)
  end

  defp request(method \\ :get, path) do
    conn(method, path) |> MaintenanceEndpoint.call([])
  end

  test "answers health checks without touching the database" do
    conn = request("/status/alive")

    assert conn.status == 200
    assert conn.resp_body == "Hello, Friend!"
  end

  test "shows the page in place of any route, with a link to the status page" do
    for path <- ["/", "/login", "/org/acme/products"] do
      conn = request(path)

      assert conn.status == 503
      assert get_resp_header(conn, "retry-after") == ["300"]
      assert ["text/html" <> _] = get_resp_header(conn, "content-type")
      assert conn.resp_body =~ "planned maintenance"
      assert conn.resp_body =~ ~s(href="#{@status_page_url}")
    end
  end

  test "leaves the status page out when none is configured" do
    Application.put_env(:nerves_hub, :status_page_url, nil)

    conn = request("/")

    assert conn.status == 503
    refute conn.resp_body =~ "status page"
    refute conn.resp_body =~ "<a "
  end

  test "names the platform as this instance is configured" do
    previous = Application.get_env(:nerves_hub, :friendly_platform_name)
    Application.put_env(:nerves_hub, :friendly_platform_name, "AcmeFleet")
    on_exit(fn -> Application.put_env(:nerves_hub, :friendly_platform_name, previous) end)

    assert request("/").resp_body =~ "AcmeFleet is offline"
    assert request("/api/orgs").resp_body =~ "AcmeFleet is offline"
  end

  test "gives the API its usual error shape" do
    conn = request("/api/orgs")

    assert conn.status == 503
    assert ["application/json" <> _] = get_resp_header(conn, "content-type")
    assert %{"errors" => %{"detail" => detail}} = Jason.decode!(conn.resp_body)
    assert detail =~ "planned maintenance"
    assert detail =~ @status_page_url
  end

  test "gives JSON to anything asking for it" do
    conn =
      conn(:get, "/")
      |> put_req_header("accept", "application/json")
      |> MaintenanceEndpoint.call([])

    assert conn.status == 503
    assert %{"errors" => %{"detail" => _}} = Jason.decode!(conn.resp_body)
  end

  test "refuses device and browser sockets rather than upgrading them" do
    for path <- ["/socket/websocket", "/device-socket/websocket", "/live/websocket"] do
      conn =
        conn(:get, path)
        |> put_req_header("connection", "upgrade")
        |> put_req_header("upgrade", "websocket")
        |> MaintenanceEndpoint.call([])

      assert conn.status == 503
    end
  end

  test "answers writes the same way" do
    assert request(:post, "/login").status == 503
  end
end
