defmodule Beamware.Devices do
  import Ecto.Query

  alias Beamware.Devices.Device
  alias Beamware.Accounts.Tenant
  alias Beamware.Repo
  alias Ecto.Changeset

  def get_devices(%Tenant{id: tenant_id}) do
    query = from(d in Device, where: d.tenant_id == ^tenant_id)

    query
    |> Repo.all()
  end

  def get_device(%Tenant{id: tenant_id}, device_id) do
    query =
      from(
        d in Device,
        where: d.tenant_id == ^tenant_id,
        where: d.id == ^device_id
      )

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @spec get_device_by_identifier(String.t()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_identifier(identifier) when is_binary(identifier) do
    query = from(d in Device, where: d.identifier == ^identifier)

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @spec create_device(Tenant.t(), map) ::
          {:ok, Device.t()}
          | {:error, Changeset.t()}
  def create_device(%Tenant{} = tenant, params) do
    tenant
    |> Ecto.build_assoc(:devices)
    |> Device.creation_changeset(params)
    |> Repo.insert()
  end

  def update_device(%Device{} = device, params) do
    device
    |> Device.update_changeset(params)
    |> Repo.update()
  end
end
