defmodule Beamware.Devices do
  import Ecto.Query

  alias Beamware.Devices.Device
  alias Beamware.Accounts.Tenant
  alias Beamware.Repo
  alias Ecto.Changeset

  def get_devices(%Tenant{id: tenant_id}) do
    query = from(d in Device,
                 where: d.tenant_id == ^tenant_id)

    query
    |> Repo.all()
  end

  @spec create_device(Tenant.t(), map)
  :: {:ok, Device.t()}
  |  {:error, Changeset.t()}
  def create_device(%Tenant{} = tenant, params) do
    tenant
    |> Ecto.build_assoc(:devices)
    |> Device.creation_changeset(params)
    |> Repo.insert()
  end
end
