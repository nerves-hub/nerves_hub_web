defmodule NervesHubDeviceWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate
  alias NervesHubWebCore.Fixtures

  using do
    quote do
      # Import conveniences for testing with connections
      use Phoenix.ConnTest
      import NervesHubDeviceWeb.Router.Helpers

      # The default endpoint for testing
      @endpoint NervesHubDeviceWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHubWebCore.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(NervesHubWebCore.Repo, {:shared, self()})
    end

    user = Fixtures.user_fixture()

    org = Fixtures.org_fixture(user)
    org_key = Fixtures.org_key_fixture(org)
    product = Fixtures.product_fixture(user, org, %{name: "starter"})
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, firmware)
    %{cert: cert, db_cert: device_cert} = Fixtures.device_certificate_fixture(device)

    deployment =
      Fixtures.deployment_fixture(firmware, %{
        conditions: %{"tags" => device.tags, "version" => ""}
      })

    {:ok,
     conn: build_auth_conn(cert),
     org: org,
     org_key: org_key,
     product: product,
     firmware: firmware,
     device: device,
     device_cert: device_cert,
     cert: cert,
     deployment: deployment}
  end

  def build_auth_conn(cert) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Test.put_peer_data(peer_data(cert))
    |> Plug.Conn.put_req_header("accept", "application/json")
  end

  def peer_data(cert) do
    %{address: {127, 0, 0, 1}, port: 111_317, ssl_cert: X509.Certificate.to_der(cert)}
  end
end
