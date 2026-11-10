defmodule NervesHub.Repo.Migrations.RemoveDevicesFromOtherProductsDeploymentGroups do
  @moduledoc """
  Take devices out of deployment groups that belong to another product, and
  list the devices in another org's product.

  A device in another product's group is sent that product's firmware, which
  may be another org's. Moving a device to another product clears its group, so
  no device should be in one, but before GHSA-rpp7-x9hm-jrmr was fixed a
  device's group could be set from request params.

  `ManagedDeployments.verify_deployment_group_membership/1` takes such a device
  out when it connects. This clears the rest now, including devices that stay
  connected through a deploy and devices that never connect again.

  Each device cleared is logged with the group it was in, since this removes the
  only record of it.

  Request params could also set a device's product without its org, and a CA's
  JITP settings could name another org's product. A device left that way is
  refused when it connects (`NervesHub.DeviceLink.Authentication`) and shows in
  neither org's device list, so this logs each one and changes nothing: only
  someone who knows where the device came from can say which org it belongs in.
  """

  use Ecto.Migration

  require Logger

  def up() do
    %{rows: rows} =
      repo().query!("""
      UPDATE devices AS d
      SET deployment_id = NULL, updated_at = timezone('utc', now())
      FROM deployments AS dg
      WHERE dg.id = d.deployment_id AND dg.product_id <> d.product_id
      RETURNING d.id, d.identifier, d.org_id, d.product_id, dg.id, dg.org_id, dg.product_id
      """)

    Enum.each(rows, fn [device_id, identifier, org_id, product_id, group_id, group_org_id, group_product_id] ->
      Logger.warning(
        "Removed device #{device_id} (#{identifier}, org #{org_id}, product #{product_id}) " <>
          "from deployment group #{group_id} (org #{group_org_id}, product #{group_product_id})"
      )
    end)

    %{rows: rows} =
      repo().query!("""
      SELECT d.id, d.identifier, d.org_id, d.product_id, p.org_id
      FROM devices AS d
      JOIN products AS p ON p.id = d.product_id
      WHERE p.org_id <> d.org_id AND d.deleted_at IS NULL
      """)

    Enum.each(rows, fn [device_id, identifier, org_id, product_id, product_org_id] ->
      Logger.warning(
        "Device #{device_id} (#{identifier}, org #{org_id}) is in product #{product_id} " <>
          "of org #{product_org_id}, and is refused when it connects"
      )
    end)
  end

  # The cleared groups were never valid, so there is nothing to put back.
  def down(), do: :ok
end
