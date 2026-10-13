defmodule NervesHub.Webhooks.Delivery.AdapterTest do
  # A real server on a real socket: the point of the adapter is the connection
  # it makes, which a stubbed plug would skip.
  use ExUnit.Case, async: true

  alias NervesHub.Webhooks.Delivery.Adapter

  defmodule Receiver do
    @moduledoc false
    import Plug.Conn

    def init(test_pid), do: test_pid

    def call(conn, test_pid) do
      {:ok, body, conn} = read_body(conn)

      send(test_pid, {:received, conn.method, conn.request_path, conn.query_string, conn.req_headers, body})

      conn
      |> put_resp_header("x-receiver", "yes")
      |> send_resp(202, String.duplicate("a body nobody reads ", 1000))
    end
  end

  setup do
    server =
      start_supervised!(
        Supervisor.child_spec({Bandit, plug: {Receiver, self()}, ip: :loopback, port: 0, startup_log: false},
          id: :receiver
        )
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    %{port: port}
  end

  defp post(url, address) do
    [method: :post, url: url, headers: [{"webhook-id", "msg_1"}], body: "{}", adapter: Adapter, retry: false]
    |> Req.new()
    |> Req.Request.put_private(:webhook_address, address)
    |> Req.request()
  end

  test "connects to the checked address, naming the host it was given", %{port: port} do
    assert {:ok, %Req.Response{status: 202} = response} =
             post("http://localhost:#{port}/hooks?source=nh", {127, 0, 0, 1})

    assert Req.Response.get_header(response, "x-receiver") == ["yes"]

    assert_receive {:received, "POST", "/hooks", "source=nh", headers, "{}"}
    assert {"host", "localhost:#{port}"} in headers
    assert {"webhook-id", "msg_1"} in headers
  end

  test "connects by name when no address was checked", %{port: port} do
    assert {:ok, %Req.Response{status: 202}} = post("http://localhost:#{port}/", nil)
    assert_receive {:received, "POST", "/", "", _headers, "{}"}
  end

  test "reports a refused connection", %{port: port} do
    :ok = stop_supervised(:receiver)

    assert {:error, %Mint.TransportError{reason: :econnrefused}} = post("http://localhost:#{port}/", {127, 0, 0, 1})
  end
end
