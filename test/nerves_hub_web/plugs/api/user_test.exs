defmodule NervesHubWeb.API.Plugs.UserTest do
  use ExUnit.Case, async: false
  use NervesHubWeb.APIConnCase

  setup do
    conn =
      build_conn()
      |> bypass_through(NervesHubWeb.API.Router)
      |> dispatch(NervesHubWeb.API.Endpoint, :get, "/users/me")

    %{conn: conn}
  end

  test "can use API token auth", %{user: user, user_token: %{token: token}} do
    conn =
      build_conn()
      |> put_req_header("authorization", "token #{token}")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "username" => user.username
           }

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "username" => user.username
           }
  end

  test "rejects unknown API token" do
    conn =
      build_conn()
      |> put_req_header("authorization", "token wat-is-this-token")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    conn2 =
      build_conn()
      |> put_req_header("authorization", "token nhu_1234567890abcdefghijklmnopqrstuvwxyz")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    assert json_response(conn, 403)
    assert json_response(conn2, 403)
  end

  test "rejects token with bad CRC", %{user_token: %{token: token}} do
    <<head::34-bytes, crc_bin::6-bytes>> = token
    crc = Base62.decode!(crc_bin) + 1
    bad = <<head::binary, Base62.encode(crc)::binary>>

    conn =
      build_conn()
      |> put_req_header("authorization", "token #{bad}")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    assert json_response(conn, 403)
  end

  test "prefers token auth", %{conn: conn, user: user, user_token: %{token: token}} do
    peer = get_peer_data(conn)

    updated =
      build_conn()
      |> Plug.Test.put_peer_data(Map.put(peer, :ssl_cert, <<1, 2, 3, 4, 5>>))
      |> put_req_header("authorization", "token #{token}")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    assert json_response(updated, 200)["data"] == %{
             "email" => user.email,
             "username" => user.username
           }
  end
end
