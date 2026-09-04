defmodule NervesHub.ProductNotifications do
  import Ecto.Query

  alias NervesHub.Accounts.Scope
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Products
  alias NervesHub.Products.Notification
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  @spec subscribe(pos_integer()) :: :ok
  def subscribe(product_id) do
    :ok = Group.join(NervesHub.Group, key(product_id), %{})
  end

  @spec paginated_list(Product.t(), integer(), integer()) :: {[Notification.t()], Flop.Meta.t()}
  def paginated_list(%Product{} = product, page \\ 1, page_size \\ 25) do
    flop = %Flop{page: page, page_size: page_size}

    Notification
    |> where([n], n.product_id == ^product.id)
    |> order_by(desc: :last_occurred_at)
    |> Flop.run(flop)
  end

  @spec delete_all(Scope.t()) :: :ok
  def delete_all(%Scope{product: product, user: user}) do
    _ =
      Notification
      |> where([n], n.product_id == ^product.id)
      |> Repo.delete_all()

    _ =
      Group.dispatch(NervesHub.Group, key(product.id), %Broadcast{
        topic: topic(product.id),
        event: "dismissed",
        payload: %{dismissed_by: %{id: user.id, name: user.name}}
      })

    :ok
  end

  @spec create_device_async_bulk_create_notification!(
          product_id :: pos_integer(),
          successfully_created_count :: non_neg_integer(),
          unsuccessfully_created_count :: non_neg_integer(),
          format :: String.t()
        ) :: Notification.t()
  def create_device_async_bulk_create_notification!(
        product_id,
        successfully_created_count,
        unsuccessfully_created_count,
        format
      ) do
    [message, level] =
      case {successfully_created_count, unsuccessfully_created_count} do
        {0, 0} ->
          [
            "No devices entries were processed. Please check if the uploaded manifest was empty, or contact support if you believe this was an error with the import process.",
            :warning
          ]

        {1, 0} ->
          [
            "1 device was imported successfully. Only 1 device was detected in the manifest, please contact support if this was incorrect.",
            :info
          ]

        {successful_count, 0} ->
          [
            "All device entries were imported successfully. #{successful_count} devices have been created, along with their associated certificates.",
            :info
          ]

        {0, unsuccessful_count} ->
          [
            "All device entries (#{unsuccessful_count}) failed to import successfully. Please check if the uploaded manifest was valid, or contact support if you believe this was an error with the import process.",
            :error
          ]

        {successful_count, unsuccessful_count} ->
          [
            "#{successful_count} device#{if(successful_count > 1, do: "s")} were imported successfully, and #{unsuccessful_count} device#{if(unsuccessful_count > 1, do: "s")} failed to import. Please check if the uploaded manifest was valid, or contact support if you believe this was an error with the import process.",
            :warning
          ]
      end

    Products.get_product!(product_id)
    |> Notification.new_changeset(%{
      title: "An async bulk device import has completed.",
      message: message,
      level: level,
      metadata: %{format: format},
      event_key: "device_bulk_create-#{DateTime.utc_now() |> DateTime.to_unix()}"
    })
    |> insert_and_notify!()
  end

  @spec create_duplicate_device_identifier_notification!(
          product_id :: pos_integer(),
          identifier :: String.t(),
          auth_type :: atom()
        ) :: Notification.t()
  def create_duplicate_device_identifier_notification!(product_id, identifier, auth_type) do
    Products.get_product!(product_id)
    |> Notification.new_changeset(%{
      title: "A device failed connecting as the identifier '#{identifier}' already exists.",
      message: "Please check if you have any soft deleted devices, or choose another identifier for the device.",
      level: :warning,
      metadata: %{identifier: identifier, auth_type: auth_type},
      event_key: "duplicate_device_identifier-#{identifier}"
    })
    |> insert_and_notify!()
  end

  @spec create_wrong_websocket_host_notification!(device_info :: DeviceInfo.t(), host :: String.t()) ::
          Notification.t()
  def create_wrong_websocket_host_notification!(device_info, host) do
    %Product{id: device_info.product_id}
    |> Notification.new_changeset(%{
      title: "A device connected to the wrong host.",
      message:
        "The device with the identifier '#{device_info.device_identifier}' connected to the management host instead of '#{host}', and was redirected. Please update the device's configuration.",
      level: :warning,
      metadata: %{identifier: device_info.device_identifier, host: host},
      event_key: "wrong_websocket_host-#{device_info.device_identifier}"
    })
    |> insert_and_notify!()
  end

  @spec create_soft_deleted_device_removed!(device :: Device.t()) :: Notification.t()
  def create_soft_deleted_device_removed!(device) do
    %Product{id: device.product_id}
    |> Notification.new_changeset(%{
      title: "A soft-deleted device with the identifier '#{device.identifier}' has been permanently deleted.",
      message: "Soft deleted devices are permanently deleted after two weeks.",
      level: :info,
      metadata: %{identifier: device.identifier},
      event_key: "soft_deleted_device-#{device.identifier}"
    })
    |> insert_and_notify!()
  end

  @spec create_missing_firmware_metadata_notification!(device :: Device.t()) :: Notification.t()
  def create_missing_firmware_metadata_notification!(device) do
    %Product{id: device.product_id}
    |> Notification.new_changeset(%{
      title: "A device connected without any firmware metadata.",
      message:
        "The device with the identifier '#{device.identifier}' connected but reported no firmware metadata (e.g. its uboot env had no `nerves_fw_uuid`). This is unexpected — please check the device's firmware.",
      level: :warning,
      metadata: %{identifier: device.identifier},
      event_key: "missing_firmware_metadata-#{device.identifier}"
    })
    |> insert_and_notify!()
  end

  @doc """
  A device could not be moved off an update mode its firmware cannot support.

  The device is stranded until someone acts: its deployment group will not push
  to it, and its firmware has no way to ask. Raised to the operator because
  nothing else will notice — the device goes on connecting perfectly happily.
  """
  def create_update_mode_revert_failed_notification!(device) do
    %Product{id: device.product_id}
    |> Notification.new_changeset(%{
      title: "A device could not be returned to automatic updates.",
      message:
        "The device with the identifier '#{device.identifier}' is set to manage its own updates, but is running firmware too old to do so. NervesHub tried to return it to automatic updates and could not, so it will receive no firmware at all until this is resolved. Set its update mode manually, or send it firmware by hand.",
      level: :error,
      metadata: %{identifier: device.identifier},
      event_key: "update_mode_revert_failed-#{device.identifier}"
    })
    |> insert_and_notify!()
  end

  @doc """
  A device reported metric names too long to store.

  The readings were discarded; the rest of the report was kept. Raised to the
  operator because nothing else would notice -- the device goes on reporting
  perfectly happily, and the missing readings look like a metric the firmware
  simply does not collect.

  Deduplicated on the *device*, not on the offending name. A client generating
  unbounded names would otherwise get a notification row per name, which is the
  unbounded growth the cap exists to prevent.
  """
  @spec create_oversized_metric_keys_notification!(DeviceInfo.t(), String.t(), pos_integer(), pos_integer()) ::
          Notification.t()
  def create_oversized_metric_keys_notification!(device_info, example_key, count, max_bytes) do
    %Product{id: device_info.product_id}
    |> Notification.new_changeset(%{
      title: "A device reported metric names that were too long to store.",
      message:
        "The device with the identifier '#{device_info.device_identifier}' sent #{count} " <>
          "metric#{if count > 1, do: "s"} whose names are longer than #{max_bytes} bytes, " <>
          "starting with '#{String.slice(example_key, 0, 64)}'. Those readings were discarded, " <>
          "and the rest of the report was stored. Please shorten the metric names the device reports.",
      level: :warning,
      metadata: %{
        identifier: device_info.device_identifier,
        example_key: String.slice(example_key, 0, 256),
        count: count,
        max_bytes: max_bytes
      },
      event_key: "oversized_metric_keys-#{device_info.device_identifier}"
    })
    |> insert_and_notify!()
  end

  @doc """
  A workflow stopped part-way through a rollout and is waiting on a person.

  Raised to the operator because nothing else will notice. A halted workflow is
  quiet: devices carry on connecting, the deployment group still says it is
  active, and the only sign is a diagram nobody is looking at.
  """
  def create_workflow_halted_notification!(deployment_group, step, reason) do
    {title, message, level} = workflow_halted_copy(deployment_group, step, reason)

    %Product{id: deployment_group.product_id}
    |> Notification.new_changeset(%{
      title: title,
      message: message,
      level: level,
      metadata: %{
        deployment_group: deployment_group.name,
        step_number: step.number,
        step: DeploymentWorkflowStep.label(step)
      },
      # Keyed to the step rather than the deployment group, so a workflow that
      # stops twice at different stages says so twice.
      event_key: workflow_halted_key(deployment_group.id, step.id)
    })
    |> insert_and_notify!()
  end

  @doc """
  A device reported more metrics in one report than will be stored.

  The report is kept, trimmed to the first `max_keys` names in sorted order --
  so the same readings are dropped every time rather than an arbitrary subset
  that changes shape between reports.

  Deduplicated on the device, for the same reason as
  `create_oversized_metric_keys_notification!/4`.
  """
  @spec create_too_many_metrics_notification!(DeviceInfo.t(), pos_integer(), pos_integer()) :: Notification.t()
  def create_too_many_metrics_notification!(device_info, reported, max_keys) do
    %Product{id: device_info.product_id}
    |> Notification.new_changeset(%{
      title: "A device reported more metrics than NervesHub will store.",
      message:
        "The device with the identifier '#{device_info.device_identifier}' sent #{reported} metrics " <>
          "in one report, and NervesHub stores at most #{max_keys}. The report was trimmed to the " <>
          "first #{max_keys} metric names in alphabetical order, so the same readings are dropped " <>
          "each time. Reduce what the device reports, or raise the limit for this deployment.",
      level: :warning,
      metadata: %{identifier: device_info.device_identifier, reported: reported, max_keys: max_keys},
      event_key: "too_many_metrics-#{device_info.device_identifier}"
    })
    |> insert_and_notify!()
  end

  @doc """
  Take back the notice that a workflow had stopped.

  Raised when a workflow stops and cleared when it starts again, so the list
  reflects what needs attention now rather than everything that ever did. The
  same key the notice was raised under finds it, whether it was raised once or
  coalesced from several.
  """
  @spec resolve_workflow_halted_notification!(pos_integer(), pos_integer(), pos_integer()) :: :ok
  def resolve_workflow_halted_notification!(product_id, deployment_group_id, step_id) do
    resolve!(product_id, workflow_halted_key(deployment_group_id, step_id))
  end

  defp resolve!(product_id, event_key) do
    {deleted, _} =
      Notification
      |> where([n], n.product_id == ^product_id and n.event_key == ^event_key)
      |> Repo.delete_all()

    if deleted > 0 do
      _ =
        Group.dispatch(NervesHub.Group, key(product_id), %Broadcast{
          topic: topic(product_id),
          event: "resolved",
          payload: %{}
        })
    end

    :ok
  end

  defp workflow_halted_key(deployment_group_id, step_id) do
    "workflow_halted-#{deployment_group_id}-#{step_id}"
  end

  defp workflow_halted_copy(deployment_group, step, {:failed, failed_count}) do
    {"A deployment workflow stopped after devices failed to update.",
     "Step #{step.number} ('#{DeploymentWorkflowStep.label(step)}') of the workflow for deployment group '#{deployment_group.name}' failed: #{failed_count} device(s) could not take the update. No further devices will be updated for this release until the step is retried or skipped.",
     :error}
  end

  defp workflow_halted_copy(deployment_group, step, :awaiting_approval) do
    {"A deployment workflow is waiting for approval.",
     "Step #{step.number} ('#{DeploymentWorkflowStep.label(step)}') of the workflow for deployment group '#{deployment_group.name}' needs approving before the rollout continues. No further devices will be updated for this release until it is approved or skipped.",
     :info}
  end

  defp insert_and_notify!(changeset) do
    conflict_query =
      Notification
      |> update([n],
        set: [
          last_occurred_at: fragment("EXCLUDED.last_occurred_at"),
          occurrence_count: fragment("?.occurrence_count + 1", n)
        ]
      )

    notification =
      Repo.insert!(changeset,
        on_conflict: conflict_query,
        conflict_target: [:product_id, :event_key]
      )

    _ =
      Group.dispatch(NervesHub.Group, key(notification.product_id), %Broadcast{
        topic: topic(notification.product_id),
        event: "created",
        payload: %{}
      })

    notification
  end

  # Group key. "/" is Group's hierarchy separator, matching the other pub/sub
  # wrappers.
  defp key(product_id), do: "product_notifications/#{product_id}"

  # Preserved as the previous `Phoenix.PubSub` topic string.
  defp topic(product_id), do: "product_notifications:#{product_id}"

  def count(product) do
    Notification
    |> where(product_id: ^product.id)
    |> Repo.aggregate(:count)
  end
end
