defmodule NervesHubWeb.Live.DeploymentGroups.Show do
  @moduledoc """
  A deployment group's page, with its Overview, Releases, Stats, Activity and Settings tabs.

  The header says what the group is releasing and to which devices, with the
  group's status and the buttons to pause it, import devices into it from a
  CSV, or make a new release. The Overview shows how far the current release has got: a callout when the
  group needs someone, the rollout bar and its steps, the devices the release
  didn't reach, and a rail with the release and how the group matches devices.
  Its counts come from `NervesHub.ManagedDeployments.Rollout` and are reloaded
  every few seconds while the page is open.
  """
  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.Fleet, only: [count_noun: 3]

  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.Deployments
  alias NervesHub.Firmwares
  alias NervesHub.Helpers.Logging
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Rollout
  alias NervesHub.Products
  alias NervesHub.Products.ApiKey
  alias NervesHubWeb.Components.DeploymentGroupPage.Activity, as: ActivityTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Dialogs
  alias NervesHubWeb.Components.DeploymentGroupPage.Overview
  alias NervesHubWeb.Components.DeploymentGroupPage.Releases, as: ReleasesTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Settings, as: SettingsTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Stats, as: StatsTab
  alias NervesHubWeb.Components.DeploymentGroups
  alias NervesHubWeb.Mounts.RequireEveryDevice
  alias NimbleCSV.RFC4180, as: CSV
  alias Phoenix.Socket.Broadcast

  on_mount(RequireEveryDevice)

  @refresh_interval to_timeout(second: 5)

  # How many of the devices the release didn't reach the Overview lists.
  @unreached_shown 5

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def mount(params, _session, socket) do
    %{"name" => name} = params
    %{current_scope: %{org: org, product: product, user: user}} = socket.assigns

    deployment_group = ManagedDeployments.get_by_product_and_name!(product, name, true)

    Logger.metadata(user_id: user.id, product_id: product.id, deployment_group_id: deployment_group.id)

    if connected?(socket) do
      :ok = Products.PubSub.subscribe(product.id)
      :ok = socket.endpoint.subscribe("deployment:#{deployment_group.id}")
      :ok = socket.endpoint.subscribe("deployment_release:#{deployment_group.current_deployment_release_id}")
      schedule_refresh()
    end

    socket
    |> assign(%{org: org, product: product, user: user})
    |> assign(:delta_target_firmware_ids, [])
    |> assign(:confirm, nil)
    |> allow_csv_import()
    |> follow_delta_targets(deployment_group)
    |> page_title("Deployment Group - #{deployment_group.name} - #{product.name}")
    |> sidebar_tab(:deployments)
    |> assign(:deployment_group, deployment_group)
    |> selected_tab()
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_params(params, _uri, socket) do
    socket
    |> assign(
      :open_new_release,
      params["new"] == "release" and authorized?(:"deployment_group:update", socket.assigns.current_scope)
    )
    |> assign(:activity_page, ActivityTab.page_params(params))
    |> assign(:stats_release, params["release"])
    |> selected_tab()
    |> assign_overview()
    |> noreply()
  end

  @impl Phoenix.LiveView
  # Pausing stops a rollout part-way and resuming sends firmware to more
  # devices, so both ask first. Opening the dialog checks the same permission
  # as acting on it.
  @decorate requires_permission(:"deployment_group:toggle")
  def handle_event("ask-toggle", _params, socket) do
    %{entry: entry, deployment_group: deployment_group} = socket.assigns
    action = if deployment_group.is_active, do: :pause, else: :resume

    socket
    |> assign(:confirm, {action, entry})
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:toggle")
  def handle_event("pause", _params, socket), do: set_active(socket, false)

  @decorate requires_permission(:"deployment_group:toggle")
  def handle_event("resume", _params, socket), do: set_active(socket, true)

  # Approving and skipping send firmware to more devices, so both ask first.
  # Opening the dialog checks the same permission as acting on it.
  @decorate requires_permission(:"deployment_group:update")
  def handle_event("approve", _params, socket) do
    socket
    |> ask(:approve, socket.assigns.entry.awaiting_step)
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("skip", _params, socket) do
    socket
    |> ask(:skip, socket.assigns.entry.failed_step)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("cancel-confirm", _params, socket) do
    socket
    |> assign(:confirm, nil)
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("confirm-approve", _params, socket), do: act(socket, :approve)

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("confirm-skip", _params, socket), do: act(socket, :skip)

  # Retrying only offers the update again to the devices that failed it, so
  # it runs straight away.
  @decorate requires_permission(:"deployment_group:update")
  def handle_event("retry", _params, socket), do: act(socket, :retry)

  @decorate requires_permission(:"deployment_group:delete")
  def handle_event("delete", _params, socket) do
    %{deployment_group: deployment_group, org: org, product: product, user: user} = socket.assigns

    {:ok, _} = ManagedDeployments.delete_deployment_group(deployment_group)

    DeploymentGroupTemplates.audit_deployment_deleted(user, deployment_group)

    socket
    |> put_flash(:info, "Deployment Group successfully deleted")
    |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups")
    |> noreply()
  end

  @decorate requires_permission(:"device:set-deployment-group")
  def handle_event("ask-move-in", _params, socket) do
    socket
    |> ask_about_devices(:move_in, :matched_outside)
    |> noreply()
  end

  @decorate requires_permission(:"device:set-deployment-group")
  def handle_event("ask-remove-unmatched", _params, socket) do
    socket
    |> ask_about_devices(:remove_unmatched, :unmatched_inside)
    |> noreply()
  end

  @decorate requires_permission(:"device:set-deployment-group")
  def handle_event("move-matched-devices-to-deployment-group", _params, socket) do
    %{assigns: %{current_scope: scope, deployment_group: deployment_group}} = socket

    move_devices = fn ->
      devices = ManagedDeployments.matched_device_ids(deployment_group, in_deployment: false)

      BulkActions.move_many_to_deployment_group(devices, deployment_group, scope.user)
      |> then(fn %{updated: updated_count, ignored: ignored_count} ->
        if ignored_count > 0 do
          {:error, updated_count, ignored_count}
        else
          updated_count
        end
      end)
    end

    socket
    |> assign(:confirm, nil)
    |> start_async(:move_devices_to_deployment, move_devices)
    |> put_flash(:info, "Moving devices to deployment, this may take a moment")
    |> noreply()
  end

  @decorate requires_permission(:"device:set-deployment-group")
  def handle_event("remove-unmatched-devices-from-deployment-group", _params, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    matched_device_ids =
      ManagedDeployments.matched_device_ids(deployment_group, in_deployment: true)

    remove_devices = fn ->
      {:ok, %{updated: updated, ignored: ignored}} =
        Deployments.remove_unmatched_devices_from_deployment_group(
          matched_device_ids,
          deployment_group
        )

      if ignored > 0 do
        {:error, updated, ignored}
      else
        updated
      end
    end

    socket
    |> assign(:confirm, nil)
    |> start_async(:remove_devices_from_deployment, remove_devices)
    |> put_flash(:info, "Removing devices from deployment, this may take a moment")
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("validate-csv", _params, socket), do: {:noreply, socket}

  @decorate requires_permission(:"device:set-deployment-group")
  def handle_progress(:device_csv, %{done?: true} = entry, socket) do
    %{deployment_group: deployment_group, current_scope: %{product: product, user: user}} =
      socket.assigns

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, parse_identifiers_from_csv(path)}
      end)

    socket =
      case result do
        {:error, :invalid_csv} ->
          put_flash(socket, :error, "CSV must have a single 'identifier' column header")

        {:ok, []} ->
          put_flash(socket, :error, "CSV contained no identifier values")

        {:ok, identifiers} ->
          socket
          |> start_async(:import_devices_from_csv, fn ->
            BulkActions.move_many_to_deployment_group_by_identifiers(
              product,
              identifiers,
              deployment_group,
              user
            )
          end)
          |> put_flash(:info, "Importing devices from CSV, this may take a moment")
      end

    {:noreply, socket}
  end

  @decorate requires_membership()
  def handle_progress(:device_csv, _entry, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_async(:import_devices_from_csv, {:ok, %{ok: updated, error: 0}}, socket) do
    socket
    |> put_flash(:info, "#{updated} devices imported from CSV into #{socket.assigns.deployment_group.name}")
    |> reload()
    |> noreply()
  end

  def handle_async(:import_devices_from_csv, {:ok, %{ok: updated, error: ignored}}, socket) do
    %{deployment_group: deployment_group} = socket.assigns

    :ok =
      Logging.log_to_sentry(
        deployment_group,
        "There was an issue importing devices from CSV into a deployment group.",
        %{updated_count: updated, ignored_count: ignored, deployment_group_id: deployment_group.id}
      )

    socket
    |> put_flash(
      :error,
      "#{updated} devices imported into #{deployment_group.name}. However, we couldn't import #{ignored} devices. We've been notified and are looking into it."
    )
    |> reload()
    |> noreply()
  end

  def handle_async(:import_devices_from_csv, {:exit, reason}, socket) do
    %{deployment_group: deployment_group} = socket.assigns
    :ok = Logging.log_to_sentry(deployment_group, reason)

    socket
    |> put_flash(
      :error,
      "There was an issue importing devices from CSV into #{deployment_group.name}. We've been notified and are looking into it."
    )
    |> noreply()
  end

  def handle_async(:move_devices_to_deployment, {:ok, {:error, updated_count, ignored_count}}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    :ok =
      Logging.log_to_sentry(
        deployment_group,
        "There was an issue moving devices to a deployment group.",
        %{updated_count: updated_count, ignored_count: ignored_count, deployment_group_id: deployment_group.id}
      )

    socket
    |> put_flash(
      :error,
      "#{updated_count} devices moved to #{deployment_group.name}. However, we couldn't move #{ignored_count} devices. We've been notified and are looking into it."
    )
    |> reload()
    |> noreply()
  end

  def handle_async(:move_devices_to_deployment, {:ok, devices_updated_count}, socket) do
    socket
    |> put_flash(:info, "#{devices_updated_count} devices moved to #{socket.assigns.deployment_group.name}")
    |> reload()
    |> noreply()
  end

  def handle_async(:move_devices_to_deployment, {:exit, reason}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket
    :ok = Logging.log_to_sentry(deployment_group, reason)

    socket
    |> put_flash(
      :error,
      "There was an issue moving devices to #{deployment_group.name}. We've been notified and are looking into it."
    )
    |> reload()
    |> noreply()
  end

  def handle_async(:remove_devices_from_deployment, {:ok, {:error, updated_count, ignored_count}}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    :ok =
      Logging.log_to_sentry(
        deployment_group,
        "There was an issue removing devices from a deployment group.",
        %{updated_count: updated_count, ignored_count: ignored_count, deployment_group_id: deployment_group.id}
      )

    socket
    |> put_flash(
      :error,
      "#{updated_count} devices removed from #{deployment_group.name}. However, we couldn't remove #{ignored_count} devices. We've been notified and are looking into it."
    )
    |> reload()
    |> noreply()
  end

  def handle_async(:remove_devices_from_deployment, {:ok, devices_removed_count}, socket) do
    socket
    |> put_flash(:info, "#{devices_removed_count} devices removed from #{socket.assigns.deployment_group.name}")
    |> reload()
    |> noreply()
  end

  def handle_async(:remove_devices_from_deployment, {:exit, reason}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket
    :ok = Logging.log_to_sentry(deployment_group, reason)

    socket
    |> put_flash(
      :error,
      "There was an issue removing devices from #{deployment_group.name}. We've been notified and are looking into it."
    )
    |> reload()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(:refresh, socket) do
    schedule_refresh()

    socket
    |> reload()
    |> noreply()
  end

  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    socket
    |> reload()
    |> noreply()
  end

  # A release's deltas finished, failed, or started building
  def handle_info(%Broadcast{event: "release/delta_status"}, socket) do
    send_update(ReleasesTab, id: "deployment_group_releases", event: :delta_status_updated)

    socket
    |> reload()
    |> noreply()
  end

  def handle_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/created", payload: %{firmware: firmware}},
        socket
      ) do
    send_update(ReleasesTab, id: "deployment_group_releases", event: {:firmware_created, firmware})

    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/deleted", payload: %{firmware: firmware}},
        socket
      ) do
    send_update(ReleasesTab, id: "deployment_group_releases", event: {:firmware_deleted, firmware})

    {:noreply, socket}
  end

  # One delta finishing or failing usually leaves every release's status where it
  # was -- a second failure among several is still `:failed` -- so the counts have
  # to follow the deltas themselves rather than `release/delta_status`, which only
  # fires on a change.
  def handle_info(%Broadcast{topic: "firmware:" <> _, event: "delta/status_update"}, socket) do
    send_update(ReleasesTab, id: "deployment_group_releases", event: :delta_status_updated)

    socket
    |> assign_overview()
    |> noreply()
  end

  def handle_info(%Broadcast{topic: "deployment_release:" <> _, event: "step/updated"}, socket) do
    socket
    |> reload()
    |> noreply()
  end

  # Ignore other broadcasts
  def handle_info(%Broadcast{}, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:flash, level, message}, socket) do
    socket
    |> put_flash(level, message)
    |> noreply()
  end

  defp schedule_refresh() do
    _ = Process.send_after(self(), :refresh, @refresh_interval)
    :ok
  end

  defp selected_tab(socket) do
    assign(socket, :tab, socket.assigns.live_action || :summary)
  end

  # Importing moves devices into the deployment group, so only members who may
  # do that get an upload configured at all, and LiveView refuses anyone else's
  # before any of the file arrives. `handle_progress/3` checks again before
  # importing.
  defp allow_csv_import(socket) do
    if authorized?(:"device:set-deployment-group", socket.assigns.current_scope) do
      socket
      |> assign(:csv_import?, true)
      |> allow_upload(:device_csv,
        accept: ~w(.csv),
        max_entries: 1,
        auto_upload: true,
        progress: &handle_progress/3
      )
    else
      assign(socket, :csv_import?, false)
    end
  end

  # The group as it stands now, with a new release's topic followed in place of
  # the old one's. Found by id, since a rename broadcasts an update too.
  defp reload(socket) do
    %{deployment_group: previous, product: product} = socket.assigns

    deployment_group = ManagedDeployments.get_by_product_and_id!(product, previous.id)

    %{current_deployment_release_id: was} = previous
    %{current_deployment_release_id: now} = deployment_group

    if connected?(socket) and was != now do
      :ok = socket.endpoint.unsubscribe("deployment_release:#{was}")
      :ok = socket.endpoint.subscribe("deployment_release:#{now}")
    end

    socket
    |> follow_delta_targets(deployment_group)
    |> assign(:deployment_group, deployment_group)
    |> assign_overview()
  end

  # What the header needs on every tab, and what the Overview adds when it's
  # the one open.
  defp assign_overview(%{assigns: %{deployment_group: deployment_group}} = socket) do
    [entry] = DeploymentGroups.load([deployment_group])

    socket
    |> assign(:entry, entry)
    |> then(fn socket ->
      if socket.assigns.tab == :summary, do: assign_overview_details(socket), else: socket
    end)
    |> refresh_confirm()
  end

  defp assign_overview_details(%{assigns: %{deployment_group: deployment_group}} = socket) do
    release = deployment_group.current_release
    matched = ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true)

    socket
    |> assign(:unreached, Rollout.unreached(deployment_group, @unreached_shown))
    |> assign(:matched_outside, ManagedDeployments.matched_devices_count(deployment_group, in_deployment: false))
    |> assign(:unmatched_inside, max(socket.assigns.entry.counts.total - matched, 0))
    |> assign(:deltas, Firmwares.get_deltas_by_target_firmware(release.firmware))
    |> assign(:released_by, released_by(release))
  end

  defp released_by(release) do
    case ManagedDeployments.release_author(release) do
      %User{name: name} -> name
      %ApiKey{name: name} -> "API key #{name}"
      nil -> nil
    end
  end

  # A dialog left open while the page refreshes shows things as they now
  # stand, and closes once there's nothing left for it to do: the step moved
  # on, someone else paused or resumed the group, or no devices are left to
  # move. The device counts are only kept on the Overview, where the buttons
  # are.
  defp refresh_confirm(%{assigns: %{confirm: {:approve, _entry}, entry: %{awaiting_step: %{}} = entry}} = socket),
    do: assign(socket, :confirm, {:approve, entry})

  defp refresh_confirm(%{assigns: %{confirm: {:skip, _entry}, entry: %{failed_step: %{}} = entry}} = socket),
    do: assign(socket, :confirm, {:skip, entry})

  defp refresh_confirm(%{assigns: %{confirm: {:pause, _entry}, entry: %{group: %{is_active: true}} = entry}} = socket),
    do: assign(socket, :confirm, {:pause, entry})

  defp refresh_confirm(
         %{assigns: %{confirm: {:resume, _entry}, entry: %{group: %{is_active: false}} = entry}} = socket
       ), do: assign(socket, :confirm, {:resume, entry})

  defp refresh_confirm(%{assigns: %{confirm: {:move_in, _}, tab: :summary, matched_outside: count}} = socket)
       when count > 0, do: assign(socket, :confirm, {:move_in, count})

  defp refresh_confirm(%{assigns: %{confirm: {:remove_unmatched, _}, tab: :summary, unmatched_inside: count}} = socket)
       when count > 0, do: assign(socket, :confirm, {:remove_unmatched, count})

  defp refresh_confirm(socket), do: assign(socket, :confirm, nil)

  defp ask(socket, _action, nil), do: socket
  defp ask(socket, action, _step), do: assign(socket, :confirm, {action, socket.assigns.entry})

  # The counts are the Overview's, so there's nothing to ask about elsewhere.
  defp ask_about_devices(%{assigns: %{tab: :summary}} = socket, action, count_key) do
    case socket.assigns[count_key] do
      count when is_integer(count) and count > 0 -> assign(socket, :confirm, {action, count})
      _ -> socket
    end
  end

  defp ask_about_devices(socket, _action, _count_key), do: socket

  # Sets the group's state rather than flipping it, so a page left open since
  # someone else paused or resumed the group can't undo what they did.
  defp set_active(socket, active?) do
    %{deployment_group: deployment_group, product: product, user: user} = socket.assigns
    deployment_group = ManagedDeployments.get_by_product_and_id!(product, deployment_group.id)
    socket = assign(socket, :confirm, nil)

    if deployment_group.is_active == active? do
      socket
      |> put_flash(:info, "#{deployment_group.name} is already #{(active? && "running") || "paused"}")
      |> reload()
      |> noreply()
    else
      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: active?}, user)

      DeploymentGroupTemplates.audit_deployment_toggle_active(
        user,
        deployment_group,
        (active? && "active") || "inactive"
      )

      socket
      |> put_flash(:info, "Deployment group #{(active? && "resumed") || "paused"}")
      |> reload()
      |> noreply()
    end
  end

  defp act(socket, action) do
    %{deployment_group: deployment_group, user: user} = socket.assigns
    {level, message} = DeploymentGroups.act(action, deployment_group, user)

    socket
    |> assign(:confirm, nil)
    |> put_flash(level, message)
    |> reload()
    |> noreply()
  end

  # Deltas are built towards firmware, and announced on the target firmware's own
  # topic, so the page joins one per firmware its devices are headed for: the
  # current release's, and that of any required release. The LiveView owns these
  # rather than the tabs, because both tabs want the same news and a membership
  # is per process -- one tab leaving would take the other's with it.
  defp follow_delta_targets(socket, deployment_group) do
    firmware_ids = ManagedDeployments.delta_target_firmware_ids(deployment_group)
    previous = socket.assigns.delta_target_firmware_ids

    if connected?(socket) and MapSet.new(previous) != MapSet.new(firmware_ids) do
      Enum.each(previous -- firmware_ids, &(:ok = Firmwares.PubSub.unsubscribe_delta_target(&1)))
      Enum.each(firmware_ids -- previous, &(:ok = Firmwares.PubSub.subscribe_delta_target(&1)))

      assign(socket, :delta_target_firmware_ids, firmware_ids)
    else
      socket
    end
  end

  defp parse_identifiers_from_csv(path) do
    path
    |> File.stream!()
    |> CSV.parse_stream(skip_headers: false)
    |> Enum.reduce({nil, []}, fn
      [header], {nil, []} ->
        if String.trim(header) == "identifier", do: {:ok, []}, else: {:error, :bad_header}

      [id], {:ok, acc} ->
        {:ok, [String.trim(id) | acc]}

      _, {:error, _} = err ->
        err
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      _ -> {:error, :invalid_csv}
    end
  end

  defp group_path(org, product, deployment_group, tab \\ nil)

  defp group_path(org, product, deployment_group, nil),
    do: ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}"

  defp group_path(org, product, deployment_group, "releases"),
    do: ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases"

  defp group_path(org, product, deployment_group, "stats"),
    do: ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/stats"

  defp group_path(org, product, deployment_group, "activity"),
    do: ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/activity"

  defp group_path(org, product, deployment_group, "settings"),
    do: ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/settings"
end
