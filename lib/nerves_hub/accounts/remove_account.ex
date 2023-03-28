defmodule NervesHub.Accounts.RemoveAccount do
  import Ecto.{Query, Changeset}
  alias Ecto.Multi

  alias NervesHub.{
    Accounts,
    Firmwares,
    Deployments.Deployment,
    Products,
    Repo,
    OrgKey,
    Devices
  }

  alias Firmwares.{Firmware, FirmwareDelta, FirmwareTransfer}
  alias Accounts.{Org, OrgUser, OrgKey, Invite, User, OrgMetric}
  alias Devices.{DeviceCertificate, Device, CACertificate}
  alias Products.{Product, ProductUser}

  def remove_account(user_id) do
    Multi.new()
    |> Multi.run(:user_id, fn _, _ -> {:ok, user_id} end)
    |> Multi.run(:org_ids, &get_org_ids/2)
    |> Multi.run(:firmware_ids, &get_firmware_ids/2)
    |> Multi.delete_all(:invites, &query_by_org_id(Invite, &1))
    |> Multi.delete_all(:device_certificates, &query_by_org_id(DeviceCertificate, &1))
    |> Multi.delete_all(:ca_certificates, &query_by_org_id(CACertificate, &1))
    |> Multi.delete_all(:deployments, &query_by_org_id(Deployment, &1))
    |> Multi.delete_all(:firmware_deltas, &query_firmware_deltas/1)
    |> Multi.delete_all(:firmware_transfers, &query_by_org_id(FirmwareTransfer, &1))
    |> Multi.merge(&delete_firmwares/1)
    |> Multi.delete_all(:product_users, &query_product_users/1)
    |> Multi.delete_all(:org_keys, &query_by_org_id(OrgKey, &1))
    |> Multi.delete_all(:org_metrics, &query_by_org_id(OrgMetric, &1))
    |> Multi.update_all(:soft_delete_products, &soft_delete_by_org_id(Product, &1), [])
    |> Multi.update_all(:soft_delete_devices, &soft_delete_by_org_id(Device, &1), [])
    |> Multi.update_all(:soft_delete_org_users, &soft_delete_by_org_id(OrgUser, &1), [])
    |> Multi.update_all(:soft_delete_orgs, &soft_delete_orgs(&1), [])
    |> Multi.update(:soft_delete_user, &soft_delete_user/1)
    |> Repo.transaction()
  end

  defp query_org_users do
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

  defp delete_firmwares(%{firmware_ids: firmware_ids}) do
    Enum.reduce(firmware_ids, Multi.new(), fn firmware_id, multi ->
      multi_key = "delete_firmware_#{firmware_id}"

      Multi.run(multi, multi_key, fn _, _ ->
        Firmware
        |> Repo.get(firmware_id)
        |> Firmwares.delete_firmware()
      end)
    end)
  end

  defp truncated_utc_now do
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

  defp query_by_org_id(queryable, %{org_ids: ids}) do
    query_by_org_id(queryable, ids)
  end

  defp query_by_org_id(queryable, ids) when is_list(ids) do
    where(queryable, [d], d.org_id in ^ids)
  end

  defp query_product_users(%{user_id: id}), do: where(ProductUser, user_id: ^id)

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
