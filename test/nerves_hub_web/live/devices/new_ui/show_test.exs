defmodule NervesHubWeb.Live.Devices.NewUI.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Accounts
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures

  alias NervesHubWeb.Endpoint

  setup %{conn: conn, fixture: %{device: device}} = context do
    Endpoint.subscribe("device:#{device.id}")

    conn = init_test_session(conn, %{"new_ui" => true})

    Map.put(context, :conn, conn)
  end

  describe "who is currently viewing the device page" do
    setup %{fixture: %{org: org}} do
      # https://hexdocs.pm/phoenix/Phoenix.Presence.html#module-testing-with-presence
      on_exit(fn ->
        for pid <- NervesHubWeb.Presence.fetchers_pids() do
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, _, _, _}, 1000
        end
      end)

      user_two = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, user_two, %{role: :view})

      {:ok, %{user_two: user_two}}
    end

    test "only the current user", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
    end

    test "two users, same device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      user_two: user_two
    } do
      conn_two =
        build_conn()
        |> init_test_session(%{"auth_user_id" => user_two.id})
        |> init_test_session(%{"new_ui" => true})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))

      conn_two
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
      |> assert_has("#present-users > #presences-#{user_two.id} > span",
        text: user_initials(user_two)
      )
    end

    test "two users, different devices", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      user_two: user_two
    } do
      firmware = Firmwares.get_firmware_by_uuid(device.firmware_metadata.uuid)
      device_two = Fixtures.device_fixture(org, product, firmware)

      conn_two =
        build_conn()
        |> init_test_session(%{"auth_user_id" => user_two.id})
        |> init_test_session(%{"new_ui" => true})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))

      conn_two
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device_two.identifier}")
      |> assert_has("h1", text: device_two.identifier)
      |> assert_has("#present-users > #presences-#{user_two.id} > span",
        text: user_initials(user_two)
      )
      |> refute_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
    end

    defp user_initials(user) do
      String.split(user.name)
      |> Enum.map(fn w ->
        String.at(w, 0)
        |> String.upcase()
      end)
      |> Enum.join("")
    end
  end

  def device_show_path(%{device: device, org: org, product: product}) do
    ~p"/org/#{org.name}/#{product.name}/devices/#{device.identifier}"
  end
end
