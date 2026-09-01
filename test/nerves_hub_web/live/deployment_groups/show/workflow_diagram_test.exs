defmodule NervesHubWeb.Live.DeploymentGroups.Show.WorkflowDiagramTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments

  @definition %{
    "version" => 1,
    "steps" => [
      %{"name" => "Canary", "description" => "a description long enough to wrap onto a second line"},
      %{"name" => "No description here"},
      %{"name" => "Sign-off", "type" => "approval_required"}
    ]
  }

  setup %{user: user, org_key: org_key, product: product, tmp_dir: tmp_dir} do
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    deployment_group =
      Fixtures.deployment_group_fixture(firmware, %{is_active: true, name: "Workflow Group", user: user})

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: @definition}, user)

    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.1.0", dir: tmp_dir})

    {:ok, {_release, _}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{}, broadcast: false)

    %{deployment_group: deployment_group}
  end

  # Every edge is drawn as `M <x>,<y> C ...`. Endpoints sharing a y means the
  # arrows run level; a step's own x tells us which side of the node it left from.
  defp edge_endpoints(html) do
    ~r/ d="M (\d+(?:\.\d+)?),(\d+(?:\.\d+)?) C [^"]*?(\d+(?:\.\d+)?),(\d+(?:\.\d+)?)"/
    |> Regex.scan(html)
    |> Enum.map(fn [_, x1, y1, x2, y2] ->
      {String.to_float(x1), String.to_float(y1), String.to_float(x2), String.to_float(y2)}
    end)
    |> Enum.uniq()
  end

  test "arrows run level and leave each node on its right", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    {:ok, _view, html} = live(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

    endpoints = edge_endpoints(html)

    # Three steps plus the generated catch_all leaves three edges between them.
    assert length(endpoints) == 3

    for {x1, y1, x2, y2} <- endpoints do
      assert y1 == y2, "expected a level edge, got #{y1} -> #{y2}"
      assert x2 > x1, "expected the edge to run left to right, got #{x1} -> #{x2}"
    end
  end

  # A step with a description is taller than one without. LiveFlow hangs handles
  # halfway down a node, so unless each node is centred on a shared line the
  # arrows between them slope.
  test "arrows stay level once the browser reports differing node heights", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    {:ok, view, _html} = live(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

    changes = [
      %{"type" => "dimensions", "id" => "step-1", "width" => 230, "height" => 110},
      %{"type" => "dimensions", "id" => "step-2", "width" => 230, "height" => 58},
      %{"type" => "dimensions", "id" => "step-3", "width" => 230, "height" => 58},
      %{"type" => "dimensions", "id" => "step-4", "width" => 230, "height" => 58}
    ]

    html = render_hook(view, "lf:node_change", %{"changes" => changes})

    endpoints = edge_endpoints(html)

    assert length(endpoints) == 3

    for {_x1, y1, _x2, y2} <- endpoints do
      assert y1 == y2, "expected a level edge after measurement, got #{y1} -> #{y2}"
    end

    ys = endpoints |> Enum.flat_map(fn {_, y1, _, y2} -> [y1, y2] end) |> Enum.uniq()

    assert [_single_centre_line] = ys
  end
end
