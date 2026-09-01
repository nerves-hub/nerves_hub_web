defmodule NervesHubWeb.Live.DeploymentGroups.Show.WorkflowDiagramTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Workflows

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

    # Reload so the group points at the release that carries the steps.
    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)

    %{deployment_group: deployment_group}
  end

  # Every edge is drawn as `M <x>,<y> C ...`. Endpoints sharing a y means the
  # arrows run level; a step's own x tells us which side of the node it left from.
  # LiveFlow's hook sits on its own live_component and is bound with phx-target, so
  # node changes go there rather than to this LiveView. Driving the element keeps
  # the test on the path a browser actually takes, callback included.
  defp measure_nodes(view, changes) do
    _ =
      view
      |> element("#deployment-workflow")
      |> render_hook("lf:node_change", %{"changes" => changes})

    # The component hands the changes on by message, so the render that the hook
    # call returns still predates our re-centring.
    render(view)
  end

  describe "the controls on a step" do
    test "a running step offers skip, and the trailing catch_all does not", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      {:ok, _view, html} = live(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

      assert html =~ "Skip step: Canary"
      refute html =~ "Skip step: Remaining devices"
      refute html =~ "Retry step:"
    end

    test "skipping a step from its node hands its devices on", %{
      conn: conn,
      org: org,
      product: product,
      user: user,
      deployment_group: deployment_group
    } do
      {:ok, view, _html} = live(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

      [canary | _] = Workflows.release_steps(deployment_group.current_deployment_release_id)
      _ = Workflows.start_step(canary)

      _ =
        view
        |> element("[aria-label='Skip step: Canary']")
        |> render_click()

      # The node component asks the LiveView by message, so the click's own render
      # still predates the work being done.
      assert render(view) =~ "Step skipped"

      [canary | _] = Workflows.release_steps(deployment_group.current_deployment_release_id)

      assert canary.status == :skipped
      assert canary.skipped_by_id == user.id
    end

    test "a failed step offers retry", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      [canary | _] = Workflows.release_steps(deployment_group.current_deployment_release_id)

      canary
      |> Workflows.start_step()
      |> Workflows.fail_step()

      {:ok, view, html} = live(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

      assert html =~ "Retry step: Canary"

      _ =
        view
        |> element("[aria-label='Retry step: Canary']")
        |> render_click()

      assert render(view) =~ "Step restarted"

      [canary | _] = Workflows.release_steps(deployment_group.current_deployment_release_id)

      assert canary.status == :in_progress
    end
  end

  defp edge_endpoints(html) do
    ~r/ d="M (\d+(?:\.\d+)?),(\d+(?:\.\d+)?) C [^"]*?(\d+(?:\.\d+)?),(\d+(?:\.\d+)?)"/
    |> Regex.scan(html)
    |> Enum.map(fn [_, x1, y1, x2, y2] ->
      {String.to_float(x1), String.to_float(y1), String.to_float(x2), String.to_float(y2)}
    end)
    |> Enum.uniq()
  end

  # The fit scales the diagram to fill its panel, which is wanted of a long
  # workflow. The cap only stops a two-step one being blown up to fill the same
  # room.
  test "scaling up to fill the panel is allowed, but bounded", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    {:ok, _view, html} = live(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

    assert [[_, max_zoom]] = Regex.scan(~r/data-max-zoom="([0-9.]+)"/, html)

    max_zoom = String.to_float(max_zoom)

    assert max_zoom > 1.0, "the diagram should be able to grow into the space it has"
    assert max_zoom <= 2.0, "a short workflow should not be magnified without limit"
  end

  # LiveFlow's fit pads by a fixed 0.1 and animates over 200ms rather than setting
  # the viewport, so having it and ours both run showed the diagram being sized
  # twice. Exactly one thing fits it.
  test "the diagram is fitted once, by our hook rather than LiveFlow", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    {:ok, _view, html} = live(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

    assert html =~ ~s(phx-hook="WorkflowDiagramFit")
    refute html =~ "data-fit-view-on-init"
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

    html = measure_nodes(view, changes)

    endpoints = edge_endpoints(html)

    assert length(endpoints) == 3

    for {_x1, y1, _x2, y2} <- endpoints do
      assert y1 == y2, "expected a level edge after measurement, got #{y1} -> #{y2}"
    end

    ys = endpoints |> Enum.flat_map(fn {_, y1, _, y2} -> [y1, y2] end) |> Enum.uniq()

    assert [_single_centre_line] = ys
  end
end
