defmodule NervesHub.Accounts.RemoveAccount do
  import Ecto.Changeset
  import Ecto.Query

  alias Ecto.Multi
  alias NervesHub.Accounts.Invite
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.OrgMetric
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceFirmware
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.PinnedDevice
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.FirmwareTransfer
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Scripts.Script
  alias NervesHub.Workers.DeleteFirmware

  def remove_account(user_id) do
    Multi.new()
    |> Multi.run(:user_id, fn _, _ -> {:ok, user_id} end)
    |> Multi.run(:org_ids, &get_org_ids/2)
    |> Multi.run(:firmware_ids, &get_firmware_ids/2)
    |> Multi.delete_all(:invites, &query_by_org_id(Invite, &1))
    |> Multi.delete_all(:device_certificates, &query_by_org_id(DeviceCertificate, &1))
    |> Multi.delete_all(:ca_certificates, &query_by_org_id(CACertificate, &1))
    |> Multi.delete_all(:deployment_groups, &query_by_org_id(DeploymentGroup, &1))
    |> Multi.delete_all(:firmware_deltas, &query_firmware_deltas/1)
    |> Multi.delete_all(:firmware_transfers, &query_by_org_id(FirmwareTransfer, &1))
    |> Multi.delete_all(:pinned_devices, &query_by_user_id(PinnedDevice, &1))
    # Devices are only soft deleted below, so nothing cascades their firmware
    # history or in-flight updates away. Both reference `firmwares`, and the
    # rows have to go before the firmware they name can.
    |> Multi.delete_all(:device_firmwares, &query_device_firmwares/1)
    |> Multi.delete_all(:inflight_updates, &query_inflight_updates/1)
    |> Multi.merge(&delete_firmwares/1)
    |> Multi.delete_all(:org_keys, &query_by_org_id(OrgKey, &1))
    |> Multi.delete_all(:org_metrics, &query_by_org_id(OrgMetric, &1))
    |> Multi.update_all(:soft_delete_products, &soft_delete_by_org_id(Product, &1), [])
    |> Multi.update_all(:soft_delete_devices, &soft_delete_by_org_id(Device, &1), [])
    |> Multi.update_all(:soft_delete_org_users, &soft_delete_by_org_id(OrgUser, &1), [])
    |> Multi.update_all(:soft_delete_orgs, &soft_delete_orgs/1, [])
    |> Multi.update_all(:nilify_script_creations, &nilify_script_creations/1, [])
    |> Multi.update_all(:nilify_script_edits, &nilify_script_edits/1, [])
    |> Multi.update(:soft_delete_user, &soft_delete_user/1)
    |> Repo.transact()
  end

  defp query_org_users() do
    from(
      org_user in OrgUser,
      join: user in assoc(org_user, :user),
      where: is_nil(user.deleted_at),
      select: org_user.org_id
    )
  end

  defp get_org_ids(repo, %{user_id: user_id}) do
    where_org_has_users = where(query_org_users(), [ou], ou.user_id != ^user_id)

    query =
      query_org_users()
      |> where([ou], ou.user_id == ^user_id)
      |> except(^where_org_has_users)

    {:ok, repo.all(query)}
  end

  defp get_firmware_ids(repo, %{org_ids: org_ids}) do
    query =
      from(
        firmware in Firmware,
        where: firmware.org_id in ^org_ids,
        select: firmware.id
      )

    {:ok, repo.all(query)}
  end

  defp query_device_firmwares(%{org_ids: org_ids}) do
    from(
      device_firmware in DeviceFirmware,
      join: device in assoc(device_firmware, :device),
      where: device.org_id in ^org_ids
    )
  end

  defp query_inflight_updates(%{org_ids: org_ids}) do
    from(
      inflight_update in InflightUpdate,
      join: device in assoc(inflight_update, :device),
      where: device.org_id in ^org_ids
    )
  end

  # Closing an account destroys the firmware outright rather than soft deleting
  # it the way `NervesHub.Firmwares.delete_firmware/2` does. A soft delete keeps
  # the row so device history survives, but nothing here is meant to survive —
  # and a surviving row would hold the org keys, which are deleted next.
  #
  # Firmware already soft deleted has had its file queued once; queueing it again
  # would put the worker to work on a file that is not there.
  defp delete_firmwares(%{firmware_ids: firmware_ids}) do
    Multi.new()
    |> Multi.run(:queue_firmware_file_deletions, fn repo, _ ->
      jobs =
        Firmware
        |> where([f], f.id in ^firmware_ids)
        |> where([f], is_nil(f.deleted_at))
        |> select([f], f.upload_metadata)
        |> repo.all()
        |> Enum.map(&DeleteFirmware.new/1)
        |> Oban.insert_all()

      {:ok, jobs}
    end)
    |> Multi.delete_all(:firmwares, where(Firmware, [f], f.id in ^firmware_ids))
  end

  defp truncated_utc_now() do
    DateTime.truncate(DateTime.utc_now(), :second)
  end

  defp soft_delete_user(%{user_id: user_id}) do
    User
    |> Repo.get!(user_id)
    |> change(deleted_at: truncated_utc_now())
  end

  defp soft_delete_by_org_id(queryable, %{org_ids: org_ids}) do
    queryable
    |> query_by_org_id(org_ids)
    |> update(set: [deleted_at: ^truncated_utc_now()])
  end

  defp soft_delete_orgs(%{org_ids: ids}) do
    Org
    |> where([o], o.id in ^ids)
    |> update(set: [deleted_at: ^truncated_utc_now()])
  end

  defp nilify_script_creations(%{user_id: user_id}) do
    Script
    |> where(created_by_id: ^user_id)
    |> update(set: [created_by_id: nil])
  end

  defp nilify_script_edits(%{user_id: user_id}) do
    Script
    |> where(last_updated_by_id: ^user_id)
    |> update(set: [last_updated_by_id: nil])
  end

  defp query_by_org_id(queryable, %{org_ids: ids}) do
    query_by_org_id(queryable, ids)
  end

  defp query_by_org_id(queryable, ids) when is_list(ids) do
    where(queryable, [d], d.org_id in ^ids)
  end

  defp query_by_user_id(queryable, %{user_id: user_id}) do
    where(queryable, [d], d.user_id == ^user_id)
  end

  defp query_firmware_deltas(%{org_ids: ids}) do
    join(
      FirmwareDelta,
      :inner,
      [fp],
      f in Firmware,
      on: fp.target_id == f.id and f.org_id in ^ids
    )
  end
end
