defmodule NervesHubWeb.Live.NewUI.DelploymentGroups.NewTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  import Ecto.Query, only: [from: 2]

  setup context do
    conn =
      context.conn
      |> put_session("new_ui", true)
      |> visit("/org/#{context.org.name}/#{context.product.name}/deployment_groups/newz")

    %{context | conn: conn}
  end

  test "can update only version", %{conn: conn, org: org, product: product, fixture: fixture} do
    conn
    |> fill_in("Name", with: "Canaries")
    |> select("Platform", option: "platform")
    # Selecting platform should trigger a change event, but it doesn't.
    # I suspect it has to do with the phx-change event on the select,
    # instead of the parent form.
    |> unwrap(fn view ->
      render_change(view, "platform-selected", %{
        "deployment_group" => %{"platform" => "platform"}
      })
    end)
    |> select("Architecture", option: "x86_64")
    # Same as above
    |> unwrap(fn view ->
      render_change(view, "architecture-selected", %{
        "deployment_group" => %{"architecture" => "x86_64"}
      })
    end)
    |> select("Firmware", option: "1.0.0", exact_option: false)
    |> fill_in("Tag(s) distributed to", with: "a, b")
    |> fill_in("Version requirement", with: "1.2.3")
    |> submit()
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/Canaries")

    deployment_group = Repo.one!(from(d in DeploymentGroup, where: d.name == "Canaries"))
    assert deployment_group.firmware_id == fixture.firmware.id
    assert deployment_group.conditions == %{"version" => "1.2.3", "tags" => ["a", "b"]}
  end
end
